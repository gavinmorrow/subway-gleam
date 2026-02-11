import gleam/dict
import gleam/option
import gleam/result
import gleam/set
import lustre/attribute
import lustre/element/html
import wisp

import subway_gleam/gtfs/st
import subway_gleam/server/lustre_middleware.{Document, try_lustre_res}
import subway_gleam/server/route/stop
import subway_gleam/server/state
import subway_gleam/server/state/gtfs_actor
import subway_gleam/shared/route/stop/alerts

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
  let routes = case route {
    Ok(route) -> set.new() |> set.insert(route)
    Error(Nil) -> all_routes
  }

  let gtfs_actor.Data(current: gtfs, last_updated:) = state.fetch_gtfs(state)

  let alerts = stop.filter_alerts(gtfs, routes, stop_id)
  let all_routes =
    set.map(all_routes, with: st.route_data(in: state.schedule, for: _))

  let model =
    alerts.Model(stop_name: stop.name, last_updated:, all_routes:, alerts:)

  let head = [html.title([], "Trains at " <> stop.name)]
  let body = [html.div([attribute.id("app")], [alerts.view(model)])]

  Ok(#(Document(head:, body:), wisp.response(200)))
}
