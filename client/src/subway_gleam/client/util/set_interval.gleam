import gleam/time/duration
import gleam/time/timestamp
import lustre/effect.{type Effect}
import plinth/javascript/global

import subway_gleam/shared/util

pub fn set_interval(
  every interval: duration.Duration,
  do callback: fn(fn(msg) -> Nil) -> anything,
  timer timer: fn(global.TimerID) -> Nil,
) -> Effect(msg) {
  use dispatch <- effect.from

  let timer_id = {
    use <- global.set_interval(duration.to_milliseconds(interval))
    callback(dispatch)
  }

  timer(timer_id)
}

pub fn update_time(msg: fn(timestamp.Timestamp) -> msg) -> Effect(msg) {
  set_interval(
    every: duration.seconds(15),
    do: fn(dispatch) { dispatch(msg(util.current_time())) },
    timer: fn(_) { Nil },
  )
}
