import gleam/dynamic/decode
import gleam/json
import gleam/time/duration
import gleam/time/timestamp

import subway_gleam/shared/util/time_zone_offset_json
import subway_gleam/shared/util/timestamp_json

pub type Time {
  Time(
    timestamp: timestamp.Timestamp,
    time_zone_offset: Result(duration.Duration, Nil),
  )
}

pub fn decoder() -> decode.Decoder(Time) {
  use timestamp <- decode.field("timestamp", timestamp_json.decoder())
  use time_zone_offset <- decode.field(
    "time_zone_offset",
    time_zone_offset_json.decoder(),
  )
  Time(timestamp:, time_zone_offset:) |> decode.success
}

pub fn to_json(time: Time) -> json.Json {
  let Time(timestamp:, time_zone_offset:) = time
  json.object([
    #("timestamp", timestamp_json.to_json(timestamp)),
    #("time_zone_offset", time_zone_offset_json.to_json(time_zone_offset)),
  ])
}
