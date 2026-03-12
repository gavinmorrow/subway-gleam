import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/option
import gleam/result
import mist
import repeatedly
import subway_gleam/server/log
import wisp
import wisp/wisp_mist

import subway_gleam/gtfs/env as gtfs_env
import subway_gleam/gtfs/st
import subway_gleam/gtfs/st/schedule_sample
import subway_gleam/server/env
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

pub fn main() -> Nil {
  wisp.configure_logger()
  configure_logger()

  log.notice("Starting sbwy...", with: log.new_context())

  let assert Ok(priv_dir) = wisp.priv_directory("subway_gleam")
  let assert Ok(schedule) = {
    case gtfs_env.use_local_st() {
      True -> schedule_sample.schedule()
      False ->
        fetch_st.fetch_bin(st.Regular)
        |> result.map_error(st.HttpError)
        |> result.try(st.parse)
    }
  }
  let assert Ok(gtfs_store) = gtfs_store.new()
  let state = state.State(priv_dir:, schedule:, gtfs_store:)

  log.debug("Setup initial state.", with: log.new_context())

  repeatedly.call(10 * 1000, Nil, fn(_state, _i) {
    gtfs_store.update(state.gtfs_store)
  })

  let secret_key_base = wisp.random_string(64)
  let wisp_handler = wisp_mist.handler(handler(state, _), secret_key_base)

  let host = env.host()
  let http_port = env.http_port()
  let https_port = env.https_port()
  log.debug(
    "Starting server...",
    with: log.context([
      #("host", host),
      #("http_port", http_port |> int.to_string),
      #("https_port", https_port |> int.to_string),
    ]),
  )

  let assert Ok(_service) = case env.certfile(), env.keyfile() {
    Ok(certfile), Ok(keyfile) ->
      mist_handler(_, state, wisp_handler)
      |> mist.new
      |> mist.bind(host)
      |> mist.port(https_port)
      |> mist.with_tls(certfile:, keyfile:)
      |> mist.start
    _, _ ->
      mist_handler(_, state, wisp_handler)
      |> mist.new
      |> mist.bind(env.host())
      |> mist.port(http_port)
      |> mist.start
  }

  log.debug("Main process sleeping forever...", with: log.new_context())

  process.sleep_forever()
}

// This is done b/c wisp doesn't support some features (e.g. websockets,
// server-sent events). So for routes that use the features wisp does support,
// they go in the wisp handler. Otherwise, they go here.
fn mist_handler(
  req: request.Request(mist.Connection),
  state: state.State,
  wisp_handler: fn(request.Request(mist.Connection)) ->
    response.Response(mist.ResponseData),
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
    // I don't love the hard coded path but c'est la vie
    ["static", "service-worker.js"] ->
      wisp_handler(req)
      |> wisp.set_header("Service-Worker-Allowed", "/")
    _ -> wisp_handler(req)
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

  // TODO: pass context to routes for logging
  use req, _context <- log.request(req)

  case wisp.path_segments(req) {
    [] -> route.index(req)
    ["map"] -> route.map(req)
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

@external(erlang, "logger_config_ffi", "configure")
fn configure_logger() -> Nil
