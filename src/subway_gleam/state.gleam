import gleam/otp/actor
import subway_gleam/st
import subway_gleam/state/rt_actor

pub type State {
  State(
    priv_dir: String,
    schedule: st.Schedule,
    rt_actor: actor.Started(rt_actor.Subject),
  )
}

pub fn fetch_gtfs(state: State) -> rt_actor.Data {
  actor.call(state.rt_actor.data, waiting: 100, sending: rt_actor.Get)
}
