import gleam/dynamic/decode
import gleam/json
import lustre/element
import lustre/element/html

pub type Model {
  Model
}

pub fn model_decoder() -> decode.Decoder(Model) {
  Model |> decode.success
}

pub fn model_to_json(model: Model) -> json.Json {
  json.object([])
}

pub fn view(model: Model) -> element.Element(msg) {
  html.div([], [])
}
