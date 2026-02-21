import gleam/list
import gleam/option
import gleam/set
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

import subway_gleam/gtfs/rt/rich_text.{type RichText}
import subway_gleam/gtfs/st
import subway_gleam/shared/component/last_updated
import subway_gleam/shared/component/rich_text as rich_text_component
import subway_gleam/shared/component/route_bullet.{route_bullet}
import subway_gleam/shared/util/time.{type Time}

pub type Model {
  Model(
    stop_name: String,
    last_updated: Time,
    // TODO: don't actually need *all* routes. trim them down server-side
    all_routes: set.Set(st.RouteData),
    alerts: List(Alert),
    cur_time: Time,
  )
}

pub type Alert {
  Alert(
    id: String,
    routes: set.Set(st.RouteData),
    header: RichText,
    description: option.Option(RichText),
    updated: option.Option(Time),
    alert_type: option.Option(String),
    human_readable_active_period: option.Option(RichText),
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

  let alerts_list = list.map(alerts, alert_detail(_, cur_time))
  let alerts_list = case list.is_empty(alerts) {
    True -> html.p([], [html.text("Woah...no alerts for this line!")])
    False -> html.ul([attribute.class("alerts")], alerts_list)
  }

  element.fragment([
    html.h1([], [
      html.text(stop_name),
    ]),
    html.aside([], [last_updated.last_updated(at: last_updated, cur_time:)]),
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

fn alert_detail(alert: Alert, cur_time: Time) -> element.Element(msg) {
  let Alert(
    id:,
    routes:,
    header:,
    description:,
    updated:,
    alert_type:,
    human_readable_active_period:,
  ) = alert

  let alerted_routes =
    // element.fragment({
    //   use route <- list.filter_map(rt.routes_in_alert(alert) |> set.to_list)
    //   use data <- result.map(dict.get(route_datas, route))
    //   data |> route_bullet.from_route_data |> route_bullet
    // })
    element.fragment({
      use route <- list.map(routes |> set.to_list)
      route |> route_bullet.from_route_data |> route_bullet
    })

  let alert_type = alert_type |> option.unwrap(or: "Alert") |> html.text

  let header = rich_text_component.as_html(header)
  let description =
    description
    |> option.map(rich_text_component.as_html)
    |> option.unwrap(or: element.none())

  let human_readable_active_period =
    human_readable_active_period |> option.map(rich_text_component.as_html)
  let last_updated =
    option.map(updated, last_updated.last_updated(at: _, cur_time:))
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
