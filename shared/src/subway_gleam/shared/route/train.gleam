import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/time/duration
import gleam/time/timestamp
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

import subway_gleam/shared/component/route_bullet.{
  type RouteBullet, route_bullet,
}
import subway_gleam/shared/util
import subway_gleam/shared/util/live_status.{type LiveStatus}
import subway_gleam/shared/util/timestamp_json

pub type Model {
  Model(
    last_updated: timestamp.Timestamp,
    stops: List(Stop),
    event_source: LiveStatus,
    // TODO: move highlighted out of Stop and into here
  )
}

pub fn view(model: Model) -> Element(msg) {
  let Model(last_updated:, stops:, event_source:) = model

  // TODO: filter by ∆t > 0
  let stops = list.map(stops, stop_li)

  let live_status = case event_source {
    live_status.Connecting(_) -> element.text("Conecting...")
    live_status.Live(_) -> element.text("Live!")
    live_status.Unavailable -> element.text("Live not available.")
  }

  html.div([], [
    html.p([], [
      html.text(
        "Last updated "
        <> last_updated |> timestamp.to_rfc3339(duration.hours(-4)),
      ),
      html.br([]),
      live_status,
    ]),
    html.ol([attribute.class("stops-list")], stops),
  ])
}

pub fn model_decoder() -> decode.Decoder(Model) {
  use last_updated <- decode.field("last_updated", timestamp_json.decoder())
  use stops <- decode.field("stops", decode.list(stop_decoder()))
  decode.success(Model(
    last_updated:,
    stops:,
    event_source: live_status.Unavailable,
  ))
}

pub fn model_to_json(model: Model) -> json.Json {
  let Model(last_updated:, stops:, event_source: _) = model
  json.object([
    #("last_updated", timestamp_json.to_json(last_updated)),
    #("stops", json.array(stops, stop_to_json)),
  ])
}

pub type Stop {
  Stop(
    name: String,
    stop_url: String,
    is_highlighted: Bool,
    transfers: List(RouteBullet),
    time: timestamp.Timestamp,
  )
}

fn stop_decoder() -> decode.Decoder(Stop) {
  use name <- decode.field("name", decode.string)
  use stop_url <- decode.field("stop_url", decode.string)
  use is_highlighted <- decode.field("is_highlighted", decode.bool)
  use transfers <- decode.field(
    "transfers",
    decode.list(route_bullet.decoder()),
  )
  use time <- decode.field("time", timestamp_json.decoder())
  decode.success(Stop(name:, stop_url:, is_highlighted:, transfers:, time:))
}

fn stop_to_json(stop: Stop) -> json.Json {
  let Stop(name:, stop_url:, is_highlighted:, transfers:, time:) = stop
  json.object([
    #("name", json.string(name)),
    #("stop_url", json.string(stop_url)),
    #("is_highlighted", json.bool(is_highlighted)),
    #("transfers", json.array(transfers, route_bullet.to_json)),
    #("time", timestamp_json.to_json(time)),
  ])
}

pub fn stop_li(stop: Stop) -> Element(msg) {
  let Stop(name:, stop_url:, is_highlighted:, transfers:, time:) = stop
  let transfers = list.map(transfers, route_bullet)

  html.li([], [
    html.a(
      [
        attribute.href(stop_url),
        attribute.classes([#("highlight", is_highlighted)]),
      ],
      [
        html.span([], [html.text(name), ..transfers]),
        html.span([], [
          html.text(time |> util.min_from_now |> int.to_string <> "min"),
        ]),
      ],
    ),
  ])
}
