import gleam/list
import gleam/time/duration
import gleam/time/timestamp
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

import shared/component/route_bullet
import subway_gleam/gtfs/st

// TODO: remove all Elements from model
pub type Model(msg) {
  Model(
    name: String,
    last_updated: timestamp.Timestamp,
    transfers: List(Transfer),
    alert_summary: String,
    uptown: List(Element(msg)),
    downtown: List(Element(msg)),
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
