import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/pair
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import gleam/uri
import lustre/attribute
import lustre/element
import lustre/element/html
import subway_gleam/st
import wisp

import subway_gleam/lustre_middleware.{Body, Document, lustre_res}
import subway_gleam/rt
import subway_gleam/state

pub fn index(req: wisp.Request) -> wisp.Response {
  use _req <- lustre_res(req)

  let body = [html.p([], [html.text("subways! yay!")])]
  let res = wisp.response(200)

  #(Body(body:), res)
}

pub fn not_found(req: wisp.Request) -> wisp.Response {
  use _req <- lustre_res(req)

  let body = [html.p([], [html.text("404 not found :[")])]
  let res = wisp.response(404)

  #(Body(body:), res)
}

pub fn stop(
  req: wisp.Request,
  state: state.State,
  stop_id: String,
) -> wisp.Response {
  use req <- lustre_res(req)

  // TODO: make this a function?
  let highlighted_train =
    req.query
    |> option.to_result(Nil)
    |> result.try(uri.parse_query)
    |> result.unwrap(or: [])
    |> list.key_find("train_id")
    |> result.try(uri.percent_decode)
    |> result.map(rt.TrainId)

  let data = {
    use stop_id <- result.try(
      st.parse_stop_id(stop_id)
      |> result.replace_error(rt.InvalidStopId(stop_id)),
    )
    use stop <- result.try(
      state.schedule.stops
      |> dict.get(stop_id)
      |> result.replace_error(rt.UnknownStop(stop_id)),
    )

    let state.RtData(current: gtfs, last_updated:) = state.fetch_gtfs(state)

    Ok(#(
      stop,
      last_updated,
      gtfs.arrivals
        |> dict.get(stop_id)
        |> result.unwrap(or: [])
        |> list.sort(by: fn(a, b) {
          timestamp.compare(a.time, b.time) |> order.negate
        })
        |> list.filter(keeping: fn(a) {
          // Strip out times that are in the past
          case timestamp.compare(a.time, timestamp.system_time()) {
            order.Eq | order.Gt -> True
            order.Lt -> False
          }
        })
        |> list.fold(from: #([], []), with: fn(acc, update) {
          let #(uptown_acc, downtown_acc) = acc
          let li = arrival_li(update, state.schedule, gtfs, highlighted_train)
          case update.stop_id.direction {
            // Treat no direction as uptown
            // TODO: figure out what should be done here. is it even be possible?
            option.Some(st.North) | option.None -> #(
              [li, ..uptown_acc],
              downtown_acc,
            )
            option.Some(st.South) -> #(uptown_acc, [li, ..downtown_acc])
          }
        })
        |> pair.map_first(list.take(_, 10))
        |> pair.map_second(list.take(_, 10)),
    ))
  }

  let head = case data {
    Ok(#(stop, _, _)) -> [html.title([], "Trains at " <> stop.name)]
    Error(_) -> [html.title([], "Error!")]
  }

  let body = case data {
    Ok(#(stop, last_updated, #(uptown, downtown))) -> [
      html.h1([], [
        html.text(stop.name),
      ]),
      html.p([], [
        html.text(
          "Last updated "
          <> { last_updated |> timestamp.to_rfc3339(duration.hours(-4)) },
        ),
      ]),
      html.h2([], [html.text("Uptown")]),
      html.ul([attribute.class("arrival-list")], uptown),
      html.h2([], [html.text("Downtown")]),
      html.ul([attribute.class("arrival-list")], downtown),
    ]
    Error(err) -> [html.p([], [html.text("Error: " <> string.inspect(err))])]
  }

  #(Document(head:, body:), wisp.response(200))
}

fn arrival_li(
  update: rt.TrainStopping,
  schedule: st.Schedule,
  gtfs: rt.Data,
  highlighted_train: Result(rt.TrainId, Nil),
) -> element.Element(msg) {
  let rt.TrainStopping(trip:, time:, stop_id: _) = update

  let headsign = {
    use shape_id <- result.try(st.parse_shape_id(from: trip.trip_id))
    let headsign =
      schedule.trips.headsigns
      |> dict.get(shape_id)
      |> result.lazy_or(fn() {
        dict.get(gtfs.final_stops, shape_id)
        |> result.try(dict.get(schedule.stops, _))
        |> result.map(fn(stop) { stop.name })
        // TODO: maybe don't want to always have a value?
        |> result.unwrap(or: "<Unknown stop>")
        |> Ok
      })
    use headsign <- result.map(headsign)
    html.span([], [html.text(headsign)])
  }

  let train_id_percent_encode =
    update.trip.nyct.train_id
    |> option.map(uri.percent_encode)
  let train_url =
    train_id_percent_encode
    |> option.map(fn(id) {
      let query =
        uri.query_to_string([
          #("stop_id", update.stop_id |> st.stop_id_to_string),
        ])
      "/train/" <> id <> "?" <> query
    })
    |> option.unwrap(or: "")

  let train_id = update.trip.nyct.train_id |> option.map(rt.TrainId)
  let is_highlighted = case train_id, highlighted_train {
    option.Some(train_id), Ok(highlight) -> train_id == highlight
    _, _ -> False
  }

  html.li([], [
    html.a(
      [
        attribute.href(train_url),
        attribute.classes([#("highlight", is_highlighted)]),
      ],
      [
        route_bullet(trip.route_id),
        headsign |> result.unwrap(or: element.none()),
        html.span([], [
          html.text(
            time
            |> min_from_now
            |> int.to_string
            <> "min",
          ),
        ]),
      ],
    ),
  ])
}

fn route_bullet(route_id: String) -> element.Element(msg) {
  html.span([attribute.class("route-bullet")], [html.text(route_id)])
}

fn min_from_now(time: timestamp.Timestamp) -> Int {
  time
  |> timestamp.difference(timestamp.system_time(), _)
  |> duration.to_seconds()
  |> float.divide(60.0)
  |> result.unwrap(0.0)
  |> float.round
}

pub fn train(
  req: wisp.Request,
  state: state.State,
  train_id: String,
) -> wisp.Response {
  use req <- lustre_middleware.lustre_res(req)

  // TODO: make this a function?
  let highlighted_stop =
    req.query
    |> option.to_result(Nil)
    |> result.try(uri.parse_query)
    |> result.unwrap(or: [])
    |> list.key_find("stop_id")
    |> result.try(st.parse_stop_id)

  let data = {
    let state.RtData(current: gtfs, last_updated:) = state.fetch_gtfs(state)

    use train_id <- result.try(uri.percent_decode(train_id))
    let train_id = rt.TrainId(train_id)

    let trip = dict.get(gtfs.trips, train_id)
    use stops <- result.map(trip)
    let stops =
      list.filter_map(stops, fn(arrival) {
        let stop =
          state.schedule.stops
          |> dict.get(arrival.stop_id)
        let time = arrival.time
        case time |> min_from_now {
          dt if dt >= 0 -> Ok(stop_li(stop, time, train_id, highlighted_stop))
          _ -> Error(Nil)
        }
      })

    #(stops, last_updated)
  }

  let body = case data {
    Error(Nil) -> [html.p([], [html.text("Could not find train.")])]
    Ok(#(stops, last_updated)) -> [
      html.p([], [
        html.text(
          "Last updated "
          <> last_updated |> timestamp.to_rfc3339(duration.hours(-4)),
        ),
      ]),
      html.ol([attribute.class("stops-list")], stops),
    ]
  }

  #(Body(body:), wisp.response(200))
}

fn stop_li(
  stop: Result(st.Stop, Nil),
  time: timestamp.Timestamp,
  train_id: rt.TrainId,
  highlighted_stop: Result(st.StopId, Nil),
) -> element.Element(msg) {
  let stop_name =
    stop
    |> result.map(fn(stop) { stop.name })
    |> result.unwrap(or: "<Unknown stop>")
  let stop_url =
    result.map(stop, fn(stop) {
      let stop_id = stop.id |> st.erase_direction |> st.stop_id_to_string
      let train_id = train_id |> rt.train_id_to_string |> uri.percent_encode
      let query = uri.query_to_string([#("train_id", train_id)])
      "/stop/" <> stop_id <> "?" <> query
    })
    |> result.unwrap(or: "")

  let stop_id = stop |> result.map(fn(stop) { stop.id })
  let is_highlighted = case stop_id, highlighted_stop {
    Ok(stop_id), Ok(highlight) -> stop_id == highlight
    _, _ -> False
  }

  html.li([], [
    html.a(
      [
        attribute.href(stop_url),
        attribute.classes([#("highlight", is_highlighted)]),
      ],
      [
        html.span([], [html.text(stop_name)]),
        html.span([], [
          html.text(time |> min_from_now |> int.to_string <> "min"),
        ]),
      ],
    ),
  ])
}
