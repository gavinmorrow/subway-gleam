import gleam/option
import gleam/time/timestamp
import gtfs_rt_nyct

import subway_gleam/gtfs/internal/unix_time_to_timestamp.{unix_time_to_timestamp}

pub type TimeRange {
  TimeRange(
    start: option.Option(timestamp.Timestamp),
    end: option.Option(timestamp.Timestamp),
  )
}

pub fn from_gtfs_rt_nyct(time_range: gtfs_rt_nyct.TimeRange) -> TimeRange {
  let gtfs_rt_nyct.TimeRange(start:, end:) = time_range

  let start = option.map(start, unix_time_to_timestamp)
  let end = option.map(end, unix_time_to_timestamp)

  TimeRange(start:, end:)
}
