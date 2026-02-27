import gleam/float
import gleam/result
import gleam/time/duration
import gleam/time/timestamp

import subway_gleam/gtfs/env

/// This exists so that for debugging, the time can be when the feed was fetched.
pub fn current_time() -> timestamp.Timestamp {
  // timestamp.system_time()
  env.rt_time()
}

pub fn min_from(
  time: timestamp.Timestamp,
  epoch epoch: timestamp.Timestamp,
) -> Int {
  time
  |> timestamp.difference(epoch, _)
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
