import gleam/time/timestamp
import gtfs_rt_nyct

pub fn unix_time_to_timestamp(
  start: gtfs_rt_nyct.UnixTime,
) -> timestamp.Timestamp {
  let gtfs_rt_nyct.UnixTime(start) = start
  timestamp.from_unix_seconds(start)
}
