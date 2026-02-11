import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/pair
import gleam/result
import gleam/set
import gleam/string
import gleam/time/timestamp
import gleam/uri
import lustre/attribute
import lustre/element/html
import wisp

import subway_gleam/gtfs/rt
import subway_gleam/gtfs/st
import subway_gleam/server/hydration_scripts.{hydration_scripts}
import subway_gleam/server/lustre_middleware.{Document, try_lustre_res}
import subway_gleam/server/state
import subway_gleam/server/state/gtfs_actor
import subway_gleam/shared/component/route_bullet
import subway_gleam/shared/route/stop
import subway_gleam/shared/util
import subway_gleam/shared/util/live_status

pub fn stop(
  req: wisp.Request,
  state: state.State,
  stop_id: String,
) -> wisp.Response {
  use req <- try_lustre_res(req)

  case model(state, stop_id, req.query) {
    Ok(model) -> {
      let head = [
        html.title([], "Trains at " <> model.name),
        hydration_scripts("stop", stop.model_to_json(model)),
      ]
      let body = [
        html.div([attribute.id("app")], [
          stop.view(model),
        ]),
      ]

      Ok(#(Document(head:, body:), wisp.response(200)))
    }
    Error(InvalidStopId(stop_id)) -> Error(error_invalid_stop_id(stop_id))
    Error(UnknownStop(stop_id)) -> Error(error_unknown_stop(stop_id))
  }
}

pub fn model(
  state: state.State,
  stop_id: String,
  query: option.Option(String),
) -> Result(stop.Model, Error) {
  // TODO: make this a function?
  let highlighted_train =
    query
    |> option.to_result(Nil)
    |> result.try(uri.parse_query)
    |> result.unwrap(or: [])
    |> list.key_find("train_id")
    |> result.try(uri.percent_decode)
    |> result.map(rt.TrainId)
    |> option.from_result

  use stop_id <- result.try(
    st.parse_stop_id_no_direction(stop_id)
    |> result.replace_error(InvalidStopId(stop_id)),
  )
  use stop <- result.try(
    state.schedule.stops
    |> dict.get(#(stop_id, option.None))
    |> result.replace_error(UnknownStop(stop_id)),
  )

  let routes =
    state.schedule.stop_routes
    |> dict.get(stop_id)
    |> result.unwrap(or: set.new())
  let transfers =
    state.schedule.transfers
    |> dict.get(stop.id)
    |> result.unwrap(or: set.new())
    |> set.map(fn(transfer) {
      let routes =
        state.schedule.stop_routes
        |> dict.get(transfer.destination)
        |> result.unwrap(set.new())
        |> set.map(fn(route_id) {
          let assert Ok(route) = state.schedule.routes |> dict.get(route_id)
          route
        })
        |> set.to_list
        |> list.sort(st.route_compare)
        |> list.map(route_bullet.from_route_data)

      stop.Transfer(destination: transfer.destination, routes:)
    })
    // TODO: also need to sort each group in sort order
    |> set.to_list

  let gtfs_actor.Data(current: gtfs, last_updated:) = state.fetch_gtfs(state)

  let alerts = filter_alerts(gtfs, routes, stop_id)
  let alert_summary =
    alerts
    |> list.map(fn(alert) { option.unwrap(alert.alert_type, or: "Alert") })
    |> list.unique
    |> string.join(with: ", ")
  let alert_summary = case list.length(alerts) {
    0 -> "0 Alerts"
    1 -> "1 Alert: " <> alert_summary
    num -> int.to_string(num) <> " Alerts: " <> alert_summary
  }

  let #(uptown, downtown) =
    gtfs.arrivals
    |> dict.get(stop_id)
    |> result.unwrap(or: [])
    |> list.sort(by: fn(a, b) {
      timestamp.compare(a.time, b.time) |> order.negate
    })
    |> list.fold(from: #([], []), with: fn(acc, update) {
      let #(uptown_acc, downtown_acc) = acc
      let li = arrival_li(update, state.schedule, gtfs)
      case update.direction {
        st.North -> #([li, ..uptown_acc], downtown_acc)
        st.South -> #(uptown_acc, [li, ..downtown_acc])
      }
    })
  // let uptown = uptown |> list.take(from: _, up_to: 10)
  // let downtown = downtown |> list.take(from: _, up_to: 10)

  Ok(stop.Model(
    name: stop.name,
    last_updated:,
    transfers:,
    alert_summary:,
    uptown:,
    downtown:,
    highlighted_train:,
    event_source: live_status.Unavailable,
    cur_time: util.current_time(),
  ))
}

pub fn filter_alerts(
  gtfs: rt.Data,
  routes: set.Set(st.Route),
  stop_id: st.StopId,
) -> List(rt.Alert) {
  let current_time = util.current_time()
  let alerts =
    gtfs.alerts
    |> list.filter(fn(alert) {
      use period <- list.any(in: alert.active_periods)

      let after_start = case period.start {
        option.Some(start) -> {
          let start =
            util.timestamp_subtract(start, alert.display_before_active)
          timestamp.compare(start, current_time) != order.Gt
        }
        option.None -> True
      }
      let before_end = case period.end {
        option.Some(end) -> timestamp.compare(current_time, end) != order.Gt
        option.None -> True
      }

      after_start && before_end
    })
    |> list.filter(fn(alert) {
      use target <- list.any(in: alert.targets)

      let matches_route_id =
        target.route_id
        |> option.to_result(Nil)
        |> result.try(fn(id) { st.parse_route(id) |> result.replace_error(Nil) })
        |> result.map(set.contains(_, in: routes))
        |> result.unwrap(or: False)

      let matches_stop =
        target.stop_id
        |> option.to_result(Nil)
        |> result.try(st.parse_stop_id)
        |> result.map(pair.first)
        |> result.map(fn(target_stop_id) { target_stop_id == stop_id })
        |> result.unwrap(or: False)

      matches_route_id || matches_stop
    })
  alerts
}

pub type Error {
  InvalidStopId(stop_id: String)
  UnknownStop(stop_id: st.StopId)
}

pub fn error_invalid_stop_id(
  stop_id: String,
) -> #(lustre_middleware.LustreRes(a), wisp.Response) {
  #(
    Document(head: [html.title([], "Error: Invalid stop")], body: [
      html.p([], [html.text("Error: Invalid stop id: " <> stop_id)]),
    ]),
    wisp.response(400),
  )
}

pub fn error_unknown_stop(
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
) -> stop.Arrival {
  let rt.TrainStopping(trip:, time:, stop_id: _, direction: _) = update

  let headsign = {
    use shape_id <- result.try(st.parse_shape_id(from: trip.trip_id))
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
  }

  let train_id_percent_encode =
    update.trip.nyct.train_id
    |> option.map(uri.percent_encode)
    |> option.map(
      // uri.percent_encode doesn't encode pluses
      string.replace(_, each: "+", with: "%2B"),
    )
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

  // TODO: what to do here?? try to get rid of assert.
  let assert Ok(route_id) = st.parse_route(trip.route_id)
  let route =
    schedule |> st.route_data(for: route_id) |> route_bullet.from_route_data

  stop.Arrival(train_id:, train_url:, route:, headsign:, time:)
}
