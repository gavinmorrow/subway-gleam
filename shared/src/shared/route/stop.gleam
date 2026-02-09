import gleam/int
import gleam/list
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

import shared/component/route_bullet.{type RouteBullet, route_bullet}
import shared/util
import subway_gleam/gtfs/st

// TODO: remove all Elements from model
pub type Model(msg) {
  Model(
    name: String,
    last_updated: timestamp.Timestamp,
    transfers: List(Transfer),
    alert_summary: String,
    uptown: List(Arrival),
    downtown: List(Arrival),
  )
}

pub fn view(model: Model(msg)) -> Element(msg) {
  let Model(
    name:,
    last_updated:,
    transfers:,
    alert_summary:,
    uptown:,
    downtown:,
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

  html.div([], [
    html.h1([], [
      html.text(name),
    ]),
    html.aside([], [
      html.text(
        "Last updated "
        <> { last_updated |> timestamp.to_rfc3339(duration.hours(-4)) },
      ),
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

pub type Transfer {
  Transfer(destination: st.StopId, routes: List(route_bullet.RouteBullet))
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
