import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre_event_source

import subway_gleam/gtfs/st
import subway_gleam/shared/component/route_bullet.{
  type RouteBullet, route_bullet,
}
import subway_gleam/shared/util
import subway_gleam/shared/util/stop_id_json
import subway_gleam/shared/util/timestamp_json

pub type Model {
  Model(
    name: String,
    last_updated: timestamp.Timestamp,
    transfers: List(Transfer),
    alert_summary: String,
    uptown: List(Arrival),
    downtown: List(Arrival),
    event_source: LiveStatus,
  )
}

pub fn view(model: Model) -> Element(msg) {
  let Model(
    name:,
    last_updated:,
    transfers:,
    alert_summary:,
    uptown:,
    downtown:,
    event_source:,
  ) = model

  let transfers =
    list.map(transfers, fn(transfer) {
      let routes = list.map(transfer.routes, route_bullet.route_bullet)
      let st.StopId(id) = transfer.destination

      html.a(
        [attribute.class("bullet-group"), attribute.href("/stop/" <> id)],
        routes,
      )
    })
  let uptown = list.map(uptown, arrival_li)
  let downtown = list.map(downtown, arrival_li)

  let live_status = case event_source {
    Connecting(_) -> element.text("Conecting...")
    Live(_) -> element.text("Live!")
    Unavailable -> element.text("Live not available.")
  }

  html.div([], [
    html.h1([], [
      html.text(name),
    ]),
    html.aside([], [
      html.text(
        "Last updated "
        <> { last_updated |> timestamp.to_rfc3339(duration.hours(-4)) },
      ),
      html.br([]),
      live_status,
    ]),
    html.aside([], [html.text("Transfer to:"), ..transfers]),
    html.aside([], [
      html.a([attribute.href("./alerts")], [html.text(alert_summary)]),
    ]),
    html.h2([], [html.text("Uptown")]),
    html.ul([attribute.class("arrival-list")], uptown),
    html.h2([], [html.text("Downtown")]),
    html.ul([attribute.class("arrival-list")], downtown),
  ])
}

pub fn model_decoder() -> decode.Decoder(Model) {
  use name <- decode.field("name", decode.string)
  use last_updated <- decode.field("last_updated", timestamp_json.decoder())
  use transfers <- decode.field("transfers", decode.list(transfer_decoder()))
  use alert_summary <- decode.field("alert_summary", decode.string)
  use uptown <- decode.field("uptown", decode.list(arrival_decoder()))
  use downtown <- decode.field("downtown", decode.list(arrival_decoder()))

  decode.success(Model(
    name:,
    last_updated:,
    transfers:,
    alert_summary:,
    uptown:,
    downtown:,
    event_source: Unavailable,
  ))
}

pub fn model_to_json(model: Model) -> json.Json {
  let Model(
    name:,
    last_updated:,
    transfers:,
    alert_summary:,
    uptown:,
    downtown:,
    // Can't encode an EventSource
    event_source: _,
  ) = model

  json.object([
    #("name", json.string(name)),
    #("last_updated", timestamp_json.to_json(last_updated)),
    #("transfers", json.array(transfers, transfer_to_json)),
    #("alert_summary", json.string(alert_summary)),
    #("uptown", json.array(uptown, arrival_to_json)),
    #("downtown", json.array(downtown, arrival_to_json)),
  ])
}

pub type Transfer {
  Transfer(destination: st.StopId, routes: List(route_bullet.RouteBullet))
}

fn transfer_decoder() -> decode.Decoder(Transfer) {
  use destination <- decode.field("destination", stop_id_json.decoder())
  use routes <- decode.field("routes", decode.list(route_bullet.decoder()))

  decode.success(Transfer(destination:, routes:))
}

fn transfer_to_json(transfer: Transfer) -> json.Json {
  let Transfer(destination:, routes:) = transfer

  json.object([
    #("destination", stop_id_json.to_json(destination)),
    #("routes", json.array(routes, route_bullet.to_json)),
  ])
}

pub type Arrival {
  Arrival(
    train_url: String,
    is_highlighted: Bool,
    route: RouteBullet,
    headsign: Result(String, Nil),
    time: timestamp.Timestamp,
  )
}

fn arrival_decoder() -> decode.Decoder(Arrival) {
  use train_url <- decode.field("train_url", decode.string)
  use is_highlighted <- decode.field("is_highlighted", decode.bool)
  use route <- decode.field("route", route_bullet.decoder())
  use headsign <- decode.field(
    "headsign",
    decode.optional(decode.string) |> decode.map(option.to_result(_, Nil)),
  )
  use time <- decode.field("time", timestamp_json.decoder())

  decode.success(Arrival(train_url:, is_highlighted:, route:, headsign:, time:))
}

fn arrival_to_json(arrival: Arrival) -> json.Json {
  let Arrival(train_url:, is_highlighted:, route:, headsign:, time:) = arrival

  json.object([
    #("train_url", json.string(train_url)),
    #("is_highlighted", json.bool(is_highlighted)),
    #("route", route_bullet.to_json(route)),
    #("headsign", json.nullable(option.from_result(headsign), of: json.string)),
    #("time", timestamp_json.to_json(time)),
  ])
}

fn arrival_li(arrival: Arrival) -> Element(msg) {
  let Arrival(train_url:, is_highlighted:, route:, headsign:, time:) = arrival
  let headsign =
    result.map(headsign, fn(headsign) { html.span([], [html.text(headsign)]) })

  html.li([], [
    html.a(
      [
        attribute.href(train_url),
        attribute.classes([#("highlight", is_highlighted)]),
      ],
      [
        route_bullet(route),
        headsign |> result.unwrap(or: element.none()),
        html.span([], [
          html.text(
            time
            |> util.min_from_now
            |> int.to_string
            <> "min",
          ),
        ]),
      ],
    ),
  ])
}

pub type LiveStatus {
  Connecting(lustre_event_source.EventSource)
  Live(lustre_event_source.EventSource)
  Unavailable
}

pub fn live_status(
  for event_source: lustre_event_source.EventSource,
) -> LiveStatus {
  let ready_state = lustre_event_source.ready_state(event_source)
  case ready_state {
    lustre_event_source.Connecting -> Connecting(event_source)
    lustre_event_source.Open -> Live(event_source)
    lustre_event_source.Closed -> Unavailable
  }
}
