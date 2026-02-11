import gleam/json
import gleam/result
import lustre
import lustre/effect.{type Effect}
import lustre_event_source
import plinth/browser/document
import plinth/browser/element

import subway_gleam/shared/route/train.{type Model, Model, view}
import subway_gleam/shared/util/live_status.{live_status}

pub fn main() -> Result(lustre.Runtime(Msg), lustre.Error) {
  // TODO: handle errors: model not found, and invalid JSON
  let assert Ok(Ok(hydrated_model)) =
    document.get_element_by_id("model")
    |> result.map(element.inner_text)
    |> result.map(json.parse(_, train.model_decoder()))

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
      case json.parse(from: data, using: train.model_decoder()) {
        Ok(Model(last_updated:, stops:, highlighted_stop: _, event_source: _)) -> #(
          Model(..model, last_updated:, stops:),
          effect.none(),
        )
        Error(_) -> todo as "handle model decode error"
      }
    }
    EventSource(lustre_event_source.Init(event_source))
    | EventSource(lustre_event_source.OnOpen(event_source)) -> {
      #(Model(..model, event_source: live_status(event_source)), effect.none())
    }
    EventSource(lustre_event_source.Error) -> {
      let live_status = case model.event_source {
        live_status.Connecting(event_source) -> live_status(event_source)
        live_status.Live(event_source) -> live_status(event_source)
        live_status.Unavailable -> live_status.Unavailable
      }
      #(Model(..model, event_source: live_status), effect.none())
    }
    EventSource(lustre_event_source.NoEventSourceClient) -> #(
      Model(..model, event_source: live_status.Unavailable),
      effect.none(),
    )
  }
}
