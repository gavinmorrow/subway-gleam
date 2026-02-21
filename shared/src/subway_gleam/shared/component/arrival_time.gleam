import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/pair
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import lustre/attribute
import lustre/element
import lustre/element/html
import subway_gleam/shared/util
import subway_gleam/shared/util/time_zone_offset_json
import subway_gleam/shared/util/timestamp_json

pub type Time {
  Time(
    timestamp: timestamp.Timestamp,
    time_zone_offset: Result(duration.Duration, Nil),
  )
}

pub fn arrival_time(
  arriving_at time: timestamp.Timestamp,
  cur_time cur_time: Time,
) -> element.Element(msg) {
  html.div(
    [
      // TODO: move to .css
      attribute.styles([
        #("display", "flex"),
        #("flex-direction", "row"),
        #("gap", "0.5em"),
      ]),
    ],
    [
      html.span([], [
        html.text(relative_time(from: cur_time.timestamp, to: time)),
      ]),
      case cur_time.time_zone_offset {
        Ok(time_zone_offset) -> {
          // TODO: is <pre> the right element? should this be smth in css?
          // TODO: make styled dimmer
          html.pre([], [
            html.text(time_of_day(at: time, offset_by: time_zone_offset)),
          ])
        }
        // Don't show the time of day if the time zone offset can't
        // be determined
        Error(Nil) -> element.none()
      },
    ],
  )
}

pub fn time_decoder() -> decode.Decoder(Time) {
  use timestamp <- decode.field("timestamp", timestamp_json.decoder())
  use time_zone_offset <- decode.field(
    "time_zone_offset",
    time_zone_offset_json.decoder(),
  )
  Time(timestamp:, time_zone_offset:) |> decode.success
}

pub fn time_to_json(time: Time) -> json.Json {
  let Time(timestamp:, time_zone_offset:) = time
  json.object([
    #("timestamp", timestamp_json.to_json(timestamp)),
    #("time_zone_offset", time_zone_offset_json.to_json(time_zone_offset)),
  ])
}

fn relative_time(
  from cur_time: timestamp.Timestamp,
  to time: timestamp.Timestamp,
) -> String {
  time
  |> util.min_from(cur_time)
  |> int.to_string
  <> "min"
}

fn time_of_day(
  at time: timestamp.Timestamp,
  offset_by offset: duration.Duration,
) -> String {
  let time_of_day =
    time
    |> timestamp.to_calendar(offset)
    |> pair.second

  let hours =
    time_of_day.hours
    |> int.to_string
    |> string.pad_start(to: 2, with: "0")
  let mins =
    time_of_day.minutes
    |> int.to_string
    |> string.pad_start(to: 2, with: "0")
  let secs = case time_of_day.seconds {
    s if s > 30 -> "+"
    _ -> " "
  }

  hours <> ":" <> mins <> secs
}
