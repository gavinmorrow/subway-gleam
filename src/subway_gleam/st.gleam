//// Work with the static GTFS data.

import gleam/bit_array
import gleam/bool
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/float
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/list
import gleam/option
import gleam/pair
import gleam/result
import gleam/string
import gsv
import subway_gleam/internal/ffi

pub type Feed {
  /// This file represents the "normal" subway schedule and does not include
  /// most temporary service changes, though some long term service changes may
  /// be included. It is typically updated a few times a year.
  Regular
  /// This file includes most, but not all, service changes for the next seven
  /// calendar days. Generally, the 'simpler' the service change, the more
  /// likely it will not be included. Beyond that period, service changes will
  /// not be included. It is updated **hourly**.
  Supplemented
}

pub type Schedule {
  Schedule(stops: List(Stop))
}

pub type Stop {
  Stop(
    id: StopId,
    name: String,
    lat: Float,
    lon: Float,
    location_type: option.Option(Int),
    parent_station: option.Option(StopId),
  )
}

fn stop_decoder() -> decode.Decoder(Stop) {
  let parse_str_field = fn(
    name: String,
    parse: fn(String) -> Result(a, Nil),
    default: a,
  ) -> decode.Decoder(a) {
    use str <- decode.then(decode.string)
    parse(str)
    |> result.map(decode.success)
    |> result.unwrap(or: decode.failure(default, name))
  }

  use id <- decode.field("stop_id", stop_id_decoder())
  use name <- decode.field("stop_name", decode.string)
  use lat <- decode.field("stop_lat", parse_str_field("lat", float.parse, 0.0))
  use lon <- decode.field("stop_lon", parse_str_field("lon", float.parse, 0.0))
  use location_type <- decode.optional_field(
    "location_type",
    option.None,
    parse_str_field("location_type", int.parse, 0) |> decode.map(option.Some),
  )
  use parent_station <- decode.optional_field(
    "parent_station",
    option.None,
    stop_id_decoder() |> decode.map(option.Some),
  )
  decode.success(Stop(id:, name:, lat:, lon:, location_type:, parent_station:))
}

pub type StopId {
  StopId(route: Route, id: Int, direction: option.Option(Direction))
}

const stop_id_default = StopId(route: A, id: 0, direction: option.None)

fn stop_id_decoder() -> decode.Decoder(StopId) {
  use stop_id <- decode.then(decode.string)
  case parse_stop_id(from: stop_id) {
    Error(Nil) -> {
      echo "could not decode stop id " <> stop_id
      decode.failure(stop_id_default, "StopId")
    }
    Ok(stop_id) -> decode.success(stop_id)
  }
}

pub type Direction {
  North
  South
}

pub type Route {
  N1
  N2
  N3

  N4
  N5
  N6

  N7

  A
  C
  E

  B
  D
  F
  M

  N
  Q
  R
  W

  J
  Z

  G

  L

  S
  Sr
  Sf

  Si
}

pub type FetchError {
  HttpError(httpc.HttpError)
  UnzipError
  InvalidUtf8
  CsvError(gsv.Error)
  MissingFile(name: String)
  DecodeError(in_file: String, error: List(decode.DecodeError))
}

pub fn parse(bits: BitArray) -> Result(Schedule, FetchError) {
  use files <- result.try(ffi.unzip(bits) |> result.replace_error(UnzipError))
  let files = dict.from_list(files)
  let files = {
    use _file_name, file <- dict.map_values(files)
    use file <- result.try(
      bit_array.to_string(file) |> result.replace_error(InvalidUtf8),
    )
    use rows <- result.map(
      gsv.to_dicts(file, separator: ",")
      |> result.map_error(CsvError),
    )

    // Transform into List(dynamic.Dynamic)
    list.map(rows, fn(row) {
      row
      |> dict.to_list
      |> list.map(fn(kv) {
        kv
        |> pair.map_first(dynamic.string)
        |> pair.map_second(dynamic.string)
      })
      |> dynamic.properties
    })
  }

  let parse_file = fn(name: String, decoder: decode.Decoder(a)) -> Result(
    List(a),
    FetchError,
  ) {
    use rows <- result.try(
      result.map(
        files
          |> dict.get(name)
          |> result.replace_error(MissingFile(name))
          |> result.flatten,
        list.map(_, decode.run(_, decoder)),
      ),
    )
    result.all(rows) |> result.map_error(DecodeError(name, _))
  }

  use stops <- result.try(parse_file("stops.txt", stop_decoder()))

  Schedule(stops:) |> Ok
}

pub fn fetch_bin(feed: Feed) -> Result(BitArray, httpc.HttpError) {
  let req: request.Request(BitArray) =
    request.new()
    |> request.set_host("rrgtfsfeeds.s3.amazonaws.com")
    |> request.set_path(feed_path(feed))
    |> request.set_body(<<>>)

  use res <- result.try(httpc.send_bits(req))
  res.body |> Ok
}

fn feed_path(feed: Feed) -> String {
  case feed {
    Regular -> "gtfs_subway.zip"
    Supplemented -> "gtfs_supplemented.zip"
  }
}

fn parse_stop_id(from str: String) -> Result(StopId, Nil) {
  // TODO: using bytes instead of graphemes would be way more performant, but
  //       there's nothing in the gleam stdlib for it.
  use #(route_id, rest) <- result.try(string.pop_grapheme(str))
  use #(id_tens, rest) <- result.try(string.pop_grapheme(rest))
  use #(id_ones, rest) <- result.try(string.pop_grapheme(rest))

  // Direction is optional
  let #(direction, rest) = string.pop_grapheme(rest) |> result.unwrap(#("", ""))

  // Ensure there is nothing left afterwards
  use <- bool.guard(when: !string.is_empty(rest), return: Error(Nil))

  // Parse each part
  use id <- result.try(int.parse(id_tens <> id_ones))
  // Route needs to come after id because it requires an id
  use route <- result.try(parse_route(from: route_id, at: id))
  use direction <- result.try(parse_optional_direction(direction))

  StopId(route:, id:, direction:) |> Ok
}

/// The stop number/`id` is needed b/c the Si and Sf share an identifier ("S"),
/// and the only way to differentiate is via the stop number.
fn parse_route(from str: String, at id: Int) -> Result(Route, Nil) {
  case str {
    "1" -> Ok(N1)
    "2" -> Ok(N2)
    "3" -> Ok(N3)
    "4" -> Ok(N4)
    "5" -> Ok(N5)
    "6" -> Ok(N6)
    "7" -> Ok(N7)

    "A" -> Ok(A)
    "C" -> Ok(C)
    "E" -> Ok(E)

    "B" -> Ok(B)
    "D" -> Ok(D)
    "F" -> Ok(F)
    "M" -> Ok(M)

    "N" -> Ok(N)
    "Q" -> Ok(Q)
    "R" -> Ok(R)
    "W" -> Ok(W)

    "G" -> Ok(G)

    "J" -> Ok(J)
    "Z" -> Ok(Z)

    "L" -> Ok(L)

    // In the GTFS, the Sf and Si routes have the same prefix (S).
    // The Sf gets stop numbers [1, 8] while the Sir gets [9, 31].
    // The normal S gets the prefix 9, while Sr gets H (which it shares with
    // both Far-Rockaway-bound and Rockaway-Park-bound A trains).
    "9" -> Ok(S)
    "H" -> Ok(Sr)
    "S" if id < 9 -> Sf |> Ok
    "S" if id >= 9 -> Si |> Ok

    _ -> Error(Nil)
  }
}

fn parse_optional_direction(
  from str: String,
) -> Result(option.Option(Direction), Nil) {
  case str {
    "N" -> Ok(option.Some(North))
    "S" -> Ok(option.Some(South))
    "" -> Ok(option.None)
    _ -> Error(Nil)
  }
}
