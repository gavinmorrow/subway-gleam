import gleam/erlang/process
import gleam/otp/actor
import mist
import repeatedly
import wisp
import wisp/wisp_mist

import subway_gleam/route
import subway_gleam/schedule_sample
import subway_gleam/state

pub fn main() -> Nil {
  let assert Ok(priv_dir) = wisp.priv_directory("subway_gleam")
  let assert Ok(schedule) = {
    // TODO: actually fetch from internet, use `st.fetch_bin()`
    // Haven't done this yet b/c it wastes internet in prototyping
    // let assert Ok(bits) = simplifile.read_bits("./gtfs_subway.zip")
    // st.parse(bits)
    schedule_sample.schedule() |> Ok
  }
  let assert Ok(rt_actor) = state.rt_actor()
  let state = state.State(priv_dir:, schedule:, rt_actor:)

  repeatedly.call(10 * 1000, Nil, fn(_state, _i) {
    actor.send(state.rt_actor.data, state.Update)
  })

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
    ["train", train_id] -> route.train(req, state, train_id)
    _ -> route.not_found(req)
  }
}
