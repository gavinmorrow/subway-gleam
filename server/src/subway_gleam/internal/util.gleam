import gleam/float
import gleam/result
import gleam/time/duration
import gleam/time/timestamp

import subway_gleam/gtfs/comp_flags

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

// See <https://github.com/gleam-lang/time/issues/41>
pub fn timestamp_subtract(
  timestamp: timestamp.Timestamp,
  duration: duration.Duration,
) -> timestamp.Timestamp {
  let negated_duration = duration.difference(duration, duration.seconds(0))
  timestamp.add(timestamp, negated_duration)
}
