//// A dataset listing all subway and Staten Island Railway stations, with data
//// aggregated by station complex. This dataset includes information on station
//// names, their locations, Station IDs, Complex IDs, GTFS Stop IDs, the
//// services that stop there, the type of structure the station is on or in,
//// whether they are in Manhattan’s Central Business District (CBD), and their
//// ADA-accessibility status.
////
//// <https://data.ny.gov/Transportation/MTA-Subway-Stations-and-Complexes/5f5g-n3cz/about_data>

import gleam/bit_array
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/float
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/list
import gleam/pair
import gleam/result
import gleam/string
import gsv
import subway_gleam/internal/util
import subway_gleam/st

pub type StationComplex {
  StationComplex(
    /// The Complex ID, or its Complex Master Reference Number. `complex_id`
    id: StationComplexId,
    /// TRUE if this is a station complex, and FALSE if not. `is_complex`
    is_complex: Bool,
    /// The number of stations within a station complex or 1 if the station is
    /// not a station complex. `number_of_stations_in_complex`
    num_stations_in_complex: Int,
    /// The name of the subway station. `stop_name`
    stop_name: String,
    /// The name of the subway station, with the services that serve the station
    /// during weekday daytime hours in parenthesis. `display_name`
    display_name: String,
    /// The name of the subway station or of multiple subway stations
    /// within one station complex, separated by a semi-colon. For stations
    /// that are not in complexes, this is identical to the stop name.
    /// `constituent_station_names`
    constituent_station_names: List(String),
    /// The ID, or Master Reference Number, for the station. If it is a
    /// station complex, multiple IDs are shown, separated by a semi-colon.
    /// `station_ids`
    station_ids: List(StationId),
    /// The GTFS Stop ID or IDs for the station. If it is a station complex,
    /// multiple IDs are shown, separated by a semi-colon. `gtfs_stop_ids`
    gtfs_stop_ids: List(st.StopId),
    /// The borough the station is in. Bx for Bronx, B for Brooklyn, M for
    /// Manhattan, Q for Queens, SI for Staten Island. `borough`
    borough: Borough,
    /// This indicates whether or not a station is in Manhattan’s Central
    /// Business District (CBD). This value is either TRUE or FALSE. `cbd`
    in_cbd: Bool,
    /// The subway routes that serve the station during weekdays.
    /// `daytime_routes`
    daytime_routes: List(Route),
    /// The type of structure the subway station is located on or in (At Grade,
    /// Elevated, Embankment, Open Cut, Subway, Viaduct, etc.). If it is a
    /// station complex, and the component stations have different structure
    /// types, both are noted, separated by a semi-colon. `structure_type`
    structure_type: List(StructureType),
    /// The latitude for the centroid of the station complex. `latitude`
    latitude: Float,
    /// The longitude for the centroid of the station complex. `longitude`
    longitude: Float,
    /// 0 if the station is not ADA-accessible, 1 if the station is fully
    /// accessible, 2 if the station is partially accessible. `ada`
    ada_status: AdaStatus,
  )
}

pub type FetchError {
  HttpError(httpc.HttpError)
  InvalidUtf8
  CsvError(gsv.Error)
  DecodeError(List(decode.DecodeError))
}

pub fn fetch_bin() -> Result(BitArray, httpc.HttpError) {
  let req: request.Request(BitArray) =
    request.new()
    |> request.set_host("data.ny.gov")
    |> request.set_path("api/views/5f5g-n3cz/rows.csv")
    |> request.set_body(<<>>)

  use res <- result.try(httpc.send_bits(req))
  res.body |> Ok
}

pub fn parse(file_bits: BitArray) -> Result(List(StationComplex), FetchError) {
  use file <- result.try(
    bit_array.to_string(file_bits) |> result.replace_error(InvalidUtf8),
  )

  use rows <- result.try(
    gsv.to_dicts(file, separator: ",")
    |> result.map_error(CsvError),
  )
  // 
  // Transform into List(dynamic.Dynamic)
  let rows =
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

  rows
  |> list.try_map(decode.run(_, station_complex_decoder()))
  |> result.map_error(DecodeError)
}

pub fn station_complex_decoder() -> decode.Decoder(StationComplex) {
  use id <- decode.field(
    "Complex ID",
    util.decode_parse_str_field(
      named: "complex_id",
      with: station_complex_id_parse,
      default: StationComplexId(0),
    ),
  )
  use is_complex <- decode.field(
    "Is Complex",
    util.decode_parse_str_field(
      named: "is_complex",
      with: bool_string_parse,
      default: False,
    ),
  )
  use num_stations_in_complex <- decode.field(
    "Number Of Stations In Complex",
    util.decode_parse_str_field(
      named: "num_stations_in_complex",
      with: int.parse,
      default: 0,
    ),
  )
  use stop_name <- decode.field("Stop Name", decode.string)
  use display_name <- decode.field("Display Name", decode.string)
  use constituent_station_names <- decode.field(
    "Constituent Station Names",
    util.decode_parse_str_field(
      named: "constituent_station_names",
      with: list_string_parse(_, on: "; ", with: Ok),
      default: [stop_name],
    ),
  )
  use station_ids <- decode.field(
    "Station IDs",
    util.decode_parse_str_field(
      named: "station_ids",
      with: list_string_parse(_, on: "; ", with: station_id_parse),
      default: [],
    ),
  )
  use gtfs_stop_ids <- decode.field(
    "GTFS Stop IDs",
    util.decode_parse_str_field(
      named: "gtfs_stop_ids",
      with: list_string_parse(_, on: "; ", with: st.parse_stop_id),
      default: [],
    ),
  )
  use borough <- decode.field("Borough", borough_decoder())
  use in_cbd <- decode.field(
    "CBD",
    util.decode_parse_str_field(
      named: "in_cbd",
      with: bool_string_parse,
      default: False,
    ),
  )
  use daytime_routes <- decode.field(
    "Daytime Routes",
    util.decode_parse_str_field(
      named: "daytime_routes",
      with: list_string_parse(_, on: " ", with: route_parse),
      default: [],
    ),
  )
  use structure_type <- decode.field(
    "Structure Type",
    util.decode_parse_str_field(
      named: "structure_type",
      with: list_string_parse(_, on: "; ", with: structure_type_parse),
      default: [],
    ),
  )
  use latitude <- decode.field(
    "Latitude",
    util.decode_parse_str_field(named: "lat", with: float.parse, default: 0.0),
  )
  use longitude <- decode.field(
    "Longitude",
    util.decode_parse_str_field(named: "lon", with: float.parse, default: 0.0),
  )
  use ada_status <- decode.then(ada_status_decoder())
  decode.success(StationComplex(
    id:,
    is_complex:,
    num_stations_in_complex:,
    stop_name:,
    display_name:,
    constituent_station_names:,
    station_ids:,
    gtfs_stop_ids:,
    borough:,
    in_cbd:,
    daytime_routes:,
    structure_type:,
    latitude:,
    longitude:,
    ada_status:,
  ))
}

pub type StationComplexId {
  StationComplexId(Int)
}

fn station_complex_id_parse(str: String) -> Result(StationComplexId, Nil) {
  str |> int.parse |> result.map(StationComplexId)
}

pub type StationId {
  StationId(Int)
}

fn station_id_parse(id: String) -> Result(StationId, Nil) {
  int.parse(id) |> result.map(StationId)
}

pub type Borough {
  Manhattan
  Brooklyn
  Bronx
  Queens
  StatenIsland
}

const borough_default = Manhattan

fn borough_decoder() -> decode.Decoder(Borough) {
  use variant <- decode.then(decode.string)
  case variant {
    "M" -> decode.success(Manhattan)
    "Bk" -> decode.success(Brooklyn)
    "Bx" -> decode.success(Bronx)
    "Q" -> decode.success(Queens)
    "SI" -> decode.success(StatenIsland)
    borough -> decode.failure(borough_default, "Borough(" <> borough <> ")")
  }
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

  L
  G
  S
  Sir
}

fn route_parse(route: String) -> Result(Route, Nil) {
  case route {
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
    "J" -> Ok(J)
    "Z" -> Ok(Z)
    "L" -> Ok(L)
    "G" -> Ok(G)
    "S" -> Ok(S)
    "SIR" -> Ok(Sir)
    _ -> Error(Nil)
  }
}

pub type StructureType {
  Subway
  Elevated
  AtGrade
  OpenCut
  Embankment
  Viaduct
}

fn structure_type_parse(variant: String) -> Result(StructureType, Nil) {
  case variant {
    "Subway" -> Ok(Subway)
    "Elevated" -> Ok(Elevated)
    "At Grade" -> Ok(AtGrade)
    "Open Cut" -> Ok(OpenCut)
    "Embankment" -> Ok(Embankment)
    "Viaduct" -> Ok(Viaduct)
    _ -> Error(Nil)
  }
}

pub type AdaStatus {
  /// Not ADA accessible. Encoded by `0`.
  NoAda
  /// Fully ADA accessible. Encoded by `1`.
  FullAda
  /// Partially ADA accessible. Encoded by `2`.
  PartialAda(
    /// Notes on the direction a station is accessible in if it is only
    /// accessible in one direction or for a particular platform. `ada_notes`
    notes: String,
  )
}

const ada_status_default = NoAda

fn ada_status_decoder() -> decode.Decoder(AdaStatus) {
  use ada_status <- decode.field("ADA", decode.string)
  case ada_status {
    "0" -> decode.success(NoAda)
    "1" -> decode.success(FullAda)
    "2" -> {
      use notes <- decode.field("ADA Notes", decode.string)
      decode.success(PartialAda(notes:))
    }
    _ -> decode.failure(ada_status_default, "AdaStatus")
  }
}

fn bool_string_parse(str: String) -> Result(Bool, Nil) {
  case str {
    "true" -> Ok(True)
    "false" -> Ok(False)
    _ -> Error(Nil)
  }
}

fn list_string_parse(
  from data: String,
  on splitter: String,
  with parse: fn(String) -> Result(a, Nil),
) -> Result(List(a), Nil) {
  data
  |> string.split(on: splitter)
  |> list.try_map(parse)
}
