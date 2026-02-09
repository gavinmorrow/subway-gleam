import gleam/json
import gleam/result
import lustre
import lustre/effect.{type Effect}
import plinth/browser/document
import plinth/browser/element
import shared/route/stop.{type Model, view}

pub fn main() -> Result(lustre.Runtime(Msg), lustre.Error) {
  // TODO: handle errors: model not found, and invalid JSON
  let assert Ok(Ok(hydrated_model)) =
    document.get_element_by_id("model")
    |> result.map(element.inner_text)
    |> result.map(json.parse(_, stop.model_decoder()))

  let app = lustre.application(init, update, view)
  lustre.start(app, onto: "#app", with: hydrated_model)
}

pub type Msg

fn init(flags: Model) -> #(Model, Effect(Msg)) {
  #(flags, effect.none())
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    _ -> #(model, effect.none())
  }
}
