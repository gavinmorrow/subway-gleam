import gleam/erlang/process
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/string
import gtfs_rt_nyct
import mist
import protobin
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()

  let secret_key_base = wisp.random_string(64)

  let assert Ok(_) =
    wisp_mist.handler(handler, secret_key_base)
    |> mist.new
    |> mist.port(8000)
    |> mist.start

  process.sleep_forever()
}

type FetchGtfsError {
  HttpError(httpc.HttpError)
  ParseError(protobin.ParseError)
}

fn handler(req: wisp.Request) -> wisp.Response {
  use _req <- middleware(req)

  let gtfs = {
    use bits <- result.try(
      fetch_gtfs_rt_bin(S1234567) |> result.map_error(HttpError),
    )
    protobin.parse_with_config(
      from: bits,
      using: gtfs_rt_nyct.feed_message_decoder(),
      config: protobin.Config(ignore_groups: True),
    )
    |> result.map(fn(parsed) { parsed.value })
    |> result.map_error(ParseError)
  }

  let gtfs =
    gtfs
    |> result.map(trains_stopping(_, at: "635"))
    |> result.map(list.sort(_, by: sort_trip_update_by_time))
    |> result.map(
      list.fold(_, from: "", with: fn(acc, update) {
        let #(trip, update) = update
        acc
        <> trip.route_id
        <> ": "
        <> update.arrival
        |> option.map(string.inspect)
        |> option.unwrap("unknown time")
        <> "<br/>"
      }),
    )

  let body = case gtfs {
    Ok(gtfs) -> "Data: " <> string.inspect(gtfs)
    Error(err) -> "Error: " <> string.inspect(err)
  }

  wisp.html_response(body, 200)
}

fn middleware(
  req: wisp.Request,
  handle_request: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  use <- wisp.rescue_crashes
  use req <- wisp.csrf_known_header_protection(req)

  handle_request(req)
}

type GtfsRtFeed {
  ACESr
  BDFMSf
  G
  JZ
  NQRW
  L
  S1234567
  Si
}

fn gtfs_rt_feed_name(feed: GtfsRtFeed) -> String {
  case feed {
    ACESr -> "gtfs-ace"
    BDFMSf -> "gtfs-bdfm"
    G -> "gtfs-g"
    JZ -> "gtfs-jz"
    L -> "gtfs-l"
    NQRW -> "gtfs-nqrw"
    S1234567 -> "gtfs"
    Si -> "gtfs-si"
  }
}

fn gtfs_rt_feed_path(feed: GtfsRtFeed) -> String {
  "Dataservice/mtagtfsfeeds/nyct%2F" <> gtfs_rt_feed_name(feed)
}

fn fetch_gtfs_rt_bin(feed: GtfsRtFeed) -> Result(BitArray, httpc.HttpError) {
  let req: request.Request(BitArray) =
    request.new()
    |> request.set_host("api-endpoint.mta.info")
    |> request.set_path(gtfs_rt_feed_path(feed))
    |> request.set_body(<<>>)

  use res <- result.try(httpc.send_bits(req))
  res.body |> Ok
}

fn trains_stopping(
  feed: gtfs_rt_nyct.FeedMessage,
  at stop_id: String,
) -> List(#(gtfs_rt_nyct.TripDescriptor, gtfs_rt_nyct.StopTimeUpdate)) {
  use acc, entity <- list.fold(over: feed.entity, from: [])

  case entity.data {
    gtfs_rt_nyct.TripUpdate(trip:, stop_time_updates:) -> {
      let stop =
        stop_time_updates
        |> list.find(one_that: fn(update) {
          update.stop_id |> string.starts_with(stop_id)
        })
        |> result.map(fn(stop) { #(trip, stop) })

      case stop {
        Ok(stop) -> [stop, ..acc]
        Error(Nil) -> acc
      }
    }
    _ -> acc
  }
}

fn sort_trip_update_by_time(
  a: #(gtfs_rt_nyct.TripDescriptor, gtfs_rt_nyct.StopTimeUpdate),
  b: #(gtfs_rt_nyct.TripDescriptor, gtfs_rt_nyct.StopTimeUpdate),
) -> order.Order {
  let #(_, a) = a
  let #(_, b) = b

  let a =
    a.arrival
    |> option.or(a.departure)
    |> option.map(fn(stop_time_event) { stop_time_event.time })
  let b =
    b.arrival
    |> option.or(b.departure)
    |> option.map(fn(stop_time_event) { stop_time_event.time })

  case a, b {
    option.Some(gtfs_rt_nyct.UnixTime(a)), option.Some(gtfs_rt_nyct.UnixTime(b))
    -> int.compare(a, b)
    option.Some(_), option.None -> order.Gt
    option.None, option.Some(_) -> order.Lt
    option.None, option.None -> order.Eq
  }
}
