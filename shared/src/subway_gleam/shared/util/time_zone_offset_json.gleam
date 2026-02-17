import gleam/dynamic/decode
import gleam/json
import gleam/option
import gleam/time/duration

pub fn decoder() -> decode.Decoder(Result(duration.Duration, Nil)) {
  use offset <- decode.then(decode.optional(decode.int))
  offset
  |> option.map(duration.milliseconds)
  |> option.to_result(Nil)
  |> decode.success
}

pub fn to_json(offset: Result(duration.Duration, Nil)) -> json.Json {
  offset
  |> option.from_result
  |> option.map(duration.to_milliseconds)
  |> json.nullable(json.int)
}
