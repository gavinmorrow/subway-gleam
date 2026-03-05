import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import lustre
import lustre/effect.{type Effect}
import plinth/browser/document
import plinth/browser/element
import plinth/javascript/storage

import subway_gleam/shared/ffi/geolocation
import subway_gleam/shared/route/stops.{type Model, Model, view}

pub fn main() -> Result(lustre.Runtime(Msg), lustre.Error) {
  // TODO: handle errors: model not found, and invalid JSON
  let assert Ok(Ok(model)) =
    document.get_element_by_id("model")
    |> result.map(element.inner_text)
    |> result.map(json.parse(from: _, using: stops.model_decoder()))

  // TODO: handle (or log?) various errors here
  let fav_stops = result.unwrap(get_fav_stops(), or: [])
  let model = Model(..model, fav_stops:)

  let app = lustre.application(init, update, view)
  lustre.start(app, onto: "#app", with: model)
}

fn get_fav_stops() -> Result(List(stops.StopLi), Nil) {
  use storage <- result.try(storage.local())
  use fav_stops <- result.try(storage.get_item(storage, "fav_stops"))
  json.parse(from: fav_stops, using: decode.list(of: stops.stop_li_decoder()))
  |> result.replace_error(Nil)
}

fn update_fav_stops(
  with fun: fn(List(stops.StopLi)) -> List(stops.StopLi),
) -> Result(Nil, Nil) {
  use storage <- result.try(storage.local())
  let fav_stops = result.unwrap(get_fav_stops(), or: [])
  let fav_stops = fun(fav_stops)
  storage.set_item(
    storage,
    "fav_stops",
    fav_stops |> json.array(of: stops.stop_li_to_json) |> json.to_string,
  )
}

pub fn add_fav_stop(stop: stops.StopLi) -> Result(Nil, Nil) {
  use fav_stops <- update_fav_stops
  [stop, ..fav_stops]
}

pub fn remove_fav_stop(stop: stops.StopLi) -> Result(Nil, Nil) {
  use fav_stops <- update_fav_stops
  list.filter(fav_stops, keeping: fn(s) { s != stop })
}

pub fn is_fav_stop(stop: stops.StopLi) -> Bool {
  get_fav_stops() |> result.unwrap(or: []) |> list.contains(stop)
}

pub type Msg {
  UpdatePosition(geolocation.Position)
}

fn init(flags: Model) -> #(Model, effect.Effect(Msg)) {
  #(flags, watch_position())
}

fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    UpdatePosition(cur_position) -> #(
      Model(..model, cur_position: option.Some(cur_position)),
      effect.none(),
    )
  }
}

fn watch_position() -> Effect(Msg) {
  use dispatch <- effect.from
  let _id =
    geolocation.watch_position(
      on_success: fn(pos) { dispatch(UpdatePosition(pos)) },
      on_error: fn(err) { todo },
    )
  Nil
}
