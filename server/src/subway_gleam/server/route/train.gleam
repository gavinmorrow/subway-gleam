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
import subway_gleam/server/hydration_scripts.{hydration_scripts}
import subway_gleam/server/lustre_middleware.{Body, Document, try_lustre_res}
import subway_gleam/server/state
import subway_gleam/server/state/gtfs_actor
import subway_gleam/server/time_zone
import subway_gleam/shared/component/route_bullet
import subway_gleam/shared/route/train
import subway_gleam/shared/util/live_status

pub fn train(
  req: wisp.Request,
  state: state.State,
  train_id: String,
) -> wisp.Response {
  use req <- try_lustre_res(req)

  case model(state, train_id, req.query) {
    Ok(model) -> {
      let head = [
        hydration_scripts("train", train.model_to_json(model)),
      ]
      let body = [
        html.div([attribute.id("app")], [
          train.view(model),
        ]),
      ]

      Ok(#(Document(head:, body:), wisp.response(200)))
    }
    Error(InvalidTrainIdEncoding) -> Error(error_invalid_train_id_encoding())
    Error(CouldNotFindTrain(train_id)) ->
      Error(error_could_not_find_train(train_id))
  }
}

pub fn model(
  state: state.State,
  train_id: String,
  query: option.Option(String),
) -> Result(train.Model, Error) {
  // TODO: make this a function?
  let highlighted_stop =
    query
    |> option.to_result(Nil)
    |> result.try(uri.parse_query)
    |> result.unwrap(or: [])
    |> list.key_find("stop_id")
    |> result.try(st.parse_stop_id)
    |> result.map(pair.first)
    |> option.from_result

  let gtfs_actor.Data(current: gtfs, last_updated:) = state.fetch_gtfs(state)

  use train_id <- result.try(
    uri.percent_decode(train_id)
    |> result.replace_error(InvalidTrainIdEncoding),
  )
  let train_id = rt.TrainId(train_id)

  let trip =
    dict.get(gtfs.trips, train_id)
    |> result.replace_error({
      let rt.TrainId(train_id) = train_id
      CouldNotFindTrain(train_id)
    })
  use stops <- result.try(trip)

  let stops =
    list.filter_map(stops, fn(arrival) {
      // If the stop doesn't exist in the stops.txt, it's an internal timepoint
      // and can be ignored.
      // See <https://groups.google.com/g/mtadeveloperresources/c/fdlP92IKmF8>
      result.map(
        dict.get(state.schedule.stops, #(
          arrival.stop_id,
          option.Some(arrival.direction),
        )),
        stop_li(_, arrival.time, train_id, state.schedule),
      )
    })

  let cur_time = time_zone.now()

  Ok(train.Model(
    last_updated:,
    stops:,
    highlighted_stop:,
    event_source: live_status.Unavailable,
    cur_time: cur_time,
  ))
}

pub type Error {
  InvalidTrainIdEncoding
  CouldNotFindTrain(train_id: String)
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

  train.Stop(id: stop.id, name: stop.name, stop_url:, transfers:, time:)
}
