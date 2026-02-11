import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/otp/actor
import gleam/result
import mist

import subway_gleam/server/state
import subway_gleam/server/state/gtfs_actor

pub fn sse_gtfs(
  req: request.Request(mist.Connection),
  state: state.State,
  model: fn() -> Result(json.Json, anyerror),
) -> response.Response(mist.ResponseData) {
  mist.server_sent_events(
    request: req,
    initial_response: response.new(200),
    init: fn(self) {
      process.send(state.gtfs_actor.data, gtfs_actor.SubscribeWatcher(self))
      Ok(actor.initialised(self))
    },
    loop: fn(self: process.Subject(Nil), _msg: Nil, conn: mist.SSEConnection) -> actor.Next(
      process.Subject(Nil),
      Nil,
    ) {
      let model =
        model()
        |> result.replace_error(Nil)
        |> result.map(json.to_string_tree)

      let event = model |> result.map(mist.event)
      case result.try(event, mist.send_event(conn, _)) {
        Ok(Nil) -> actor.continue(self)
        Error(Nil) -> {
          process.send(
            state.gtfs_actor.data,
            gtfs_actor.UnsubscribeWatcher(self),
          )
          actor.stop()
        }
      }
    },
  )
}
