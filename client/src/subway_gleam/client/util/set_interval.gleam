import gleam/time/duration
import lustre/effect.{type Effect}
import plinth/javascript/global

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
