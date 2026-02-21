import gleam/int
import gleam/string
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import lustre/element/html
import subway_gleam/shared/util/time.{type Time}

pub fn last_updated(at time: Time, cur_time cur_time: Time) {
  let dt = {
    let #(dt, dt_unit) =
      time.timestamp
      |> timestamp.difference(cur_time.timestamp)
      // TODO: this always rounds down. is that correct?
      |> duration.approximate

    let dt = int.to_string(dt)
    case dt_unit {
      duration.Nanosecond -> "just now"
      duration.Microsecond -> "just now"
      duration.Millisecond -> "just now"
      duration.Second if dt == "1" -> "1 second ago"
      duration.Second -> dt <> " seconds ago"
      duration.Minute if dt == "1" -> "1 minute ago"
      duration.Minute -> dt <> " minutes ago"
      duration.Hour if dt == "1" -> "1 hour ago"
      duration.Hour -> dt <> " hours ago"
      duration.Day if dt == "1" -> "1 day ago"
      duration.Day -> dt <> " days ago"
      duration.Week if dt == "1" -> "1 week ago"
      duration.Week -> dt <> " weeks ago"
      duration.Month if dt == "1" -> "1 month ago"
      duration.Month -> dt <> " months ago"
      duration.Year if dt == "1" -> "1 year ago"
      duration.Year -> dt <> " years ago"
    }
  }

  let calendar_date = case time.time_zone_offset {
    Ok(offset) -> {
      let #(date, time) = timestamp.to_calendar(time.timestamp, offset)
      // TODO: do localization on client
      let hours =
        time.hours |> int.to_string |> string.pad_start(to: 2, with: "0")
      let min =
        time.minutes |> int.to_string |> string.pad_start(to: 2, with: "0")
      let secs =
        time.seconds |> int.to_string |> string.pad_start(to: 2, with: "0")

      let day = date.day |> int.to_string
      let month = date.month |> calendar.month_to_string
      let year = date.year |> int.to_string

      " ("
      <> hours
      <> ":"
      <> min
      <> ":"
      <> secs
      <> " "
      <> day
      <> " "
      <> month
      <> " "
      <> year
      <> ")"
    }
    Error(Nil) -> ""
  }

  html.text("Last updated " <> dt <> calendar_date)
}
