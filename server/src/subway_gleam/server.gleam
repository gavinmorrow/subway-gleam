import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/option
import gleam/result
import mist
import repeatedly
import wisp
import wisp/wisp_mist

import subway_gleam/gtfs/comp_flags
import subway_gleam/gtfs/st
import subway_gleam/gtfs/st/schedule_sample
import subway_gleam/server/gtfs/fetch_st
import subway_gleam/server/normalize_path_trailing_slash.{
  normalize_path_trailing_slash,
}
import subway_gleam/server/route
import subway_gleam/server/route/stop
import subway_gleam/server/route/train
import subway_gleam/server/sse_gtfs.{sse_gtfs}
import subway_gleam/server/state
import subway_gleam/server/state/gtfs_store
import subway_gleam/shared/route/stop as shared_stop
import subway_gleam/shared/route/train as shared_train

/// If true, bind to localhost. Otherwise, bind to `[::]`
const serve_localhost = False

/// A tuple of #(certfile, keyfile) for a TLS cert.
/// Only matters when serve_localhost is False.
const tls = option.Some(#("server.crt", "server.key"))

pub fn main() -> Nil {
  let assert Ok(priv_dir) = wisp.priv_directory("subway_gleam")
  let assert Ok(schedule) = {
    case comp_flags.use_local_st {
      True -> schedule_sample.schedule()
      False ->
        fetch_st.fetch_bin(st.Regular)
        |> result.map_error(st.HttpError)
        |> result.try(st.parse)
    }
  }
  let assert Ok(gtfs_store) = gtfs_store.new()
  let state = state.State(priv_dir:, schedule:, gtfs_store:)

  repeatedly.call(10 * 1000, Nil, fn(_state, _i) {
    gtfs_store.update(state.gtfs_store)
  })

  wisp.configure_logger()

  let secret_key_base = wisp.random_string(64)

  let assert Ok(_) = case serve_localhost {
    True ->
      mist_handler(_, state, secret_key_base)
      |> mist.new
      |> mist.port(8000)
      |> mist.start

    False -> {
      case tls {
        option.Some(#(certfile, keyfile)) -> {
          let assert Ok(_https_service) =
            mist_handler(_, state, secret_key_base)
            |> mist.new
            |> mist.bind("::")
            |> mist.port(443)
            |> mist.with_tls(certfile:, keyfile:)
            |> mist.start
          Nil
        }
        _ -> Nil
      }

      let assert Ok(_http_service) =
        mist_handler(_, state, secret_key_base)
        |> mist.new
        |> mist.bind("::")
        |> mist.port(80)
        |> mist.start
    }
  }

  process.sleep_forever()
}

// This is done b/c wisp doesn't support some features (e.g. websockets,
// server-sent events). So for routes that use the features wisp does support,
// they go in the wisp handler. Otherwise, they go here.
fn mist_handler(
  req: request.Request(mist.Connection),
  state: state.State,
  secret_key_base: String,
) -> response.Response(mist.ResponseData) {
  case request.path_segments(req) {
    // TODO: figure out some abstraction for this. also move out of this file
    ["stop", stop_id, "model_stream"] ->
      sse_gtfs(req, state, fn() {
        stop.model(state, stop_id, option.None)
        |> result.map(shared_stop.model_to_json)
      })
    ["train", train_id, "model_stream"] ->
      sse_gtfs(req, state, fn() {
        train.model(state, train_id, req.query)
        |> result.map(shared_train.model_to_json)
      })
    _ -> {
      let handler = wisp_mist.handler(handler(state, _), secret_key_base)
      handler(req)
    }
  }
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
    ["stops"] -> route.stops(req, state)
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
