import gleam/dynamic/decode
import gleam/result

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
