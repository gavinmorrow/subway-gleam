//// Work with the static GTFS data.

import gleam/bit_array
import gleam/bool
import gleam/dict
import gleam/float
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/list
import gleam/option
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

pub type StopId {
  StopId(route: Route, id: Int, direction: option.Option(Direction))
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

  Sir
}

pub type FetchError {
  HttpError(httpc.HttpError)
  UnzipError
  InvalidUtf8
  CsvError(gsv.Error)
  MissingFile(name: String)
  DecodeError(in_file: String)
}

pub fn fetch(feed: Feed) -> Result(Schedule, FetchError) {
  use bits <- result.try(fetch_bin(feed) |> result.map_error(HttpError))
  use files <- result.try(ffi.unzip(bits) |> result.replace_error(UnzipError))
  let files = dict.from_list(files)
  let files = {
    use _file_name, file <- dict.map_values(files)
    use file <- result.try(
      bit_array.to_string(file) |> result.replace_error(InvalidUtf8),
    )
    gsv.to_dicts(file, separator: ",") |> result.map_error(CsvError)
  }

  let parse_file = fn(
    name: String,
    parse: fn(dict.Dict(String, String)) -> Result(a, Nil),
  ) -> Result(List(a), FetchError) {
    use rows <- result.try(
      result.map(
        files
          |> dict.get(name)
          |> result.replace_error(MissingFile(name))
          |> result.flatten,
        list.map(_, parse),
      ),
    )
    result.all(rows) |> result.replace_error(DecodeError(name))
  }

  use stops <- result.try(parse_file("stops.txt", parse_stop))

  Schedule(stops:) |> Ok
}

fn fetch_bin(feed: Feed) -> Result(BitArray, httpc.HttpError) {
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

fn parse_stop(data: dict.Dict(String, String)) -> Result(Stop, Nil) {
  use id <- result.try(data |> dict.get("stop_id") |> result.try(parse_stop_id))
  use name <- result.try(data |> dict.get("stop_name"))
  use lat <- result.try(data |> dict.get("stop_lat") |> result.try(float.parse))
  use lon <- result.try(data |> dict.get("stop_lon") |> result.try(float.parse))
  let location_type =
    data
    |> dict.get("location_type")
    |> result.try(int.parse)
    |> option.from_result
  let parent_station =
    data
    |> dict.get("parent_station")
    |> result.try(parse_stop_id)
    |> option.from_result

  Stop(id:, name:, lat:, lon:, location_type:, parent_station:) |> Ok
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
  use route <- result.try(parse_route(route_id))
  use id <- result.try(int.parse(id_tens <> id_ones))
  use direction <- result.try(parse_optional_direction(direction))

  StopId(route:, id:, direction:) |> Ok
}

fn parse_route(from str: String) -> Result(Route, Nil) {
  case str {
    "A" -> Ok(A)
    "B" -> Ok(B)
    "C" -> Ok(C)
    "D" -> Ok(D)
    "E" -> Ok(E)
    "F" -> Ok(F)
    "G" -> Ok(G)
    "J" -> Ok(J)
    "L" -> Ok(L)
    "M" -> Ok(M)
    "N" -> Ok(N)
    "N1" -> Ok(N1)
    "N2" -> Ok(N2)
    "N3" -> Ok(N3)
    "N4" -> Ok(N4)
    "N5" -> Ok(N5)
    "N6" -> Ok(N6)
    "N7" -> Ok(N7)
    "Q" -> Ok(Q)
    "R" -> Ok(R)
    "S" -> Ok(S)
    "Sf" -> Ok(Sf)
    "Sir" -> Ok(Sir)
    "Sr" -> Ok(Sr)
    "W" -> Ok(W)
    "Z" -> Ok(Z)
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
