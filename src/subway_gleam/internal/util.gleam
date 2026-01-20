import comp_flags
import gleam/dynamic/decode
import gleam/float
import gleam/result
import gleam/time/duration
import gleam/time/timestamp

pub fn decode_parse_str_field(
  named name: String,
  with parse: fn(String) -> Result(a, Nil),
  default default: a,
) -> decode.Decoder(a) {
  use str <- decode.then(decode.string)
  parse(str)
  |> result.map(decode.success)
  |> result.unwrap(or: decode.failure(default, name))
}

/// This exists so that for debugging, the time can be when the feed was fetched.
pub fn current_time() -> timestamp.Timestamp {
  // timestamp.system_time()
  comp_flags.rt_time()
}

pub fn min_from_now(time: timestamp.Timestamp) -> Int {
  time
  |> timestamp.difference(current_time(), _)
  |> duration.to_seconds()
  |> float.divide(60.0)
  |> result.unwrap(0.0)
  |> float.round
}
