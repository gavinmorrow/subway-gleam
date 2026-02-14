import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import lustre/element
import lustre/element/html
import subway_gleam/shared/ffi/geolocation
import subway_gleam/shared/util
import subway_gleam/shared/util/haversine

import subway_gleam/gtfs/st

pub type Model {
  Model(
    all_stops: List(st.Stop(Nil)),
    cur_position: option.Option(geolocation.Position),
  )
}

pub fn view(model: Model) -> element.Element(msg) {
  let Model(all_stops:, cur_position:) = model

  // DEBUG
  let cur_position =
    geolocation.Position(
      latitude: 40.7127667,
      longitude: -74.0060544,
      accuracy: 10.0,
      // Okay to use current time bc this is for debugging
      timestamp: util.current_time(),
    )
    |> option.Some

  let stops_nearby =
    option.map(cur_position, fn(pos) {
      all_stops
      |> list.filter(keeping: fn(stop) { stop_distance(stop, pos:) <. 800.0 })
      |> list.sort(by: fn(a, b) {
        float.compare(stop_distance(a, pos:), with: stop_distance(b, pos:))
      })
      |> list.map(stop_li)
    })
  let stops_nearby = case stops_nearby {
    option.Some(lis) -> html.li([], lis)
    option.None -> html.p([], [html.text("No stops nearby.")])
  }

  html.div([], [html.h1([], [html.text("Stops Nearby")]), stops_nearby])
}

fn stop_li(stop: st.Stop(Nil)) -> element.Element(msg) {
  html.li([], [html.text(stop.name)])
}

/// The distance between a stop and a position, in meters.
fn stop_distance(stop: st.Stop(Nil), pos pos: geolocation.Position) -> Float {
  // TODO: account for pos accuracy
  let distance_km =
    haversine.distance(from: #(stop.lat, stop.lon), to: #(
      pos.latitude,
      pos.longitude,
    ))
  distance_km *. 1000.0
}

pub fn model_decoder() -> decode.Decoder(Model) {
  use all_stops <- decode.field("all_stops", decode.list(of: stop_decoder()))

  Model(all_stops:, cur_position: option.None) |> decode.success
}

pub fn model_to_json(model: Model) -> json.Json {
  let Model(all_stops:, cur_position: _) = model
  json.object([#("all_stops", json.array(from: all_stops, of: stop_to_json))])
}

fn stop_decoder() -> decode.Decoder(st.Stop(Nil)) {
  let float_or_int_decoder =
    decode.one_of(decode.float, or: [decode.int |> decode.map(int.to_float)])

  use id <- decode.field("id", decode.string |> decode.map(st.StopId))
  use name <- decode.field("name", decode.string)
  use lat <- decode.field("lat", float_or_int_decoder)
  use lon <- decode.field("lon", float_or_int_decoder)

  st.Stop(
    id:,
    direction: Nil,
    name:,
    lat:,
    lon:,
    location_type: option.None,
    parent_station: option.None,
  )
  |> decode.success
}

fn stop_to_json(stop: st.Stop(Nil)) -> json.Json {
  let st.Stop(
    id:,
    direction: _,
    name:,
    lat:,
    lon:,
    location_type: _,
    parent_station: _,
  ) = stop
  let st.StopId(id) = id

  json.object([
    #("id", json.string(id)),
    #("name", json.string(name)),
    #("lat", json.float(lat)),
    #("lon", json.float(lon)),
  ])
}
