import gleam/int
import gleam/time/timestamp

pub type Position {
  Position(
    /// The position's latitude in decimal degrees.
    latitude: Float,
    /// The position's longitude in decimal degrees.
    longitude: Float,
    ///  Returns a double representing the accuracy of the latitude and
    /// longitude properties, expressed in meters.
    accuracy: Float,
    /// The time at which the location was retrieved.
    timestamp: timestamp.Timestamp,
  )
}

pub type Error {
  /// The acquisition of the geolocation information failed because the page
  /// didn't have the necessary permissions, for example because it is blocked by
  /// a Permissions Policy.
  PermissionDenied
  /// The acquisition of the geolocation failed because at least one internal
  /// source of position returned an internal error.
  PositionUnavailable
  /// The time allowed to acquire the geolocation was reached before the
  /// information was obtained.
  Timeout
}

pub type WatchId {
  WatchId(Int)
}

pub fn watch_position(
  on_success success: fn(Position) -> Nil,
  on_error error: fn(Error) -> Nil,
) -> WatchId {
  do_watch_position(
    on_success: fn(pos) { success(js_pos_to_pos(pos)) },
    on_error: fn(err) { error(js_err_to_err(err)) },
  )
  |> WatchId
}

/// The external JS type `GeolocationPosition`
type JsPosition

fn js_pos_to_pos(pos: JsPosition) -> Position {
  let latitude = get_latitude(pos)
  let longitude = get_longitude(pos)
  let accuracy = get_accuracy(pos)
  let timestamp = get_timestamp(pos) |> timestamp.from_unix_seconds

  Position(latitude:, longitude:, accuracy:, timestamp:)
}

/// The external JS type `GeolocationPositionError`
type JsError

fn js_err_to_err(err: JsError) -> Error {
  case get_error_code(err) {
    1 -> PermissionDenied
    2 -> PositionUnavailable
    3 -> Timeout
    unknown_code ->
      panic as {
        "unknown geolocation error code " <> int.to_string(unknown_code)
      }
  }
}

@external(javascript, "./geolocation_ffi.mjs", "watchPosition")
fn do_watch_position(
  on_success _: fn(JsPosition) -> Nil,
  on_error _: fn(JsError) -> Nil,
) -> Int {
  panic as "geolocation should run in a browser"
}

@external(javascript, "./geolocation_ffi.mjs", "getLatitude")
fn get_latitude(_pos: JsPosition) -> Float {
  0.0
}

@external(javascript, "./geolocation_ffi.mjs", "getLongitude")
fn get_longitude(_pos: JsPosition) -> Float {
  0.0
}

@external(javascript, "./geolocation_ffi.mjs", "getAccuracy")
fn get_accuracy(_pos: JsPosition) -> Float {
  0.0
}

@external(javascript, "./geolocation_ffi.mjs", "getTimestamp")
fn get_timestamp(_pos: JsPosition) -> Int {
  0
}

@external(javascript, "./geolocation_ffi.mjs", "getErrorCode")
fn get_error_code(_err: JsError) -> Int {
  0
}
