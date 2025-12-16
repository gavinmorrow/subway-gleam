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
import gleam/time/duration
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
    services: dict.Dict(Route, Service),
  )
}

pub type FetchError {
  HttpError(httpc.HttpError)
  UnzipError
  InvalidUtf8
  CsvError(gsv.Error)
  MissingFile(name: String)
  DecodeError(in_file: String, error: List(decode.DecodeError))
  InvalidStopTimes
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
  use stop_times <- result.try(parse_file("stop_times.txt", stop_time_decoder()))
  use services <- result.try(
    list.try_fold(over: stop_times, from: dict.new(), with: fn(acc, stop) {
      use route <- result.map(dict.get(trips.routes, stop.trip_id))

      use service <- dict.upsert(in: acc, update: route)
      let service = option.unwrap(service, or: empty_service(route))

      let stop = dict.get(stops, #(stop.stop_id, option.Some(stop.direction)))
      case stop {
        Error(Nil) -> service
        Ok(Stop(id:, ..)) -> Service(..service, stops: [id, ..service.stops])
      }
    })
    |> result.replace_error(InvalidStopTimes),
  )

  Schedule(stops:, trips:, services:) |> Ok
}

fn empty_service(route: Route) -> Service {
  Service(route:, stops: [])
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

pub type Service {
  Service(
    route: Route,
    // This will also probably have to be more complicated than this; it can't
    // represent branches, rush hour only stops, etc,
    stops: List(StopId),
  )
}

pub type StopTime {
  /// Primary key: `#(trip_id, stop_sequence)`
  StopTime(
    /// Identifies a trip.
    trip_id: TripId,
    /// Identifies the serviced stop. All stops serviced during a trip
    /// must have a record in stop_times.txt. Referenced locations must be
    /// stops/platforms, i.e. their stops.location_type value must be 0 or
    /// empty. A stop may be serviced multiple times in the same trip, and
    /// multiple trips and routes may service the same stop.
    stop_id: StopId,
    direction: Direction,
    /// Arrival time at the stop for a specific trip in the time zone specified
    /// by agency.agency_timezone, not stops.stop_timezone.
    /// 
    /// If there are not separate times for arrival and departure at a stop,
    /// arrival_time and departure_time should be the same.
    /// 
    /// For times occurring after midnight on the service day, enter the time as
    /// a value greater than 24:00:00 in HH:MM:SS.
    arrival_time: duration.Duration,
    /// Departure time at the stop for a specific trip in the time zone
    /// specified by agency.agency_timezone, not stops.stop_timezone.
    /// 
    /// If there are not separate times for arrival and departure at a stop,
    /// arrival_time and departure_time should be the same.
    /// 
    /// For times occurring after midnight on the service day, enter the time as
    /// a value greater than 24:00:00 in HH:MM:SS.
    departure_time: duration.Duration,
    /// Order of stops, location groups, or GeoJSON locations for a particular
    /// trip. The values must increase along the trip but do not need to be
    /// consecutive.
    stop_sequence: Int,
  )
}

fn stop_time_decoder() -> decode.Decoder(StopTime) {
  use trip_id <- decode.field("trip_id", decode.string)
  let trip_id = TripId(trip_id)
  use #(stop_id, direction) <- decode.field(
    "stop_id",
    stop_id_decoder()
      |> decode.then(fn(stop_id) {
        // There must be a direction
        case stop_id {
          #(stop_id, option.Some(direction)) ->
            decode.success(#(stop_id, direction))
          #(stop_id, option.None) ->
            decode.failure(#(stop_id, North), "StopId (with direction)")
        }
      }),
  )
  use arrival_time <- decode.field(
    "arrival_time",
    util.decode_parse_str_field(
      named: "arrival_time",
      with: parse_time,
      default: duration.seconds(0),
    ),
  )
  use departure_time <- decode.field(
    "departure_time",
    util.decode_parse_str_field(
      named: "departure_time",
      with: parse_time,
      default: duration.seconds(0),
    ),
  )
  use stop_sequence <- decode.field(
    "stop_sequence",
    util.decode_parse_str_field(
      named: "stop_sequence",
      with: int.parse,
      default: 0,
    ),
  )

  StopTime(
    trip_id:,
    stop_id:,
    direction:,
    arrival_time:,
    departure_time:,
    stop_sequence:,
  )
  |> decode.success
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
/// It is the opposite of route_id_long_to_route().
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
/// It is the opposite of route_to_long_id().
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
  Trips(headsigns: dict.Dict(ShapeId, String), routes: dict.Dict(TripId, Route))
}

pub type TripId {
  TripId(String)
}

fn extract_shape_id(from trip_id: TripId) {
  let TripId(id) = trip_id
  string.split(id, on: "_") |> list.last |> result.map(ShapeId)
}

fn trips_from_rows(rows: List(Trip)) -> Trips {
  let headsigns =
    list.fold(over: rows, from: dict.new(), with: fn(headsigns, trip) {
      let shape_id_from_trip_id = extract_shape_id(from: trip.id)
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

  let routes =
    list.fold(over: rows, from: dict.new(), with: fn(routes, trip) {
      dict.insert(into: routes, for: trip.id, insert: trip.route_id)
    })

  Trips(headsigns:, routes:)
}

/// Intended for when parsing the raw rows, before parsing `Trips`
type Trip {
  Trip(
    id: TripId,
    route_id: Route,
    headsign: String,
    shape_id: option.Option(ShapeId),
  )
}

fn trip_decoder() -> decode.Decoder(Trip) {
  use id <- decode.field("trip_id", decode.string)
  let id = TripId(id)
  use route_id <- decode.field("route_id", route_id_in_trip_decoder())
  use headsign <- decode.field("trip_headsign", decode.string)
  use shape_id <- decode.optional_field(
    "shape_id",
    option.None,
    shape_id_decoder() |> decode.map(option.Some),
  )
  decode.success(Trip(id:, route_id:, headsign:, shape_id:))
}

fn route_id_in_trip_decoder() -> decode.Decoder(Route) {
  use route <- decode.then(decode.string)
  case route {
    "A" -> A |> decode.success
    "B" -> B |> decode.success
    "C" -> C |> decode.success
    "D" -> D |> decode.success
    "E" -> E |> decode.success
    "F" | "FX" -> F |> decode.success
    "G" -> G |> decode.success
    "J" -> J |> decode.success
    "L" -> L |> decode.success
    "M" -> M |> decode.success
    "N" -> N |> decode.success
    "1" -> N1 |> decode.success
    "2" -> N2 |> decode.success
    "3" -> N3 |> decode.success
    "4" -> N4 |> decode.success
    "5" -> N5 |> decode.success
    "6" | "6X" -> N6 |> decode.success
    "7" | "7X" -> N7 |> decode.success
    "Q" -> Q |> decode.success
    "R" -> R |> decode.success
    "GS" -> S |> decode.success
    "FS" -> Sf |> decode.success
    "SI" -> Si |> decode.success
    "H" -> Sr |> decode.success
    "W" -> W |> decode.success
    "Z" -> Z |> decode.success
    route -> decode.failure(A, "Route (in trip) (" <> route <> ")")
  }
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

/// Parses a static GTFS `Time`.
/// 
/// Time in the HH:MM:SS format (H:MM:SS is also accepted). The time is measured
/// from "noon minus 12h" of the service day (effectively midnight except for
/// days on which daylight savings time changes occur). For times occurring
/// after midnight on the service day, enter the time as a value greater than
/// 24:00:00 in HH:MM:SS.
/// 
/// Example: 14:30:00 for 2:30PM or 25:35:00 for 1:35AM on the next day.
fn parse_time(from timestamp: String) -> Result(duration.Duration, Nil) {
  case string.split(timestamp, on: ":") {
    [hours, minutes, seconds] -> {
      // Hours may be specified with one digit.
      // Ensure adherence to the spec in terms of length (HH:MM:SS or H:MM:SS).
      use <- bool.guard(when: string.length(hours) > 2, return: Error(Nil))
      use <- bool.guard(when: string.length(minutes) != 2, return: Error(Nil))
      use <- bool.guard(when: string.length(seconds) != 2, return: Error(Nil))

      use hours <- result.try(int.parse(hours))
      use minutes <- result.try(int.parse(minutes))
      use seconds <- result.try(int.parse(seconds))

      // Hours may be >24 to roll over to next day.
      // Ensure that min/sec are sane though.
      use <- bool.guard(when: minutes >= 60, return: Error(Nil))
      use <- bool.guard(when: seconds >= 60, return: Error(Nil))

      let total_sec = hours * 60 * 60 + minutes * 60 + seconds
      duration.seconds(total_sec) |> Ok
    }
    _ -> Error(Nil)
  }
}
