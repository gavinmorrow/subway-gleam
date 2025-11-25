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
import subway_gleam/internal/util

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
  Schedule(
    stops: dict.Dict(
      #(StopId, option.Option(Direction)),
      Stop(option.Option(Direction)),
    ),
    trips: Trips,
  )
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
    use file <- result.try(
      files
      |> dict.get(name)
      |> result.replace_error(MissingFile(name))
      |> result.flatten,
    )
    let rows = list.map(file, decode.run(_, decoder))
    result.all(rows) |> result.map_error(DecodeError(name, _))
  }

  // TODO: reverse order
  use trips <- result.try(parse_file("trips.txt", trip_decoder()))
  let trips = trips_from_rows(trips)
  use stops <- result.try(parse_file("stops.txt", stop_decoder()))
  let stops =
    list.fold(over: stops, from: dict.new(), with: fn(acc, stop) {
      acc |> dict.insert(for: #(stop.id, stop.direction), insert: stop)
    })

  Schedule(stops:, trips:) |> Ok
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

pub type Stop(direction) {
  Stop(
    id: StopId,
    direction: direction,
    name: String,
    lat: Float,
    lon: Float,
    location_type: option.Option(Int),
    parent_station: option.Option(StopId),
  )
}

fn stop_decoder() -> decode.Decoder(Stop(option.Option(Direction))) {
  use #(id, direction) <- decode.field("stop_id", stop_id_decoder())
  use name <- decode.field("stop_name", decode.string)
  use lat <- decode.field(
    "stop_lat",
    util.decode_parse_str_field(named: "lat", with: float.parse, default: 0.0),
  )
  use lon <- decode.field(
    "stop_lon",
    util.decode_parse_str_field(named: "lon", with: float.parse, default: 0.0),
  )
  use location_type <- decode.optional_field(
    "location_type",
    option.None,
    util.decode_parse_str_field(
      named: "location_type",
      with: int.parse,
      default: 0,
    )
      |> decode.map(option.Some),
  )
  use parent_station <- decode.optional_field(
    "parent_station",
    option.None,
    stop_id_decoder()
      |> decode.then(fn(stop_id) {
        // Ensure that direction is None 
        case stop_id {
          #(stop_id, option.None) -> decode.success(stop_id)
          #(stop_id, option.Some(_)) ->
            decode.failure(stop_id, "StopId (no direction)")
        }
      })
      |> decode.map(option.Some),
  )

  decode.success(Stop(
    id:,
    direction:,
    name:,
    lat:,
    lon:,
    location_type:,
    parent_station:,
  ))
}

pub type StopId {
  /// A route followed by a two-digit number (e.g. `A01`).
  StopId(String)
}

const stop_id_default = StopId("A01")

fn stop_id_decoder() -> decode.Decoder(#(StopId, option.Option(Direction))) {
  use stop_id <- decode.then(decode.string)
  case parse_stop_id(from: stop_id) {
    Error(Nil) -> {
      echo "could not decode stop id " <> stop_id
      decode.failure(#(stop_id_default, option.None), "StopId")
    }
    Ok(#(stop_id, direction)) -> decode.success(#(stop_id, direction))
  }
}

pub fn stop_id_to_string(
  stop_id stop_id: StopId,
  direction direction: option.Option(Direction),
) -> String {
  let StopId(id) = stop_id
  id <> direction_to_string(direction)
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

pub fn parse_stop_id(
  from str: String,
) -> Result(#(StopId, option.Option(Direction)), Nil) {
  // The stop id should be either 3 or 4 digits
  // (route + two digit id + optional direction)
  let len = string.length(str)
  use <- bool.guard(when: !{ len == 3 || len == 4 }, return: Error(Nil))

  // id is the first 3 chars
  let id = string.slice(from: str, at_index: 0, length: 3)

  // `string.last` really shouldn't fail since we checked the length above, but
  // there's no good reason to assert.
  use direction <- result.try(string.last(str))
  // Direction is optional
  // The last character is either `N` or `S`, in which case there is a
  // direction; or a number, in which case there is not.
  let direction = case direction {
    "N" -> option.Some(North)
    "S" -> option.Some(South)
    _ -> option.None
  }

  #(StopId(id), direction) |> Ok
}

pub fn parse_stop_id_no_direction(from str: String) -> Result(StopId, Nil) {
  use #(id, direction) <- result.try(parse_stop_id(from: str))
  case direction {
    option.None -> Ok(id)
    option.Some(_) -> Error(Nil)
  }
}

/// This exists so that the app can convert Route <=> String losslessly.
/// It is essentially string.inspect.
pub fn route_to_long_id(route: Route) -> String {
  case route {
    A -> "A"
    B -> "B"
    C -> "C"
    D -> "D"
    E -> "E"
    F -> "F"
    G -> "G"
    J -> "J"
    L -> "L"
    M -> "M"
    N -> "N"
    N1 -> "1"
    N2 -> "2"
    N3 -> "3"
    N4 -> "4"
    N5 -> "5"
    N6 -> "6"
    N7 -> "7"
    Q -> "Q"
    R -> "R"
    S -> "S"
    Sf -> "Sf"
    Si -> "Si"
    Sr -> "Sr"
    W -> "W"
    Z -> "Z"
  }
}

/// This exists so that the app can convert Route <=> String losslessly.
/// It is the opposite of route_to_string_long().
pub fn route_id_long_to_route(route: String) -> Result(Route, Nil) {
  case route {
    "A" -> A |> Ok
    "B" -> B |> Ok
    "C" -> C |> Ok
    "D" -> D |> Ok
    "E" -> E |> Ok
    "F" -> F |> Ok
    "G" -> G |> Ok
    "J" -> J |> Ok
    "L" -> L |> Ok
    "M" -> M |> Ok
    "N" -> N |> Ok
    "1" -> N1 |> Ok
    "2" -> N2 |> Ok
    "3" -> N3 |> Ok
    "4" -> N4 |> Ok
    "5" -> N5 |> Ok
    "6" -> N6 |> Ok
    "7" -> N7 |> Ok
    "Q" -> Q |> Ok
    "R" -> R |> Ok
    "S" -> S |> Ok
    "Sf" -> Sf |> Ok
    "Si" -> Si |> Ok
    "Sr" -> Sr |> Ok
    "W" -> W |> Ok
    "Z" -> Z |> Ok
    _ -> Error(Nil)
  }
}

pub fn direction_to_string(direction: option.Option(Direction)) -> String {
  case direction {
    option.None -> ""
    option.Some(North) -> "N"
    option.Some(South) -> "S"
  }
}

pub type Trips {
  Trips(headsigns: dict.Dict(ShapeId, String))
}

fn trips_from_rows(rows: List(Trip)) -> Trips {
  let headsigns =
    list.fold(over: rows, from: dict.new(), with: fn(headsigns, trip) {
      let shape_id_from_trip_id =
        string.split(trip.id, on: "_") |> list.last |> result.map(ShapeId)
      let shape_id = case trip.shape_id, shape_id_from_trip_id {
        option.Some(trip_shape_id), Ok(shape_id_from_trip_id) -> {
          // TODO: get rid of assert
          assert trip_shape_id == shape_id_from_trip_id
          trip_shape_id
        }
        option.Some(shape_id), Error(Nil) -> shape_id
        option.None, Ok(shape_id) -> shape_id
        // TODO: get rid of panic
        option.None, Error(Nil) -> panic as "no shape id"
      }
      case dict.get(headsigns, shape_id) {
        Error(Nil) ->
          dict.insert(into: headsigns, for: shape_id, insert: trip.headsign)
        Ok(headsign) -> {
          // TODO: get rid of assert
          assert headsign == trip.headsign
          headsigns
        }
      }
    })
  Trips(headsigns:)
}

/// Intended for when parsing the raw rows, before parsing `Trips`
type Trip {
  Trip(id: String, headsign: String, shape_id: option.Option(ShapeId))
}

fn trip_decoder() -> decode.Decoder(Trip) {
  use id <- decode.field("trip_id", decode.string)
  use headsign <- decode.field("trip_headsign", decode.string)
  use shape_id <- decode.optional_field(
    "shape_id",
    option.None,
    shape_id_decoder() |> decode.map(option.Some),
  )
  decode.success(Trip(id:, headsign:, shape_id:))
}

pub opaque type ShapeId {
  ShapeId(String)
}

fn shape_id_decoder() -> decode.Decoder(ShapeId) {
  use shape_id <- decode.then(decode.string)
  ShapeId(shape_id) |> decode.success
}

pub fn parse_shape_id(from trip_id: String) -> Result(ShapeId, Nil) {
  trip_id
  |> string.split(on: "_")
  |> list.last
  |> result.map(ShapeId)
}
