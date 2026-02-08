import gleam/io
import gleam/string
import shellout
import simplifile
import subway_gleam/gtfs/st

const path = "src/subway_gleam/gtfs/st/schedule_sample"

const stops_prefix = "import subway_gleam/gtfs/st.{North, South, Stop, StopId}

import gleam/dict
import gleam/option.{None, Some}
"

const trips_prefix = "import subway_gleam/gtfs/st.{
  type ShapeId, A, B, C, D, E, F, FX, G, J, L, M, N, N1, N2, N3, N4, N5, N6, N6X,
  N7, N7X, Q, R, S, Sf, Si, Sr, TripId, Trips, W, Z, parse_shape_id,
}

import gleam/dict

fn shape_id(shape_id: String) -> ShapeId {
  let assert Ok(shape_id) = parse_shape_id(shape_id)
  shape_id
}
"

const services_prefix = "import subway_gleam/gtfs/st.{
  A, B, C, D, E, F, FX, G, J, L, M, N, N1, N2, N3, N4, N5, N6, N6X, N7, N7X, Q,
  R, S, Service, Sf, Si, Sr, StopId, W, Z,
}

import gleam/dict
import gleam/set

fn set(dict: dict.Dict(a, b)) -> set.Set(a) {
  dict |> dict.keys |> set.from_list
}
"

const stop_routes_prefix = "import subway_gleam/gtfs/st.{
  A, B, C, D, E, F, FX, G, J, L, M, N, N1, N2, N3, N4, N5, N6, N6X, N7, N7X, Q,
  R, S, Sf, Si, Sr, StopId, W, Z,
}

import gleam/dict
import gleam/set

fn set(dict: dict.Dict(a, b)) -> set.Set(a) {
  dict |> dict.keys |> set.from_list
}
"

const transfers_prefix = "import subway_gleam/gtfs/st.{StopId, Transfer}

import gleam/dict
import gleam/set
import gleam/time/duration.{type Duration}

fn set(dict: dict.Dict(a, b)) -> set.Set(a) {
  dict |> dict.keys |> set.from_list
}

fn duration(secs: Int, nanos: Int) -> Duration {
  assert nanos == 0
  duration.seconds(secs)
}
"

const routes_prefix = "import subway_gleam/gtfs/st.{
  A, B, C, D, E, F, FX, G, J, L, M, N, N1, N2, N3, N4, N5, N6, N6X, N7, N7X, Q,
  R, RouteData, S, Sf, Si, Sr, W, Z,
}

import gleam/dict
"

const schedule_code = "//// A sample schedule to use that doesn't take forever to parse.
import subway_gleam/gtfs/st.{Schedule}
import subway_gleam/gtfs/st/schedule_sample/stops.{stops}
import subway_gleam/gtfs/st/schedule_sample/trips.{trips}
import subway_gleam/gtfs/st/schedule_sample/services.{services}
import subway_gleam/gtfs/st/schedule_sample/stop_routes.{stop_routes}
import subway_gleam/gtfs/st/schedule_sample/transfers.{transfers}
import subway_gleam/gtfs/st/schedule_sample/routes.{routes}

/// A sample schedule to use that doesn't take forever to parse.
pub fn schedule() {
  Ok(Schedule(
    stops: stops(),
    trips: trips(),
    services: services(),
    stop_routes: stop_routes(),
    transfers: transfers(),
    routes: routes(),
  ))
}
"

pub fn main() -> Nil {
  io.println_error("Fetching...")
  // let assert Ok(bits) = st.fetch_bin(st.Regular)
  let assert Ok(bits) = simplifile.read_bits(from: "../gtfs_subway.zip")
  io.println_error("Parsing...")
  let assert Ok(schedule) = st.parse(bits)
  io.println_error("Generating...")

  let stops_str =
    string.inspect(schedule.stops)
    // The ShapeId constructor is opaque, so there's a helper func
    |> string.replace(each: "ShapeId(", with: "shape_id(")
  // |> string.replace(each: "StopId(", with: "stop_id(")
  let assert Ok(Nil) =
    simplifile.write(
      to: path <> "/stops.gleam",
      contents: stops_prefix <> "pub fn stops() {" <> stops_str <> "}",
    )
  let trips_str =
    string.inspect(schedule.trips)
    // The ShapeId constructor is opaque, so there's a helper func
    |> string.replace(each: "ShapeId(", with: "shape_id(")
  // |> string.replace(each: "StopId(", with: "stop_id(")
  let assert Ok(Nil) =
    simplifile.write(
      to: path <> "/trips.gleam",
      contents: trips_prefix <> "pub fn trips() {" <> trips_str <> "}",
    )
  let services_str =
    string.inspect(schedule.services)
    // The ShapeId constructor is opaque, so there's a helper func
    |> string.replace(each: "ShapeId(", with: "shape_id(")
    |> string.replace(each: "Set(", with: "set(")
  let assert Ok(Nil) =
    simplifile.write(
      to: path <> "/services.gleam",
      contents: services_prefix <> "pub fn services() {" <> services_str <> "}",
    )
  let stop_routes_str =
    string.inspect(schedule.stop_routes)
    // The ShapeId constructor is opaque, so there's a helper func
    |> string.replace(each: "ShapeId(", with: "shape_id(")
    |> string.replace(each: "Set(", with: "set(")
  let assert Ok(Nil) =
    simplifile.write(
      to: path <> "/stop_routes.gleam",
      contents: stop_routes_prefix
        <> "pub fn stop_routes() {"
        <> stop_routes_str
        <> "}",
    )
  let transfers_str =
    string.inspect(schedule.transfers)
    // The ShapeId constructor is opaque, so there's a helper func
    |> string.replace(each: "ShapeId(", with: "shape_id(")
    |> string.replace(each: "Set(", with: "set(")
    |> string.replace(each: "Duration(", with: "duration(")
  let assert Ok(Nil) =
    simplifile.write(
      to: path <> "/transfers.gleam",
      contents: transfers_prefix
        <> "pub fn transfers() {"
        <> transfers_str
        <> "}",
    )
  let routes_str = string.inspect(schedule.routes)
  let assert Ok(Nil) =
    simplifile.write(
      to: path <> "/routes.gleam",
      contents: routes_prefix <> "pub fn routes() {" <> routes_str <> "}",
    )

  io.println_error("Writing to " <> path <> "...")
  let assert Ok(Nil) =
    simplifile.write(to: path <> ".gleam", contents: schedule_code)

  io.println_error("Formatting code...")
  let assert Ok(_) =
    shellout.command("gleam", with: ["format", path], in: ".", opt: [])

  io.println_error("Checking code...")
  let assert Ok(gleam_check_out) =
    shellout.command("gleam", with: ["check"], in: ".", opt: [])
  io.println_error(gleam_check_out)

  io.println_error("Done.")
  Nil
}
