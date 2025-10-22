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
      |> list.find(fn(stop) { stop.id == stop_id })
      |> result.replace_error(rt.UnknownStop(stop_id)),
    )

    // TODO: don't parse new gtfs every request
    let feed = rt.gtfs_rt_feed_from_stop_id(stop_id)
    use gtfs <- result.map(rt.fetch_gtfs(feed:))

    #(
      stop,
      gtfs
        |> rt.trains_stopping(at: stop_id)
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
          let li = arrival_li(update, state.schedule.trips)
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
    )
  }

  let head = case data {
    Ok(#(stop, _)) -> [html.title([], "Trains at " <> stop.name)]
    Error(_) -> [html.title([], "Error!")]
  }

  let body = case data {
    Ok(#(stop, #(uptown, downtown))) -> [
      html.h1([], [
        html.text(stop.name),
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
  trips: st.Trips,
) -> List(element.Element(msg)) {
  let rt.TrainStopping(trip:, time:, stop_id: _) = update

  let headsign = {
    use shape_id <- result.try(
      trip.trip_id
      |> string.split(on: "_")
      |> list.last
      |> result.map(st.ShapeId),
    )
    use headsign <- result.map(trips.headsigns |> dict.get(shape_id))
    html.span([], [html.text(headsign)])
  }

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
  ]
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
