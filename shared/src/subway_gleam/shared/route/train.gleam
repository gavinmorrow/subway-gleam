import gleam/bool
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/time/duration
import gleam/time/timestamp
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed

import subway_gleam/gtfs/st
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
    highlighted_stop: option.Option(st.StopId),
    event_source: LiveStatus,
  )
}

pub fn view(model: Model) -> Element(msg) {
  let Model(last_updated:, stops:, highlighted_stop:, event_source:) = model

  let stops = list.filter_map(stops, stop_li(_, highlighted_stop))

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
    keyed.ol([attribute.class("stops-list")], stops),
  ])
}

pub fn model_decoder() -> decode.Decoder(Model) {
  use last_updated <- decode.field("last_updated", timestamp_json.decoder())
  use stops <- decode.field("stops", decode.list(stop_decoder()))
  use highlighted_stop <- decode.field(
    "highlighted_stop",
    decode.optional(decode.string |> decode.map(st.StopId)),
  )

  decode.success(Model(
    last_updated:,
    stops:,
    highlighted_stop:,
    event_source: live_status.Unavailable,
  ))
}

pub fn model_to_json(model: Model) -> json.Json {
  let Model(last_updated:, stops:, highlighted_stop:, event_source: _) = model

  json.object([
    #("last_updated", timestamp_json.to_json(last_updated)),
    #("stops", json.array(stops, stop_to_json)),
    #(
      "highlighted_stop",
      json.nullable(from: highlighted_stop, of: fn(stop_id) {
        let st.StopId(str) = stop_id
        json.string(str)
      }),
    ),
  ])
}

pub type Stop {
  Stop(
    id: st.StopId,
    name: String,
    stop_url: String,
    transfers: List(RouteBullet),
    time: timestamp.Timestamp,
  )
}

fn stop_decoder() -> decode.Decoder(Stop) {
  use id <- decode.field("id", decode.string |> decode.map(st.StopId))
  use name <- decode.field("name", decode.string)
  use stop_url <- decode.field("stop_url", decode.string)
  use transfers <- decode.field(
    "transfers",
    decode.list(route_bullet.decoder()),
  )
  use time <- decode.field("time", timestamp_json.decoder())

  decode.success(Stop(id:, name:, stop_url:, transfers:, time:))
}

fn stop_to_json(stop: Stop) -> json.Json {
  let Stop(id:, name:, stop_url:, transfers:, time:) = stop
  let st.StopId(id) = id

  json.object([
    #("id", json.string(id)),
    #("name", json.string(name)),
    #("stop_url", json.string(stop_url)),
    #("transfers", json.array(transfers, route_bullet.to_json)),
    #("time", timestamp_json.to_json(time)),
  ])
}

pub fn stop_li(
  stop: Stop,
  highlighted_stop: option.Option(st.StopId),
) -> Result(#(String, Element(msg)), Nil) {
  let Stop(id:, name:, stop_url:, transfers:, time:) = stop

  let dt = util.min_from_now(time)
  use <- bool.guard(when: dt < 0, return: Error(Nil))

  let transfers = list.map(transfers, route_bullet)
  let is_highlighted = option.Some(id) == highlighted_stop

  let st.StopId(id) = id
  #(
    id,
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
    ]),
  )
  |> Ok
}
