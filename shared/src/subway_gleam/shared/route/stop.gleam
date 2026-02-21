import gleam/bool
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
import lustre/element/keyed

import subway_gleam/gtfs/rt
import subway_gleam/gtfs/st
import subway_gleam/shared/component/arrival_time.{arrival_time}
import subway_gleam/shared/component/route_bullet.{
  type RouteBullet, route_bullet,
}
import subway_gleam/shared/util
import subway_gleam/shared/util/live_status.{type LiveStatus}
import subway_gleam/shared/util/stop_id_json
import subway_gleam/shared/util/time.{type Time}
import subway_gleam/shared/util/timestamp_json

pub type Model {
  Model(
    name: String,
    last_updated: timestamp.Timestamp,
    transfers: List(Transfer),
    alerted_routes: List(RouteBullet),
    alert_summary: String,
    uptown: List(Arrival),
    downtown: List(Arrival),
    highlighted_train: option.Option(rt.TrainId),
    event_source: LiveStatus,
    cur_time: Time,
  )
}

pub fn view(model: Model) -> Element(msg) {
  let Model(
    name:,
    last_updated:,
    transfers:,
    alerted_routes:,
    alert_summary:,
    uptown:,
    downtown:,
    highlighted_train:,
    event_source:,
    cur_time:,
  ) = model

  let alerted_routes =
    element.fragment(list.map(alerted_routes, with: route_bullet))

  let transfers =
    list.map(transfers, fn(transfer) {
      let routes = list.map(transfer.routes, route_bullet.route_bullet)
      let st.StopId(id) = transfer.destination

      html.a(
        [attribute.class("bullet-group"), attribute.href("/stop/" <> id)],
        routes,
      )
    })
  let uptown =
    list.filter_map(uptown, arrival_li(
      for: _,
      highlighting: highlighted_train,
      at: cur_time,
    ))
  let downtown =
    list.filter_map(downtown, arrival_li(
      for: _,
      highlighting: highlighted_train,
      at: cur_time,
    ))

  let live_status = case event_source {
    live_status.Connecting(_) -> element.text("Conecting...")
    live_status.Live(_) -> element.text("Live!")
    live_status.Unavailable -> element.text("Live not available.")
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
      html.a([attribute.href("./alerts")], [
        alerted_routes,
        html.text(alert_summary),
      ]),
    ]),
    html.h2([], [html.text("Uptown")]),
    keyed.ul([attribute.class("arrival-list")], uptown),
    html.h2([], [html.text("Downtown")]),
    keyed.ul([attribute.class("arrival-list")], downtown),
  ])
}

pub fn model_decoder() -> decode.Decoder(Model) {
  use name <- decode.field("name", decode.string)
  use last_updated <- decode.field("last_updated", timestamp_json.decoder())
  use transfers <- decode.field("transfers", decode.list(transfer_decoder()))
  use alerted_routes <- decode.field(
    "alerted_routes",
    decode.list(route_bullet.decoder()),
  )
  use alert_summary <- decode.field("alert_summary", decode.string)
  use highlighted_train <- decode.field(
    "highlighted_train",
    decode.optional(decode.string |> decode.map(rt.TrainId)),
  )
  use uptown <- decode.field("uptown", decode.list(arrival_decoder()))
  use downtown <- decode.field("downtown", decode.list(arrival_decoder()))
  use cur_time <- decode.field("cur_time", time.decoder())

  decode.success(Model(
    name:,
    last_updated:,
    transfers:,
    alerted_routes:,
    alert_summary:,
    uptown:,
    downtown:,
    highlighted_train:,
    event_source: live_status.Unavailable,
    cur_time:,
  ))
}

pub fn model_to_json(model: Model) -> json.Json {
  let Model(
    name:,
    last_updated:,
    transfers:,
    alerted_routes:,
    alert_summary:,
    uptown:,
    downtown:,
    highlighted_train:,
    // Can't encode an EventSource
    event_source: _,
    cur_time:,
  ) = model

  json.object([
    #("name", json.string(name)),
    #("last_updated", timestamp_json.to_json(last_updated)),
    #("transfers", json.array(transfers, transfer_to_json)),
    #("alerted_routes", json.array(alerted_routes, route_bullet.to_json)),
    #("alert_summary", json.string(alert_summary)),
    #(
      "highlighted_train",
      json.nullable(from: highlighted_train, of: fn(id) {
        json.string(rt.train_id_to_string(id))
      }),
    ),
    #("uptown", json.array(uptown, arrival_to_json)),
    #("downtown", json.array(downtown, arrival_to_json)),
    #("cur_time", time.to_json(cur_time)),
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
    train_id: option.Option(rt.TrainId),
    train_url: String,
    route: RouteBullet,
    headsign: Result(String, Nil),
    time: timestamp.Timestamp,
  )
}

fn arrival_decoder() -> decode.Decoder(Arrival) {
  use train_id <- decode.field(
    "train_id",
    decode.optional(decode.string |> decode.map(rt.TrainId)),
  )
  use train_url <- decode.field("train_url", decode.string)
  use route <- decode.field("route", route_bullet.decoder())
  use headsign <- decode.field(
    "headsign",
    decode.optional(decode.string) |> decode.map(option.to_result(_, Nil)),
  )
  use time <- decode.field("time", timestamp_json.decoder())

  decode.success(Arrival(train_id:, train_url:, route:, headsign:, time:))
}

fn arrival_to_json(arrival: Arrival) -> json.Json {
  let Arrival(train_id:, train_url:, route:, headsign:, time:) = arrival

  json.object([
    #(
      "train_id",
      json.nullable(from: train_id, of: fn(train_id) {
        json.string(rt.train_id_to_string(train_id))
      }),
    ),
    #("train_url", json.string(train_url)),
    #("route", route_bullet.to_json(route)),
    #("headsign", json.nullable(option.from_result(headsign), of: json.string)),
    #("time", timestamp_json.to_json(time)),
  ])
}

fn arrival_li(
  for arrival: Arrival,
  highlighting highlighted_train: option.Option(rt.TrainId),
  at cur_time: Time,
) -> Result(#(String, Element(msg)), Nil) {
  let Arrival(train_id:, train_url:, route:, headsign:, time:) = arrival

  // Filter to not show departed trains
  let dt = time |> util.min_from(cur_time.timestamp)
  use <- bool.guard(when: dt < 0, return: Error(Nil))

  let headsign =
    result.map(headsign, fn(headsign) { html.span([], [html.text(headsign)]) })

  let is_highlighted = train_id == highlighted_train

  #(
    arrival.train_id
      |> option.map(rt.train_id_to_string)
      // TODO: is this the right option here
      |> option.unwrap(int.random(1024) |> int.to_string),
    html.li([], [
      html.a(
        [
          attribute.href(train_url),
          attribute.classes([#("highlight", is_highlighted)]),
        ],
        [
          route_bullet(route),
          headsign |> result.unwrap(or: element.none()),
          arrival_time(arriving_at: time, cur_time:),
        ],
      ),
    ]),
  )
  |> Ok
}
