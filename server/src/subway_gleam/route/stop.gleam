import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/pair
import gleam/result
import gleam/set
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import gleam/uri
import lustre/attribute
import lustre/element
import lustre/element/html
import shared/route/stop
import subway_gleam/component
import subway_gleam/internal/util
import subway_gleam/lustre_middleware.{Document, try_lustre_res}
import subway_gleam/rt
import subway_gleam/rt/rich_text
import subway_gleam/st
import subway_gleam/state
import subway_gleam/state/gtfs_actor
import wisp

pub fn stop(
  req: wisp.Request,
  state: state.State,
  stop_id: String,
) -> wisp.Response {
  use req <- try_lustre_res(req)

  // TODO: make this a function?
  let highlighted_train =
    req.query
    |> option.to_result(Nil)
    |> result.try(uri.parse_query)
    |> result.unwrap(or: [])
    |> list.key_find("train_id")
    |> result.try(uri.percent_decode)
    |> result.map(rt.TrainId)

  use stop_id <- result.try(
    st.parse_stop_id_no_direction(stop_id)
    |> result.replace_error(error_invalid_stop(stop_id)),
  )
  use stop <- result.try(
    state.schedule.stops
    |> dict.get(#(stop_id, option.None))
    |> result.replace_error(error_unknown_stop(stop_id)),
  )

  let routes =
    state.schedule.stop_routes
    |> dict.get(stop_id)
    |> result.unwrap(or: set.new())
  let transfers =
    state.schedule.transfers
    |> dict.get(stop.id)
    |> result.unwrap(or: set.new())
    |> set.map(fn(transfer) {
      let routes =
        state.schedule.stop_routes
        |> dict.get(transfer.destination)
        |> result.unwrap(set.new())
        |> set.map(fn(route_id) {
          let assert Ok(route) = state.schedule.routes |> dict.get(route_id)
          route
        })
        |> set.to_list
        |> list.sort(st.route_compare)
        // TODO: also need to sort each group in sort order
        |> list.map(component.route_bullet)

      let st.StopId(id) = transfer.destination
      html.a(
        [attribute.class("bullet-group"), attribute.href("/stop/" <> id)],
        routes,
      )
    })
    |> set.to_list

  let gtfs_actor.Data(current: gtfs, last_updated:) = state.fetch_gtfs(state)

  let alerts = filter_alerts(gtfs, routes, stop_id)
  let alert_summary =
    alerts
    |> list.map(fn(alert) { option.unwrap(alert.alert_type, or: "Alert") })
    |> list.unique
    |> string.join(with: ", ")
  let num_alerts = list.length(alerts) |> int.to_string
  let alert_summary = num_alerts <> " Alerts: " <> alert_summary

  let #(uptown, downtown) =
    gtfs.arrivals
    |> dict.get(stop_id)
    |> result.unwrap(or: [])
    |> list.sort(by: fn(a, b) {
      timestamp.compare(a.time, b.time) |> order.negate
    })
    |> list.filter(keeping: fn(a) {
      // Strip out times that are in the past
      case timestamp.compare(a.time, util.current_time()) {
        order.Eq | order.Gt -> True
        order.Lt -> False
      }
    })
    |> list.fold(from: #([], []), with: fn(acc, update) {
      let #(uptown_acc, downtown_acc) = acc
      let li = arrival_li(update, state.schedule, gtfs, highlighted_train)
      case update.direction {
        st.North -> #([li, ..uptown_acc], downtown_acc)
        st.South -> #(uptown_acc, [li, ..downtown_acc])
      }
    })
  // let uptown = uptown |> list.take(from: _, up_to: 10)
  // let downtown = downtown |> list.take(from: _, up_to: 10)

  let model =
    stop.Model(
      name: stop.name,
      last_updated:,
      transfers:,
      alert_summary:,
      uptown:,
      downtown:,
    )

  let head = [html.title([], "Trains at " <> stop.name)]
  let body = [
    html.div([attribute.id("app")], [
      stop.view(model),
    ]),
  ]

  Ok(#(Document(head:, body:), wisp.response(200)))
}

fn filter_alerts(
  gtfs: rt.Data,
  routes: set.Set(st.Route),
  stop_id: st.StopId,
) -> List(rt.Alert) {
  let current_time = util.current_time()
  let alerts =
    gtfs.alerts
    |> list.filter(fn(alert) {
      use period <- list.any(in: alert.active_periods)

      let after_start = case period.start {
        option.Some(start) -> {
          let start =
            util.timestamp_subtract(start, alert.display_before_active)
          timestamp.compare(start, current_time) != order.Gt
        }
        option.None -> True
      }
      let before_end = case period.end {
        option.Some(end) -> timestamp.compare(current_time, end) != order.Gt
        option.None -> True
      }

      after_start && before_end
    })
    |> list.filter(fn(alert) {
      use target <- list.any(in: alert.targets)

      let matches_route_id =
        target.route_id
        |> option.to_result(Nil)
        |> result.try(fn(id) { st.parse_route(id) |> result.replace_error(Nil) })
        |> result.map(set.contains(_, in: routes))
        |> result.unwrap(or: False)

      let matches_stop =
        target.stop_id
        |> option.to_result(Nil)
        |> result.try(st.parse_stop_id)
        |> result.map(pair.first)
        |> result.map(fn(target_stop_id) { target_stop_id == stop_id })
        |> result.unwrap(or: False)

      matches_route_id || matches_stop
    })
  alerts
}

pub fn alerts(
  req: wisp.Request,
  state: state.State,
  stop_id: String,
  route_id: option.Option(String),
) -> wisp.Response {
  use _req <- try_lustre_res(req)

  use stop_id <- result.try(
    st.parse_stop_id_no_direction(stop_id)
    |> result.replace_error(error_invalid_stop(stop_id)),
  )
  use stop <- result.try(
    state.schedule.stops
    |> dict.get(#(stop_id, option.None))
    |> result.replace_error(error_unknown_stop(stop_id)),
  )

  let all_routes =
    state.schedule.stop_routes
    |> dict.get(stop_id)
    |> result.unwrap(or: set.new())
  let route =
    route_id |> option.to_result(Nil) |> result.try(st.route_id_long_to_route)
  let routes = case route {
    Ok(route) -> set.new() |> set.insert(route)
    Error(Nil) -> all_routes
  }

  let gtfs_actor.Data(current: gtfs, last_updated:) = state.fetch_gtfs(state)

  let route_selections = {
    let bullets =
      all_routes
      |> set.map(fn(route) {
        let route_id = st.route_to_long_id(route)
        let route = st.route_data(in: state.schedule, for: route)
        html.a(
          [attribute.class("bullet-group"), attribute.href("../" <> route_id)],
          [component.route_bullet(route)],
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

  let alerts = filter_alerts(gtfs, routes, stop_id)
  let alerts = list.map(alerts, alert_detail)
  let alerts_list = case list.is_empty(alerts) {
    True -> html.p([], [html.text("Woah...no alerts for this line!")])
    False -> html.ul([attribute.class("alerts")], alerts)
  }

  let head = [html.title([], "Trains at " <> stop.name)]
  let body = [
    html.h1([], [
      html.text(stop.name),
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
    route_selections,
    html.main([], [
      alerts_list,
    ]),
  ]

  Ok(#(Document(head:, body:), wisp.response(200)))
}

fn alert_detail(alert: rt.Alert) -> element.Element(msg) {
  let rt.Alert(
    id:,
    active_periods: _,
    targets: _,
    header:,
    description:,
    created: _,
    updated:,
    alert_type:,
    station_alternatives:,
    display_before_active: _,
    human_readable_active_period:,
    clone_id:,
  ) = alert

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
      let str = updated |> util.min_from_now |> int.negate |> int.to_string
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
    html.summary([], [alert_type]),
    header,
    active_period_or_last_updated,
    html.hr([]),
    description,
    alert_id,
  ])
}

fn error_invalid_stop(
  stop_id: String,
) -> #(lustre_middleware.LustreRes(a), wisp.Response) {
  #(
    Document(head: [html.title([], "Error: Invalid stop")], body: [
      html.p([], [html.text("Error: Invalid stop id: " <> stop_id)]),
    ]),
    wisp.response(400),
  )
}

fn error_unknown_stop(
  stop_id: st.StopId,
) -> #(lustre_middleware.LustreRes(b), wisp.Response) {
  #(
    Document(head: [html.title([], "Error: Unknown stop")], body: [
      html.p([], [
        html.text(
          "Error: Could not find stop "
          <> st.stop_id_to_string(stop_id, option.None),
        ),
      ]),
    ]),
    wisp.response(404),
  )
}

fn arrival_li(
  update: rt.TrainStopping,
  schedule: st.Schedule,
  gtfs: rt.Data,
  highlighted_train: Result(rt.TrainId, Nil),
) -> element.Element(msg) {
  let rt.TrainStopping(trip:, time:, stop_id: _, direction: _) = update

  let headsign = {
    use shape_id <- result.try(st.parse_shape_id(from: trip.trip_id))
    let headsign =
      schedule.trips.headsigns
      |> dict.get(shape_id)
      |> result.lazy_or(fn() {
        dict.get(gtfs.final_stops, shape_id)
        |> result.map(pair.map_second(_, option.Some))
        |> result.try(dict.get(schedule.stops, _))
        |> result.map(fn(stop) { stop.name })
        // TODO: maybe don't want to always have a value?
        |> result.unwrap(or: "<Unknown stop>")
        |> Ok
      })
    use headsign <- result.map(headsign)
    html.span([], [html.text(headsign)])
  }

  let train_id_percent_encode =
    update.trip.nyct.train_id
    |> option.map(uri.percent_encode)
    |> option.map(
      // uri.percent_encode doesn't encode pluses
      string.replace(_, each: "+", with: "%2B"),
    )
  let train_url =
    train_id_percent_encode
    |> option.map(fn(id) {
      let query =
        uri.query_to_string([
          #(
            "stop_id",
            st.stop_id_to_string(update.stop_id, option.Some(update.direction)),
          ),
        ])
      "/train/" <> id <> "?" <> query
    })
    |> option.unwrap(or: "")

  let train_id = update.trip.nyct.train_id |> option.map(rt.TrainId)
  let is_highlighted = case train_id, highlighted_train {
    option.Some(train_id), Ok(highlight) -> train_id == highlight
    _, _ -> False
  }

  // TODO: what to do here?? try to get rid of assert.
  let assert Ok(route_id) = st.parse_route(trip.route_id)
  let route = schedule |> st.route_data(for: route_id)

  html.li([], [
    html.a(
      [
        attribute.href(train_url),
        attribute.classes([#("highlight", is_highlighted)]),
      ],
      [
        component.route_bullet(route),
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
