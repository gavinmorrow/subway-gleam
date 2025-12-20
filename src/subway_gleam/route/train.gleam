import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/pair
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import gleam/uri
import lustre/attribute
import lustre/element
import lustre/element/html
import subway_gleam/internal/util
import subway_gleam/lustre_middleware.{Body, Document, try_lustre_res}
import subway_gleam/rt
import subway_gleam/st
import subway_gleam/state
import subway_gleam/state/gtfs_actor
import wisp

pub fn train(
  req: wisp.Request,
  state: state.State,
  train_id: String,
) -> wisp.Response {
  use req <- try_lustre_res(req)

  // TODO: make this a function?
  let highlighted_stop =
    req.query
    |> option.to_result(Nil)
    |> result.try(uri.parse_query)
    |> result.unwrap(or: [])
    |> list.key_find("stop_id")
    |> result.try(st.parse_stop_id)
    |> result.map(pair.first)

  let gtfs_actor.Data(current: gtfs, last_updated:) = state.fetch_gtfs(state)

  use train_id <- result.try(
    uri.percent_decode(train_id)
    |> result.replace_error(error_invalid_train_id_encoding()),
  )
  let train_id = rt.TrainId(train_id)

  let trip =
    dict.get(gtfs.trips, train_id)
    |> result.replace_error({
      let rt.TrainId(train_id) = train_id
      error_could_not_find_train(train_id)
    })
  use stops <- result.try(trip)

  let stops =
    list.filter_map(stops, fn(arrival) {
      let stop =
        state.schedule.stops
        |> dict.get(#(arrival.stop_id, option.Some(arrival.direction)))
      let time = arrival.time
      case time |> util.min_from_now {
        dt if dt >= 0 -> Ok(stop_li(stop, time, train_id, highlighted_stop))
        _ -> Error(Nil)
      }
    })

  let body = [
    html.p([], [
      html.text(
        "Last updated "
        <> last_updated |> timestamp.to_rfc3339(duration.hours(-4)),
      ),
    ]),
    html.ol([attribute.class("stops-list")], stops),
  ]

  Ok(#(Body(body:), wisp.response(200)))
}

fn error_invalid_train_id_encoding() -> #(
  lustre_middleware.LustreRes(c),
  wisp.Response,
) {
  #(Body([html.text("Train id URI encoding is invalid.")]), wisp.response(400))
}

fn error_could_not_find_train(
  train_id: String,
) -> #(lustre_middleware.LustreRes(d), wisp.Response) {
  #(
    Document(head: [html.title([], "Error: Could not find train")], body: [
      html.p([], [
        html.text("Could not find train with identifier " <> train_id),
      ]),
    ]),
    wisp.response(404),
  )
}

fn stop_li(
  stop: Result(st.Stop(a), Nil),
  time: timestamp.Timestamp,
  train_id: rt.TrainId,
  highlighted_stop: Result(st.StopId, Nil),
) -> element.Element(msg) {
  let stop_name =
    stop
    |> result.map(fn(stop) { stop.name })
    |> result.unwrap(or: "<Unknown stop>")
  let stop_url =
    result.map(stop, fn(stop) {
      let stop_id = stop.id |> st.stop_id_to_string(direction: option.None)
      let train_id = train_id |> rt.train_id_to_string |> uri.percent_encode
      let query = uri.query_to_string([#("train_id", train_id)])
      "/stop/" <> stop_id <> "?" <> query
    })
    |> result.unwrap(or: "")

  let stop_id = stop |> result.map(fn(stop) { stop.id })
  let is_highlighted = case stop_id, highlighted_stop {
    Ok(stop_id), Ok(highlight) -> stop_id == highlight
    _, _ -> False
  }

  html.li([], [
    html.a(
      [
        attribute.href(stop_url),
        attribute.classes([#("highlight", is_highlighted)]),
      ],
      [
        html.span([], [html.text(stop_name)]),
        html.span([], [
          html.text(time |> util.min_from_now |> int.to_string <> "min"),
        ]),
      ],
    ),
  ])
}
