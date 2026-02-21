import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import lustre/attribute
import lustre/element/html
import wisp

import subway_gleam/gtfs/rt
import subway_gleam/gtfs/st
import subway_gleam/server/lustre_middleware.{Document, try_lustre_res}
import subway_gleam/server/route/stop
import subway_gleam/server/state
import subway_gleam/server/state/gtfs_actor
import subway_gleam/server/time_zone
import subway_gleam/shared/route/stop/alerts
import subway_gleam/shared/util/time

pub fn alerts(
  req: wisp.Request,
  state: state.State,
  stop_id: String,
  route_id: option.Option(String),
) -> wisp.Response {
  use _req <- try_lustre_res(req)

  use stop_id <- result.try(
    st.parse_stop_id_no_direction(stop_id)
    |> result.replace_error(stop.error_invalid_stop_id(stop_id)),
  )
  use stop <- result.try(
    state.schedule.stops
    |> dict.get(#(stop_id, option.None))
    |> result.replace_error(stop.error_unknown_stop(stop_id)),
  )

  let all_routes =
    state.schedule.stop_routes
    |> dict.get(stop_id)
    |> result.unwrap(or: set.new())
  let route =
    route_id |> option.to_result(Nil) |> result.try(st.route_id_long_to_route)

  let gtfs_actor.Data(current: gtfs, last_updated:) = state.fetch_gtfs(state)

  // Add in alerts from arrivals.
  // Needed b/c if a train is rerouted then alerts from that train should be
  // shown at this stop.
  let all_routes =
    set.union(of: all_routes, and: rt.routes_arriving(gtfs, at: stop_id))

  let routes = case route {
    Ok(route) -> set.new() |> set.insert(route)
    Error(Nil) -> all_routes
  }

  let alerts =
    stop.filter_alerts(gtfs, routes, stop_id)
    |> list.map(rt_alert_to_model_alert(_, state))
  let all_routes =
    set.map(all_routes, with: st.route_data(in: state.schedule, for: _))

  let cur_time = time_zone.now()
  let last_updated =
    time.Time(last_updated, time_zone.new_york_offset(last_updated))

  let model =
    alerts.Model(
      stop_name: stop.name,
      last_updated:,
      all_routes:,
      alerts:,
      cur_time:,
    )

  let head = [html.title([], "Trains at " <> stop.name)]
  let body = [html.div([attribute.id("app")], [alerts.view(model)])]

  Ok(#(Document(head:, body:), wisp.response(200)))
}

fn rt_alert_to_model_alert(alert: rt.Alert, state: state.State) -> alerts.Alert {
  let routes =
    rt.routes_in_alert(alert)
    |> set.map(st.route_data(in: state.schedule, for: _))
  let updated =
    alert.updated
    |> option.map(fn(updated) {
      time.Time(updated, time_zone.new_york_offset(updated))
    })

  alerts.Alert(
    id: alert.id,
    routes:,
    header: alert.header,
    description: alert.description,
    updated:,
    alert_type: alert.alert_type,
    human_readable_active_period: alert.human_readable_active_period,
  )
}
