import gleam/result
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import tzif/database
import tzif/tzcalendar

import subway_gleam/shared/util
import subway_gleam/shared/util/time.{type Time, Time}

pub fn new_york_offset(at time: Timestamp) -> Result(Duration, Nil) {
  use tz_db <- result.try(database.load_from_os())
  use tz <- result.map(
    tzcalendar.to_time_and_zone(time, "America/New_York", tz_db)
    |> result.replace_error(Nil),
  )
  tz.offset
}

pub fn now() -> Time {
  let timestamp = util.current_time()
  Time(timestamp:, time_zone_offset: new_york_offset(at: timestamp))
}
