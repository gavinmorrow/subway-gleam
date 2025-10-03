import gleam/erlang/process
import gleam/float
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/pair
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
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
  InvalidStopId(StopId)
}

fn handler(req: wisp.Request) -> wisp.Response {
  use req <- routing.middleware(req)

  let body = case wisp.path_segments(req) {
    [] -> "subways! yay!"
    ["stop", stop_id] -> {
      let gtfs = {
        use feed <- result.try(
          gtfs_rt_feed_from_stop_id(stop_id)
          |> result.replace_error(InvalidStopId(stop_id)),
        )
        use bits <- result.try(
          fetch_gtfs_rt_bin(feed) |> result.map_error(HttpError),
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
        |> result.map(trains_stopping(_, at: stop_id))
        |> result.map(
          list.sort(_, by: fn(a, b) {
            timestamp.compare(a.time, b.time) |> order.negate
          }),
        )
        |> result.map(
          list.fold(_, from: #([], []), with: fn(acc, update) {
            let TrainStopping(trip:, time:, stop_id:) = update
            let #(uptown_acc, downtown_acc) = acc
            let text =
              trip.route_id
              <> ": "
              <> time
              |> timestamp.difference(timestamp.system_time(), _)
              |> duration.to_seconds()
              |> float.divide(60.0)
              |> result.unwrap(0.0)
              |> float.round
              |> int.to_string
              <> "min ("
              <> time
              |> timestamp.to_calendar(calendar.local_offset())
              |> pair.second
              |> string.inspect
              <> ")"
            case stop_id |> string.ends_with("N") {
              True -> #([text, ..uptown_acc], downtown_acc)
              False -> #(uptown_acc, [text, ..downtown_acc])
            }
          }),
        )
        |> result.map(pair.map_first(_, list.take(_, 10)))
        |> result.map(pair.map_second(_, list.take(_, 10)))

      case gtfs {
        Ok(#(uptown, downtown)) ->
          "<h1>Stopping at stop #"
          <> stop_id
          <> ":</h1><h2>Uptown</h2>"
          <> uptown |> list.fold("", fn(acc, text) { acc <> "</br>" <> text })
          <> "<br/><h2>Downtown</h2>"
          <> downtown |> list.fold("", fn(acc, text) { acc <> "</br>" <> text })
        Error(err) -> "Error: " <> string.inspect(err)
      }
    }
    _ -> "404 not found :["
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

fn gtfs_rt_feed_from_stop_id(stop_id: StopId) -> Result(GtfsRtFeed, Nil) {
  use #(route_id, stop_num) <- result.try(stop_id |> string.pop_grapheme)
  use stop_num <- result.try(
    stop_num
    |> string.slice(at_index: 0, length: 2)
    |> int.parse,
  )
  case route_id {
    "A" | "C" | "E" -> ACESr |> Ok
    "B" | "D" | "F" | "M" -> BDFMSf |> Ok
    "G" -> G |> Ok
    "J" | "Z" -> JZ |> Ok
    "N" | "Q" | "R" | "W" -> NQRW |> Ok
    "L" -> L |> Ok
    "1" | "2" | "3" | "4" | "5" | "6" | "7" -> S1234567 |> Ok

    // In the GTFS, the Sf and Sir routes have the same prefix (S).
    // The Sf gets stop numbers [1, 8] while the Sir gets [9, 31].
    // The normal S gets the prefix 9, while Sr gets H (which it shares with
    // both Far-Rockaway-bound and Rockaway-Park-bound A trains).
    "H" -> ACESr |> Ok
    "9" -> S1234567 |> Ok
    "S" if stop_num < 9 -> BDFMSf |> Ok
    "S" if stop_num >= 9 -> Si |> Ok

    _ -> Error(Nil)
  }
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

type StopId =
  String

type TrainStopping {
  TrainStopping(
    trip: gtfs_rt_nyct.TripDescriptor,
    time: timestamp.Timestamp,
    stop_id: StopId,
  )
}

fn trains_stopping(
  feed: gtfs_rt_nyct.FeedMessage,
  at stop_id: StopId,
) -> List(TrainStopping) {
  use acc, entity <- list.fold(over: feed.entity, from: [])

  case entity.data {
    gtfs_rt_nyct.TripUpdate(trip:, stop_time_updates:) -> {
      let is_stop = fn(update: gtfs_rt_nyct.StopTimeUpdate) {
        update.stop_id |> string.starts_with(stop_id)
      }

      let stop = {
        use stop <- result.try(list.find(stop_time_updates, one_that: is_stop))

        let stop_time_event =
          stop.arrival |> option.or(stop.departure) |> option.to_result(Nil)
        use gtfs_rt_nyct.StopTimeEvent(unix) <- result.try(stop_time_event)

        let gtfs_rt_nyct.UnixTime(unix_secs) = unix
        let time = timestamp.from_unix_seconds(unix_secs)

        TrainStopping(trip:, time:, stop_id: stop.stop_id) |> Ok
      }

      case stop {
        Ok(stop) -> [stop, ..acc]
        Error(Nil) -> acc
      }
    }
    _ -> acc
  }
}
