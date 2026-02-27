import subway_gleam/gtfs/st
import subway_gleam/server/state/gtfs_store.{type GtfsStore}

pub type State {
  State(priv_dir: String, schedule: st.Schedule, gtfs_store: GtfsStore)
}

pub fn fetch_gtfs(state: State) -> gtfs_store.Data {
  gtfs_store.get(from: state.gtfs_store)
}
