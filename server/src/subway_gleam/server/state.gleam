import gleam/otp/actor

import subway_gleam/gtfs/st
import subway_gleam/server/state/gtfs_actor

pub type State {
  State(
    priv_dir: String,
    schedule: st.Schedule,
    gtfs_actor: actor.Started(gtfs_actor.Subject),
  )
}

pub fn fetch_gtfs(state: State) -> gtfs_actor.Data {
  gtfs_actor.get(state.gtfs_actor.data)
}
