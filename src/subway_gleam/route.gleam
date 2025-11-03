import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/otp/actor
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
  use _req <- lustre_res(req)

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
          let li = arrival_li(update, state.schedule, gtfs)
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
      html.ul(
        [attribute.class("arrival-list")],
        uptown
          |> list.map(html.li([], _)),
      ),
      html.h2([], [html.text("Downtown")]),
      html.ul(
        [attribute.class("arrival-list")],
        downtown
          |> list.map(html.li([], _)),
      ),
    ]
    Error(err) -> [html.p([], [html.text("Error: " <> string.inspect(err))])]
  }

  #(Document(head:, body:), wisp.response(200))
}

fn arrival_li(
  update: rt.TrainStopping,
  schedule: st.Schedule,
  gtfs: rt.Data,
) -> List(element.Element(msg)) {
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

  let inner = [
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
  ]

  let train_id_percent_encode =
    update.trip.nyct.train_id
    |> option.map(uri.percent_encode)
  let train_url =
    train_id_percent_encode |> option.map(fn(id) { "/train/" <> id })

  case train_url {
    option.None -> inner
    option.Some(train_url) -> [html.a([attribute.href(train_url)], inner)]
  }
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

  let state.RtData(current: gtfs, last_updated:) = state.fetch_gtfs(state)

  let train_id = train_id |> uri.percent_decode |> result.map(rt.TrainId)
  let trip = train_id |> result.try(dict.get(gtfs.trips, _))
  let stops = {
    use stops <- result.map(trip)
    use stop <- list.map(stops)

    let stop_name =
      state.schedule.stops
      |> dict.get(stop.stop_id)
      |> result.map(fn(stop) { stop.name })
      |> result.unwrap(or: "<Unknown stop>")
    let time = stop.time
    stop_li(stop_name, time)
  }

  let stops_list = case stops {
    Error(Nil) -> html.p([], [html.text("Could not find train.")])
    Ok(stops) -> html.ol([attribute.class("stops-list")], stops)
  }
  let body = [
    html.p([], [
      html.text(
        "Last updated "
        <> last_updated |> timestamp.to_rfc3339(duration.hours(-4)),
      ),
    ]),
    stops_list,
  ]

  #(Body(body:), wisp.response(200))
}

fn stop_li(stop_name: String, time: timestamp.Timestamp) -> element.Element(msg) {
  html.li([], [
    html.span([], [html.text(stop_name)]),
    html.span([], [html.text(time |> min_from_now |> int.to_string)]),
  ])
}
