import gleam/otp/actor
import subway_gleam/st
import subway_gleam/state/gtfs_actor

pub type State {
  State(
    priv_dir: String,
    schedule: st.Schedule,
    gtfs_actor: actor.Started(gtfs_actor.Subject),
  )
}

pub fn fetch_gtfs(state: State) -> gtfs_actor.Data {
  actor.call(state.gtfs_actor.data, waiting: 100, sending: gtfs_actor.Get)
}
