import gleam/http/response
import gleam/list
import gleam/option
import gleam/order
import gleam/pair
import gleam/result
import gleam/string
import gleam/time/timestamp
import lustre/attribute
import lustre/element
import lustre/element/html
import subway_gleam/st
import wisp

import subway_gleam/rt
import subway_gleam/state

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

pub fn stop(
  req: wisp.Request,
  state: state.State,
  stop_id: String,
) -> wisp.Response {
  use _req <- lustre_res(req)

  let data = {
    use stop_id <- result.try(
      st.parse_stop_id(stop_id)
      |> result.replace_error(rt.InvalidStopId(stop_id)),
    )
    use stop <- result.try(
      state.schedule.stops
      |> list.find(fn(stop) { stop.id == stop_id })
      |> result.replace_error(rt.UnknownStop(stop_id)),
    )

    // TODO: don't parse new gtfs every request
    let feed = rt.gtfs_rt_feed_from_stop_id(stop_id)
    use gtfs <- result.map(rt.fetch_gtfs(feed:))

    #(
      stop,
      gtfs
        |> rt.trains_stopping(at: stop_id)
        |> list.sort(by: fn(a, b) {
          timestamp.compare(a.time, b.time) |> order.negate
        })
        |> list.fold(from: #([], []), with: fn(acc, update) {
          let #(uptown_acc, downtown_acc) = acc
          let text = rt.describe_arrival(update)
          case update.stop_id.direction {
            // Treat no direction as uptown
            // TODO: figure out what should be done here. is it even be possible?
            option.Some(st.North) | option.None -> #(
              [text, ..uptown_acc],
              downtown_acc,
            )
            option.Some(st.South) -> #(uptown_acc, [text, ..downtown_acc])
          }
        })
        |> pair.map_first(list.take(_, 10))
        |> pair.map_second(list.take(_, 10)),
    )
  }

  let body = case data {
    Ok(#(stop, #(uptown, downtown))) ->
      element.fragment([
        html.link([
          attribute.rel("stylesheet"),
          attribute.href("/static/style.css"),
        ]),
        html.h1([], [
          html.text(stop.name),
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
