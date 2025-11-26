import gleam/io
import gleam/string
import shellout
import simplifile
import subway_gleam/st

const path = "src/subway_gleam/schedule_sample.gleam"

const code = "//// A sample schedule to use that doesn't take forever to parse.

import subway_gleam/st.{
  type ShapeId, North, Schedule, South, Stop, StopId, Trips, parse_shape_id,
}

import gleam/dict
import gleam/option.{None, Some}

fn shape_id(shape_id: String) -> ShapeId {
  let assert Ok(shape_id) = parse_shape_id(shape_id)
  shape_id
}

/// A sample schedule to use that doesn't take forever to parse.
pub fn schedule() {
  // <schedule>
}
"

pub fn main() -> Nil {
  io.println_error("Fetching...")
  let assert Ok(bits) = st.fetch_bin(st.Regular)
  io.println_error("Parsing...")
  let assert Ok(schedule) = st.parse(bits)
  io.println_error("Generating...")
  let schedule_str =
    string.inspect(schedule)
    // The ShapeId constructor is opaque, so there's a helper func
    |> string.replace(each: "ShapeId(", with: "shape_id(")
  let full_code =
    string.replace(in: code, each: "// <schedule>", with: schedule_str)

  io.println_error("Writing to src/subway_gleam/schedule_sample.gleam...")
  let assert Ok(Nil) = simplifile.write(to: path, contents: full_code)

  // io.println_error("Formatting code...")
  // let assert Ok(_) =
  //   shellout.command("gleam", with: ["format", path], in: ".", opt: [])

  io.println_error("Checking code...")
  let assert Ok(gleam_check_out) =
    shellout.command("gleam", with: ["check"], in: ".", opt: [])
  io.println_error(gleam_check_out)

  io.println_error("Done.")
  Nil
}
