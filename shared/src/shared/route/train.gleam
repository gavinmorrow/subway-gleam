import gleam/int
import gleam/list
import gleam/time/duration
import gleam/time/timestamp
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import shared/component/route_bullet.{type RouteBullet, route_bullet}
import shared/util

pub type Model {
  Model(last_updated: timestamp.Timestamp, stops: List(Stop))
}

pub fn view(model: Model) -> Element(msg) {
  let Model(last_updated:, stops:) = model
  let stops = list.map(stops, stop_li)

  html.div([], [
    html.p([], [
      html.text(
        "Last updated "
        <> last_updated |> timestamp.to_rfc3339(duration.hours(-4)),
      ),
    ]),
    html.ol([attribute.class("stops-list")], stops),
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
