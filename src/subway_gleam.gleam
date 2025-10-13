import gleam/erlang/process
import mist
import simplifile
import wisp
import wisp/wisp_mist

import subway_gleam/route
import subway_gleam/st
import subway_gleam/state

pub fn main() -> Nil {
  let assert Ok(schedule) = {
    // TODO: actually fetch from internet, use `st.fetch_bin()`
    // Haven't done this yet b/c it wastes internet in prototyping
    let assert Ok(bits) = simplifile.read_bits("./gtfs_subway.zip")
    st.parse(bits)
  }
  let state = state.State(schedule:)

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
  use req <- route.middleware(req)

  case wisp.path_segments(req) {
    [] -> route.index(req)
    ["stop", stop_id] -> route.stop(req, state, stop_id)
    _ -> route.not_found(req)
  }
}
