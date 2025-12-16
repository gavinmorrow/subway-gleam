import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import gleam/string
import lustre/element
import lustre/element/html
import subway_gleam/lustre_middleware.{Document, try_lustre_res}
import subway_gleam/st
import subway_gleam/state
import wisp

pub fn line(req: wisp.Request, state: state.State, route_id: String) {
  use req <- try_lustre_res(req)

  use route <- result.try(
    st.route_id_long_to_route(route_id)
    |> result.replace_error(error_unknown_route(route_id)),
  )

  use service <- result.try(
    state.schedule.services
    |> dict.get(route)
    |> result.replace_error(error_no_service(route)),
  )
  let st.Service(stops:, route: _) = service

  let stops =
    stops
    |> set.to_list
    |> list.filter_map(fn(id) {
      state.schedule.stops |> dict.get(#(id, option.None))
    })
    |> list.sort(by: fn(a, b) { string.compare(a.name, b.name) })
  let stop_elems = list.map(stops, stop_li)
  let stops_ul = html.ul([], stop_elems)

  let head = [html.title([], "The " <> route_id)]
  let body = [html.h1([], [html.text(route_id)]), stops_ul]

  Ok(#(Document(head:, body:), wisp.response(200)))
}

fn stop_li(stop: st.Stop(direction)) -> element.Element(msg) {
  let st.Stop(
    name:,
    id: _,
    direction: _,
    lat: _,
    lon: _,
    location_type: _,
    parent_station: _,
  ) = stop
  html.li([], [html.text(name)])
}

fn error_unknown_route(
  route: String,
) -> #(lustre_middleware.LustreRes(msg), wisp.Response) {
  #(
    Document(head: [html.title([], "Error: Unknown route")], body: [
      html.p([], [
        html.text("Error: Unknown route " <> route),
      ]),
    ]),
    wisp.response(404),
  )
}

fn error_no_service(
  route: st.Route,
) -> #(lustre_middleware.LustreRes(msg), wisp.Response) {
  #(
    Document(head: [html.title([], "Error: No route data")], body: [
      html.p([], [
        html.text(
          "Error: Could not find data for route " <> st.route_to_long_id(route),
        ),
      ]),
    ]),
    wisp.response(404),
  )
}
