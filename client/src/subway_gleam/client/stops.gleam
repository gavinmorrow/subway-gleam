import gleam/json
import gleam/option
import gleam/result
import lustre
import lustre/effect.{type Effect}
import plinth/browser/document
import plinth/browser/element

import subway_gleam/shared/ffi/geolocation
import subway_gleam/shared/route/stops.{type Model, Model, view}

pub fn main() -> Result(lustre.Runtime(Msg), lustre.Error) {
  // TODO: handle errors: model not found, and invalid JSON
  let assert Ok(Ok(model)) =
    document.get_element_by_id("model")
    |> result.map(element.inner_text)
    |> result.map(json.parse(from: _, using: stops.model_decoder()))

  let app = lustre.application(init, update, view)
  lustre.start(app, onto: "#app", with: model)
}

pub type Msg {
  UpdatePosition(geolocation.Position)
}

fn init(flags: Model) -> #(Model, effect.Effect(Msg)) {
  #(flags, watch_position())
}

fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    UpdatePosition(cur_position) -> #(
      Model(..model, cur_position: option.Some(cur_position)),
      effect.none(),
    )
  }
}

fn watch_position() -> Effect(Msg) {
  use dispatch <- effect.from
  let _id =
    geolocation.watch_position(
      on_success: fn(pos) { dispatch(UpdatePosition(pos)) },
      on_error: fn(err) { todo },
    )
  Nil
}
