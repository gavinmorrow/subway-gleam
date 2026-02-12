import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import gleam/time/duration
import gleam/time/timestamp
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

import subway_gleam/gtfs/rt
import subway_gleam/gtfs/st
import subway_gleam/shared/component/rich_text
import subway_gleam/shared/component/route_bullet.{route_bullet}
import subway_gleam/shared/util

pub type Model {
  Model(
    stop_name: String,
    last_updated: timestamp.Timestamp,
    all_routes: set.Set(st.RouteData),
    alerts: List(rt.Alert),
    cur_time: timestamp.Timestamp,
  )
}

pub fn view(model: Model) -> Element(msg) {
  let Model(stop_name:, last_updated:, all_routes:, alerts:, cur_time:) = model
  let route_selection = {
    let bullets =
      all_routes
      |> set.map(fn(route) {
        let route_id = st.route_to_long_id(route.id)
        let bullet = route_bullet.from_route_data(route)
        html.a(
          [attribute.class("bullet-group"), attribute.href("../" <> route_id)],
          [route_bullet(bullet)],
        )
      })
      |> set.to_list
    html.aside([], [
      html.a(
        [
          attribute.class("bullet-group"),
          attribute.href("../all"),
        ],
        [html.text("All")],
      ),
      ..bullets
    ])
  }

  let route_datas =
    set.fold(over: all_routes, from: dict.new(), with: fn(acc, route) {
      dict.insert(route, for: route.id, into: acc)
    })
  let alerts_list = list.map(alerts, alert_detail(_, cur_time, route_datas))
  let alerts_list = case list.is_empty(alerts) {
    True -> html.p([], [html.text("Woah...no alerts for this line!")])
    False -> html.ul([attribute.class("alerts")], alerts_list)
  }

  element.fragment([
    html.h1([], [
      html.text(stop_name),
    ]),
    html.aside([], [
      html.text(
        "Last updated "
        <> { last_updated |> timestamp.to_rfc3339(duration.hours(-4)) },
      ),
    ]),
    html.nav([], [
      html.a([attribute.href("../../")], [html.text("Back to arrivals")]),
    ]),
    route_selection,
    html.main([], [alerts_list]),
  ])
}

pub type AlertDetail {
  AlertDetail(alert_type: String)
}

fn alert_detail(
  alert: rt.Alert,
  cur_time: timestamp.Timestamp,
  route_datas: dict.Dict(st.Route, st.RouteData),
) -> element.Element(msg) {
  let rt.Alert(
    id:,
    active_periods: _,
    targets: _,
    header:,
    description:,
    created: _,
    updated:,
    alert_type:,
    station_alternatives: _,
    display_before_active: _,
    human_readable_active_period:,
    clone_id: _,
  ) = alert

  let alerted_routes =
    element.fragment({
      use route <- list.filter_map(rt.routes_in_alert(alert) |> set.to_list)
      use data <- result.map(dict.get(route_datas, route))
      data |> route_bullet.from_route_data |> route_bullet
    })

  let alert_type = alert_type |> option.unwrap(or: "Alert") |> html.text

  let header = rich_text.as_html(header)
  let description =
    description
    |> option.map(rich_text.as_html)
    |> option.unwrap(or: element.none())

  let human_readable_active_period =
    human_readable_active_period |> option.map(rich_text.as_html)
  let last_updated =
    option.map(updated, fn(updated) {
      let str =
        updated |> util.min_from(cur_time) |> int.negate |> int.to_string
      html.text("Last updated: " <> str <> "min ago")
    })
  let active_period_or_last_updated =
    option.or(human_readable_active_period, last_updated)
    |> option.map(fn(elem) {
      html.div([attribute.class("alert-last-updated")], [elem])
    })
    |> option.unwrap(or: element.none())

  let alert_id = html.p([attribute.class("alert-id")], [html.text(id)])

  html.details([attribute.class("alert")], [
    html.summary([], [alerted_routes, alert_type]),
    header,
    active_period_or_last_updated,
    html.hr([]),
    description,
    alert_id,
  ])
}
