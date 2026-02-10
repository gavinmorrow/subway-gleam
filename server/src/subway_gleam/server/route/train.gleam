import gleam/dict
import gleam/list
import gleam/option
import gleam/pair
import gleam/result
import gleam/set
import gleam/string
import gleam/time/timestamp
import gleam/uri
import lustre/attribute
import lustre/element/html
import wisp

import subway_gleam/gtfs/rt
import subway_gleam/gtfs/st
import subway_gleam/server/lustre_middleware.{Body, Document, try_lustre_res}
import subway_gleam/server/state
import subway_gleam/server/state/gtfs_actor
import subway_gleam/shared/component/route_bullet
import subway_gleam/shared/route/train
import subway_gleam/shared/util

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
      // If the stop doesn't exist in the stops.txt, it's an internal timepoint
      // and can be ignored.
      // See <https://groups.google.com/g/mtadeveloperresources/c/fdlP92IKmF8>
      use stop <- result.try(
        dict.get(state.schedule.stops, #(
          arrival.stop_id,
          option.Some(arrival.direction),
        )),
      )

      let time = arrival.time
      case time |> util.min_from_now {
        dt if dt >= 0 ->
          Ok(stop_li(stop, time, train_id, highlighted_stop, state.schedule))
        _ -> Error(Nil)
      }
    })

  let model = train.Model(last_updated:, stops:)
  let body = [
    html.div([attribute.id("app")], [
      train.view(model),
    ]),
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
  stop: st.Stop(a),
  time: timestamp.Timestamp,
  train_id: rt.TrainId,
  highlighted_stop: Result(st.StopId, Nil),
  schedule: st.Schedule,
) -> train.Stop {
  let stop_url = {
    let stop_id = stop.id |> st.stop_id_to_string(direction: option.None)
    let train_id =
      train_id
      |> rt.train_id_to_string
      |> uri.percent_encode
      // uri.percent_encode doesn't encode pluses
      |> string.replace(each: "+", with: "%2B")
    let query = uri.query_to_string([#("train_id", train_id)])
    "/stop/" <> stop_id <> "?" <> query
  }

  let is_highlighted = case highlighted_stop {
    Ok(highlight) -> stop.id == highlight
    _ -> False
  }

  let transfers =
    dict.get(schedule.transfers, stop.id)
    |> result.map(set.to_list)
    |> result.unwrap(or: [])
    |> list.flat_map(fn(transfer) {
      dict.get(schedule.stop_routes, transfer.destination)
      |> result.map(set.to_list)
      |> result.unwrap(or: [])
    })
    |> list.map(st.route_data(for: _, in: schedule))
    |> list.sort(by: st.route_compare)
    |> list.map(route_bullet.from_route_data)

  train.Stop(name: stop.name, stop_url:, is_highlighted:, transfers:, time:)
}
