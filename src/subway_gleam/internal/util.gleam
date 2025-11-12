import gleam/dynamic/decode
import gleam/float
import gleam/result
import gleam/time/duration
import gleam/time/timestamp

pub fn decode_parse_str_field(
  name: String,
  parse: fn(String) -> Result(a, Nil),
  default: a,
) -> decode.Decoder(a) {
  use str <- decode.then(decode.string)
  parse(str)
  |> result.map(decode.success)
  |> result.unwrap(or: decode.failure(default, name))
}

pub fn min_from_now(time: timestamp.Timestamp) -> Int {
  time
  |> timestamp.difference(timestamp.system_time(), _)
  |> duration.to_seconds()
  |> float.divide(60.0)
  |> result.unwrap(0.0)
  |> float.round
}
