import gleam/http/response
import gleam/list
import gleam/order
import gleam/pair
import gleam/result
import gleam/string
import gleam/time/timestamp
import lustre/element
import lustre/element/html
import wisp

import subway_gleam/rt

pub fn lustre_res(
  req: wisp.Request,
  handle_request: fn(wisp.Request) -> #(element.Element(msg), wisp.Response),
) -> wisp.Response {
  let #(html, res) = handle_request(req)

  response.set_body(
    res,
    html
      |> element.to_document_string
      |> wisp.Text,
  )
}

pub fn middleware(
  req: wisp.Request,
  handle_request: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  use <- wisp.rescue_crashes
  use req <- wisp.csrf_known_header_protection(req)

  handle_request(req)
}

pub fn index(req: wisp.Request) -> wisp.Response {
  use _req <- lustre_res(req)

  let body = html.p([], [html.text("subways! yay!")])
  let res = wisp.response(200)

  #(body, res)
}

pub fn not_found(req: wisp.Request) -> wisp.Response {
  use _req <- lustre_res(req)

  let body = html.p([], [html.text("404 not found :[")])
  let res = wisp.response(404)

  #(body, res)
}

pub fn stop(req: wisp.Request, stop_id: String) -> wisp.Response {
  use _req <- lustre_res(req)

  let stop_id = rt.parse_stop_id(stop_id)

  let data = {
    // TODO: don't parse new gtfs every request
    use feed <- result.try(
      rt.gtfs_rt_feed_from_stop_id(stop_id)
      |> result.replace_error(rt.InvalidStopId(stop_id)),
    )
    use gtfs <- result.map(rt.fetch_gtfs(feed:))

    gtfs
    |> rt.trains_stopping(at: stop_id)
    |> list.sort(by: fn(a, b) {
      timestamp.compare(a.time, b.time) |> order.negate
    })
    |> list.fold(from: #([], []), with: fn(acc, update) {
      let #(uptown_acc, downtown_acc) = acc
      let text = rt.describe_arrival(update)
      case update.stop_id |> rt.stop_id_string |> string.ends_with("N") {
        True -> #([text, ..uptown_acc], downtown_acc)
        False -> #(uptown_acc, [text, ..downtown_acc])
      }
    })
    |> pair.map_first(list.take(_, 10))
    |> pair.map_second(list.take(_, 10))
  }

  let body = case data {
    Ok(#(uptown, downtown)) ->
      element.fragment([
        html.h1([], [
          html.text("Stopping at stop #" <> stop_id |> rt.stop_id_string <> ":"),
        ]),
        html.h2([], [html.text("Uptown")]),
        html.ul(
          [],
          uptown
            |> list.map(html.text)
            |> list.map(fn(text) { html.li([], [text]) }),
        ),
        html.h2([], [html.text("Downtown")]),
        html.ul(
          [],
          downtown
            |> list.map(html.text)
            |> list.map(fn(text) { html.li([], [text]) }),
        ),
      ])
    Error(err) -> html.p([], [html.text("Error: " <> string.inspect(err))])
  }

  #(body, wisp.response(200))
}
