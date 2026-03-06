import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/otp/actor
import gleam/result
import mist
import subway_gleam/server/log

import subway_gleam/server/state
import subway_gleam/server/state/gtfs_store

pub fn sse_gtfs(
  req: request.Request(mist.Connection),
  state: state.State,
  model: fn() -> Result(json.Json, anyerror),
) -> response.Response(mist.ResponseData) {
  use req, context <- log.request(req)

  mist.server_sent_events(
    request: req,
    initial_response: response.new(200)
      // Prevent nginx from buffering SSE responses
      |> response.set_header("X-Accel-Buffering", "no"),
    init: fn(self) {
      gtfs_store.subscribe_watcher(self, to: state.gtfs_store)
      log.debug("Subscribed to gtfs store.", with: context)
      Ok(actor.initialised(self))
    },
    loop: fn(self: process.Subject(Nil), _msg: Nil, conn: mist.SSEConnection) -> actor.Next(
      process.Subject(Nil),
      Nil,
    ) {
      log.debug("Notified of gtfs update; updating model...", with: context)

      let model =
        model()
        |> result.replace_error(Nil)
        |> result.map(json.to_string_tree)

      log.debug("Finished updating model.", with: context)

      let event = model |> result.map(mist.event)
      case result.try(event, mist.send_event(conn, _)) {
        Ok(Nil) -> {
          log.debug("Sent model.", with: context)
          actor.continue(self)
        }
        Error(Nil) -> {
          log.debug(
            "Failed to send model: connection closed; unsubscribing from gtfs store.",
            with: context,
          )
          gtfs_store.unsubscribe_watcher(self, from: state.gtfs_store)
          actor.stop()
        }
      }
    },
  )
}
