//// Work with the static GTFS data.

import gleam/bool
import gleam/erlang/charlist
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/list
import gleam/option
import gleam/pair
import gleam/result
import gleam/string
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
  UnzipError(Nil)
}

pub fn fetch(feed: Feed) -> Result(Schedule, FetchError) {
  use bits <- result.try(fetch_bin(feed) |> result.map_error(HttpError))
  use files <- result.try(ffi.unzip(bits) |> result.map_error(UnzipError))
  todo
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
