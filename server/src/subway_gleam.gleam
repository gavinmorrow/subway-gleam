import gleam/erlang/process
import gleam/option
import gleam/otp/actor
import gleam/result
import mist
import repeatedly
import wisp
import wisp/wisp_mist

import subway_gleam/gtfs/comp_flags
import subway_gleam/gtfs/st
import subway_gleam/gtfs/st/schedule_sample
import subway_gleam/normalize_path_trailing_slash.{normalize_path_trailing_slash}
import subway_gleam/route
import subway_gleam/state
import subway_gleam/state/gtfs_actor

pub fn main() -> Nil {
  let assert Ok(priv_dir) = wisp.priv_directory("subway_gleam")
  let assert Ok(schedule) = {
    case comp_flags.use_local_st {
      True -> schedule_sample.schedule()
      False ->
        st.fetch_bin(st.Regular)
        |> result.map_error(st.HttpError)
        |> result.try(st.parse)
    }
  }
  let assert Ok(gtfs_actor) = gtfs_actor.gtfs_actor()
  let state = state.State(priv_dir:, schedule:, gtfs_actor:)

  repeatedly.call(10 * 1000, Nil, fn(_state, _i) {
    actor.send(state.gtfs_actor.data, gtfs_actor.Update)
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

  // Only apply this to non-static files
  // 
  // Doing this because it allows routes to use relative paths to drill down
  // into details. e.g. the stop route has a link, `./alerts`, that will
  // redirect to the alerts page for the stop.
  use req <- normalize_path_trailing_slash(req)

  case wisp.path_segments(req) {
    [] -> route.index(req)
    ["stop", stop_id] -> route.stop(req, state, stop_id)
    ["stop", _stop_id, "alerts"] ->
      // slightly hacky, but this works b/c if the route is unrecognized, then
      // it'll show the alerts for all routes.
      wisp.permanent_redirect(to: req.path <> "all/")
    ["stop", stop_id, "alerts", route_id] ->
      route.stop_alerts(req, state, stop_id, option.Some(route_id))
    ["train", train_id] -> route.train(req, state, train_id)
    ["line", route_id] -> route.line(req, state, route_id)
    _ -> route.not_found(req)
  }
}
