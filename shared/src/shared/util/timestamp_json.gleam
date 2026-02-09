import gleam/dynamic/decode
import gleam/float
import gleam/json
import gleam/time/timestamp

pub fn decoder() -> decode.Decoder(timestamp.Timestamp) {
  use unix_time <- decode.then(decode.int)
  timestamp.from_unix_seconds(unix_time) |> decode.success
}

pub fn to_json(timestamp: timestamp.Timestamp) -> json.Json {
  timestamp |> timestamp.to_unix_seconds |> float.truncate |> json.int
}
