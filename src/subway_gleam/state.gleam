import subway_gleam/st

pub type State {
  State(priv_dir: String, schedule: st.Schedule)
}
