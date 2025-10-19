import gleam/erlang/process
import gleam/option
import mist
import wisp
import wisp/wisp_mist

import subway_gleam/route
import subway_gleam/st
import subway_gleam/state

pub fn main() -> Nil {
  let assert Ok(priv_dir) = wisp.priv_directory("subway_gleam")
  let assert Ok(schedule) = {
    // TODO: actually fetch from internet, use `st.fetch_bin()`
    // Haven't done this yet b/c it wastes internet in prototyping
    // let assert Ok(bits) = simplifile.read_bits("./gtfs_subway.zip")
    // st.parse(bits)
    let id = st.StopId(route: st.N6, id: 35, direction: _)
    let stop = fn(id, parent) {
      st.Stop(
        id:,
        name: "14 St-Union Sq",
        lat: 0.0,
        lon: 0.0,
        location_type: option.None,
        parent_station: parent,
      )
    }
    st.Schedule([
      stop(id(option.None), option.None),
      stop(id(option.Some(st.North)), option.Some(id(option.None))),
      stop(id(option.Some(st.South)), option.Some(id(option.None))),
    ])
    |> Ok
  }
  let state = state.State(priv_dir:, schedule:)

  wisp.configure_logger()

  let secret_key_base = wisp.random_string(64)

  let assert Ok(_) =
    wisp_mist.handler(handler(state, _), secret_key_base)
    |> mist.new
    |> mist.port(8000)
    |> mist.start

  process.sleep_forever()
}

fn handler(state: state.State, req: wisp.Request) -> wisp.Response {
  use <- wisp.rescue_crashes
  use req <- wisp.csrf_known_header_protection(req)

  use <- wisp.serve_static(req, under: "/static", from: state.priv_dir)

  case wisp.path_segments(req) {
    [] -> route.index(req)
    ["stop", stop_id] -> route.stop(req, state, stop_id)
    _ -> route.not_found(req)
  }
}
