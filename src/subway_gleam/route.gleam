import gleam/float
import gleam/http/request
import gleam/http/response
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
import lustre/element
import lustre/element/html
import protobin
import wisp

pub fn lustre_res(
  req: wisp.Request,
  handle_request: fn(wisp.Request) -> #(element.Element(msg), wisp.Response),
) -> wisp.Response {
  let #(html, res) = handle_request(req)

  response.set_body(
    res,
    html
      |> element.to_document_string
      |> wisp.Text,
  )
}

pub fn middleware(
  req: wisp.Request,
  handle_request: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  use <- wisp.rescue_crashes
  use req <- wisp.csrf_known_header_protection(req)

  handle_request(req)
}

pub fn index(req: wisp.Request) -> wisp.Response {
  use _req <- lustre_res(req)

  let body = html.p([], [html.text("subways! yay!")])
  let res = wisp.response(200)

  #(body, res)
}

pub fn not_found(req: wisp.Request) -> wisp.Response {
  use _req <- lustre_res(req)

  let body = html.p([], [html.text("404 not found :[")])
  let res = wisp.response(404)

  #(body, res)
}

pub fn stop(req: wisp.Request, stop_id: StopId) -> wisp.Response {
  use _req <- lustre_res(req)

  let data = {
    use feed <- result.try(
      gtfs_rt_feed_from_stop_id(stop_id)
      |> result.replace_error(InvalidStopId(stop_id)),
    )
    use gtfs <- result.map(fetch_gtfs(feed:))

    gtfs
    |> trains_stopping(at: stop_id)
    |> list.sort(by: fn(a, b) {
      timestamp.compare(a.time, b.time) |> order.negate
    })
    |> list.fold(from: #([], []), with: fn(acc, update) {
      let #(uptown_acc, downtown_acc) = acc
      let text = describe_arrival(update)
      case update.stop_id |> string.ends_with("N") {
        True -> #([text, ..uptown_acc], downtown_acc)
        False -> #(uptown_acc, [text, ..downtown_acc])
      }
    })
    |> pair.map_first(list.take(_, 10))
    |> pair.map_second(list.take(_, 10))
  }

  let body = case data {
    Ok(#(uptown, downtown)) ->
      element.fragment([
        html.h1([], [html.text("Stopping at stop #" <> stop_id <> ":")]),
        html.h2([], [html.text("Uptown")]),
        html.ul(
          [],
          uptown
            |> list.map(html.text)
            |> list.map(fn(text) { html.li([], [text]) }),
        ),
        html.h2([], [html.text("Downtown")]),
        html.ul(
          [],
          downtown
            |> list.map(html.text)
            |> list.map(fn(text) { html.li([], [text]) }),
        ),
      ])
    Error(err) -> html.p([], [html.text("Error: " <> string.inspect(err))])
  }

  #(body, wisp.response(200))
}

type TrainStopping {
  TrainStopping(
    trip: gtfs_rt_nyct.TripDescriptor,
    time: timestamp.Timestamp,
    stop_id: StopId,
  )
}

type StopId =
  String

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

type FetchGtfsError {
  HttpError(httpc.HttpError)
  ParseError(protobin.ParseError)
  InvalidStopId(StopId)
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

fn fetch_gtfs_rt_bin(feed: GtfsRtFeed) -> Result(BitArray, httpc.HttpError) {
  let req: request.Request(BitArray) =
    request.new()
    |> request.set_host("api-endpoint.mta.info")
    |> request.set_path(gtfs_rt_feed_path(feed))
    |> request.set_body(<<>>)

  use res <- result.try(httpc.send_bits(req))
  res.body |> Ok
}

fn fetch_gtfs(
  feed feed: GtfsRtFeed,
) -> Result(gtfs_rt_nyct.FeedMessage, FetchGtfsError) {
  use bits <- result.try(fetch_gtfs_rt_bin(feed) |> result.map_error(HttpError))
  protobin.parse_with_config(
    from: bits,
    using: gtfs_rt_nyct.feed_message_decoder(),
    config: protobin.Config(ignore_groups: True),
  )
  |> result.map(fn(parsed) { parsed.value })
  |> result.map_error(ParseError)
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

fn describe_arrival(update: TrainStopping) -> String {
  let TrainStopping(trip:, time:, stop_id: _) = update

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
}
