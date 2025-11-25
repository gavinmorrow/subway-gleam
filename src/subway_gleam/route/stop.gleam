import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/pair
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import gleam/uri
import lustre/attribute
import lustre/element
import lustre/element/html
import subway_gleam/component
import subway_gleam/internal/util
import subway_gleam/lustre_middleware.{Document, try_lustre_res}
import subway_gleam/rt
import subway_gleam/st
import subway_gleam/state
import wisp

pub fn stop(
  req: wisp.Request,
  state: state.State,
  stop_id: String,
) -> wisp.Response {
  use req <- try_lustre_res(req)

  // TODO: make this a function?
  let highlighted_train =
    req.query
    |> option.to_result(Nil)
    |> result.try(uri.parse_query)
    |> result.unwrap(or: [])
    |> list.key_find("train_id")
    |> result.try(uri.percent_decode)
    |> result.map(rt.TrainId)

  use stop_id <- result.try(
    st.parse_stop_id_no_direction(stop_id)
    |> result.replace_error(error_invalid_stop(stop_id)),
  )
  use stop <- result.try(
    state.schedule.stops
    |> dict.get(#(stop_id, option.None))
    |> result.replace_error(error_unknown_stop(stop_id)),
  )

  let state.RtData(current: gtfs, last_updated:) = state.fetch_gtfs(state)

  let #(uptown, downtown) =
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
      case update.direction {
        st.North -> #([li, ..uptown_acc], downtown_acc)
        st.South -> #(uptown_acc, [li, ..downtown_acc])
      }
    })
  let uptown = uptown |> list.take(from: _, up_to: 10)
  let downtown = downtown |> list.take(from: _, up_to: 10)

  let head = [html.title([], "Trains at " <> stop.name)]
  let body = [
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

  Ok(#(Document(head:, body:), wisp.response(200)))
}

fn error_invalid_stop(
  stop_id: String,
) -> #(lustre_middleware.LustreRes(a), wisp.Response) {
  #(
    Document(head: [html.title([], "Error: Invalid stop")], body: [
      html.p([], [html.text("Error: Invalid stop id: " <> stop_id)]),
    ]),
    wisp.response(400),
  )
}

fn error_unknown_stop(
  stop_id: st.StopId,
) -> #(lustre_middleware.LustreRes(b), wisp.Response) {
  #(
    Document(head: [html.title([], "Error: Unknown stop")], body: [
      html.p([], [
        html.text(
          "Error: Could not find stop "
          <> st.stop_id_to_string(stop_id, option.None),
        ),
      ]),
    ]),
    wisp.response(404),
  )
}

fn arrival_li(
  update: rt.TrainStopping,
  schedule: st.Schedule,
  gtfs: rt.Data,
  highlighted_train: Result(rt.TrainId, Nil),
) -> element.Element(msg) {
  let rt.TrainStopping(trip:, time:, stop_id: _, direction: _) = update

  let headsign = {
    use shape_id <- result.try(st.parse_shape_id(from: trip.trip_id))
    let headsign =
      schedule.trips.headsigns
      |> dict.get(shape_id)
      |> result.lazy_or(fn() {
        dict.get(gtfs.final_stops, shape_id)
        |> result.map(pair.map_second(_, option.Some))
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
          #(
            "stop_id",
            st.stop_id_to_string(update.stop_id, option.Some(update.direction)),
          ),
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
        component.route_bullet(trip.route_id),
        headsign |> result.unwrap(or: element.none()),
        html.span([], [
          html.text(
            time
            |> util.min_from_now
            |> int.to_string
            <> "min",
          ),
        ]),
      ],
    ),
  ])
}
