import lustre/effect.{type Effect}

/// The external JS type `EventSource`
pub type EventSource

/// The state of an event source connection.
pub type ReadyState {
  ///  The connection is not yet open.
  Connecting
  /// The connection is open and ready to communicate.
  Open
  /// The connection is closed or couldn't be opened.
  Closed
}

pub type Message {
  // TODO: handle data types other than string
  Data(String)
  // Named to disambiguate from `ReadyState.Open`
  OnOpen(EventSource)
  // TODO: is it possible to handle specific errors?
  //       is there any error data available?
  Error
  NoEventSourceClient
}

pub fn init(path: String, to_msg: fn(Message) -> msg) -> Effect(msg) {
  effect.from(fn(dispatch: fn(msg) -> Nil) {
    do_init(
      path:,
      on_data: fn(msg) { dispatch(Data(msg) |> to_msg) },
      on_open: fn(event_source) { dispatch(OnOpen(event_source) |> to_msg) },
      on_error: fn() { dispatch(Error |> to_msg) },
      on_no_client: fn() { dispatch(NoEventSourceClient |> to_msg) },
    )
  })
}

@external(javascript, "./lustre_event_source_ffi.mjs", "init")
fn do_init(
  path _: String,
  on_data _: fn(String) -> Nil,
  on_open _: fn(EventSource) -> Nil,
  on_error _: fn() -> Nil,
  on_no_client on_no_client: fn() -> Nil,
) -> Nil {
  on_no_client()
}

pub fn close(event_source: EventSource) -> Effect(msg) {
  use _dispatch <- effect.from
  do_close(event_source)
}

@external(javascript, "./lustre_event_source_ffi.mjs", "close")
fn do_close(_event_source: EventSource) -> Nil {
  Nil
}

pub fn ready_state(event_source: EventSource) -> ReadyState {
  case ready_state_int(event_source) {
    0 -> Connecting
    1 -> Open
    2 -> Closed
    _ -> panic as "ready state should be 0, 1, or 2"
  }
}

@external(javascript, "./lustre_event_source_ffi.mjs", "readyState")
fn ready_state_int(_event_source: EventSource) -> Int {
  // Default to closed when the target doesn't support event sources
  2
}
