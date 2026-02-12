import gleam/json
import gleam/result
import lustre
import lustre/effect
import plinth/browser/document
import plinth/browser/element

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

pub type Msg

fn init(flags: Model) -> #(Model, effect.Effect(Msg)) {
  #(flags, effect.none())
}

fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  #(model, effect.none())
}
