import lustre/element/html
import subway_gleam/route/stop
import subway_gleam/route/train
import wisp

import subway_gleam/lustre_middleware.{Body, lustre_res}

pub fn index(req: wisp.Request) -> wisp.Response {
  use _req <- lustre_res(req)

  let body = [html.p([], [html.text("subways! yay!")])]
  let res = wisp.response(200)

  #(Body(body:), res)
}

pub fn not_found(req: wisp.Request) -> wisp.Response {
  use _req <- lustre_res(req)

  let body = [html.p([], [html.text("404 not found :[")])]
  let res = wisp.response(404)

  #(Body(body:), res)
}

pub const stop = stop.stop

pub const train = train.train
