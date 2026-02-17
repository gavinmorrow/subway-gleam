import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}

pub fn new_york_offset(at time: Timestamp) -> Result(Duration, Nil) {
  let time_ms = timestamp.to_unix_seconds(time) *. 1000.0
  case get_offset(at: time_ms) {
    0 -> Error(Nil)
    offset_mins -> Ok(duration.minutes(offset_mins))
  }
}

@external(javascript, "./time_zone_ffi.mjs", "newYorkOffset")
fn get_offset(at time: Float) -> Int
