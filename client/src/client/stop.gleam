import gleam/json
import gleam/result
import lustre
import lustre/effect.{type Effect}
import lustre_event_source
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

pub type Msg {
  EventSource(lustre_event_source.Message)
}

fn init(flags: Model) -> #(Model, Effect(Msg)) {
  #(flags, lustre_event_source.init("./model_stream", EventSource))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    EventSource(lustre_event_source.Data(data)) -> {
      case json.parse(from: data, using: stop.model_decoder()) {
        Ok(new_model) -> #(new_model, effect.none())
        Error(_) -> todo as "handle model decode error"
      }
    }
    EventSource(lustre_event_source.OnOpen(_event_source)) -> #(
      model,
      effect.none(),
    )
    EventSource(lustre_event_source.Error) ->
      todo as "handle event source error"
    EventSource(lustre_event_source.NoEventSourceClient) ->
      // could also handle as normal error
      panic as "web target should always have EventSource"
  }
}
