import gleam/io
import gleam/string
import shellout
import simplifile
import subway_gleam/st

const path = "src/subway_gleam/schedule_sample"

const code_prefix = "//// A sample schedule to use that doesn't take forever to parse.

import subway_gleam/st.{
  type ShapeId, A, B, C, D, E, F, G, J, L, M, N, N1, N2, N3, N4, N5, N6, N7,
  North, Q, R, S, Schedule, Service, Sf, Si, South, Sr, Stop, StopId, Trips, W,
  Z, parse_shape_id, parse_stop_id, TripId,
}

import gleam/dict
import gleam/set
import gleam/option.{None, Some}

fn shape_id(shape_id: String) -> ShapeId {
  let assert Ok(shape_id) = parse_shape_id(shape_id)
  shape_id
}

fn set(dict: dict.Dict(a, b)) -> set.Set(a) {
  dict |> dict.keys |> set.from_list
}
"

const schedule_code = "//// A sample schedule to use that doesn't take forever to parse.
import subway_gleam/st.{Schedule}
import subway_gleam/schedule_sample/stops.{stops}
import subway_gleam/schedule_sample/trips.{trips}
import subway_gleam/schedule_sample/services.{services}

/// A sample schedule to use that doesn't take forever to parse.
pub fn schedule() {
  Ok(Schedule(stops: stops(), trips: trips(), services: services()))
}
"

pub fn main() -> Nil {
  io.println_error("Fetching...")
  // let assert Ok(bits) = st.fetch_bin(st.Regular)
  let assert Ok(bits) = simplifile.read_bits(from: "./gtfs_subway.zip")
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
      contents: code_prefix <> "pub fn stops() {" <> stops_str <> "}",
    )
  let trips_str =
    string.inspect(schedule.trips)
    // The ShapeId constructor is opaque, so there's a helper func
    |> string.replace(each: "ShapeId(", with: "shape_id(")
  // |> string.replace(each: "StopId(", with: "stop_id(")
  let assert Ok(Nil) =
    simplifile.write(
      to: path <> "/trips.gleam",
      contents: code_prefix <> "pub fn trips() {" <> trips_str <> "}",
    )
  let services_str =
    string.inspect(schedule.services)
    // The ShapeId constructor is opaque, so there's a helper func
    |> string.replace(each: "ShapeId(", with: "shape_id(")
    |> string.replace(each: "Set(", with: "set(")
  let assert Ok(Nil) =
    simplifile.write(
      to: path <> "/services.gleam",
      contents: code_prefix <> "pub fn services() {" <> services_str <> "}",
    )

  io.println_error("Writing to src/subway_gleam/schedule_sample.gleam...")
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
