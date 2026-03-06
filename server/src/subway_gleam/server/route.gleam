import lustre/attribute
import lustre/element/html
import wisp

import subway_gleam/server/lustre_middleware.{Body, lustre_res}
import subway_gleam/server/route/line
import subway_gleam/server/route/stop
import subway_gleam/server/route/stop/alerts
import subway_gleam/server/route/stops
import subway_gleam/server/route/train
import subway_gleam/shared/component/navbar.{navbar}

pub fn index(req: wisp.Request) -> wisp.Response {
  use _req <- lustre_res(req)

  let body = [
    html.p([], [html.text("subways! yay!")]),
    html.a([attribute.href("/stops")], [html.text("stops nearby")]),
    navbar(),
  ]
  let res = wisp.response(200)

  #(Body(body:), res)
}

pub fn not_found(req: wisp.Request) -> wisp.Response {
  use _req <- lustre_res(req)

  let body = [
    html.p([], [
      html.text("404 not found :["),
    ]),
    navbar(),
  ]
  let res = wisp.response(404)

  #(Body(body:), res)
}

pub fn map(req: wisp.Request) -> wisp.Response {
  use _req <- lustre_res(req)

  let body = [html.p([], [html.text("Coming soon!")]), navbar()]
  let res = wisp.response(200)

  #(Body(body:), res)
}

pub const stops = stops.stops

pub const stop = stop.stop

pub const stop_alerts = alerts.alerts

pub const train = train.train

pub const line = line.line
