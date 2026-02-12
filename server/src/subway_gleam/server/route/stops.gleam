import gleam/dict
import gleam/list
import gleam/option
import lustre/attribute
import lustre/element/html
import subway_gleam/gtfs/st
import wisp

import subway_gleam/server/hydration_scripts.{hydration_scripts}
import subway_gleam/server/lustre_middleware.{Document}
import subway_gleam/server/state
import subway_gleam/shared/route/stops

pub fn stops(req: wisp.Request, state: state.State) -> wisp.Response {
  use _req <- lustre_middleware.lustre_res(req)

  let all_stops =
    state.schedule.stops
    |> dict.values
    |> list.filter_map(fn(stop) {
      case stop.direction {
        option.Some(_) -> Error(Nil)
        option.None -> Ok(st.Stop(..stop, direction: Nil))
      }
    })

  let model = stops.Model(all_stops:, cur_position: option.None)

  let head = [
    html.title([], "Stops"),
    hydration_scripts("stops", stops.model_to_json(model)),
  ]
  let body = [html.div([attribute.id("app")], [stops.view(model)])]

  #(Document(head:, body:), wisp.response(200))
}
