import gleam/dict
import gleam/http/request
import gleam/httpc
import gleam/list
import gleam/option
import gleam/pair
import gleam/result
import gleam/time/timestamp
import gtfs_rt_nyct
import protobin

import subway_gleam/st

// TODO: find a better name
pub type Data {
  Data(
    message: gtfs_rt_nyct.FeedMessage,
    arrivals: dict.Dict(st.StopId, List(TrainStopping)),
    final_stops: dict.Dict(st.ShapeId, st.StopId),
  )
}

pub type TrainStopping {
  TrainStopping(
    trip: gtfs_rt_nyct.TripDescriptor,
    time: timestamp.Timestamp,
    stop_id: st.StopId,
  )
}

pub type GtfsRtFeed {
  ACESr
  BDFMSf
  G
  JZ
  NQRW
  L
  S1234567
  Si
}

pub type FetchGtfsError {
  HttpError(httpc.HttpError)
  ParseError(protobin.ParseError)
  InvalidStopId(String)
  UnknownStop(st.StopId)
}

fn gtfs_rt_feed_path(feed: GtfsRtFeed) -> String {
  let name = case feed {
    ACESr -> "gtfs-ace"
    BDFMSf -> "gtfs-bdfm"
    G -> "gtfs-g"
    JZ -> "gtfs-jz"
    L -> "gtfs-l"
    NQRW -> "gtfs-nqrw"
    S1234567 -> "gtfs"
    Si -> "gtfs-si"
  }
  "Dataservice/mtagtfsfeeds/nyct%2F" <> name
}

pub fn gtfs_rt_feed_from_stop_id(stop_id: st.StopId) -> GtfsRtFeed {
  case stop_id.route {
    st.A | st.C | st.E | st.Sr -> ACESr
    st.B | st.D | st.F | st.M | st.Sf -> BDFMSf
    st.G -> G
    st.J | st.Z -> JZ
    st.N | st.Q | st.R | st.W -> NQRW
    st.L -> L
    st.N1 | st.N2 | st.N3 | st.N4 | st.N5 | st.N6 | st.N7 | st.S -> S1234567
    st.Si -> Si
  }
}

fn fetch_gtfs_rt_bin(feed: GtfsRtFeed) -> Result(BitArray, httpc.HttpError) {
  let req: request.Request(BitArray) =
    request.new()
    |> request.set_host("api-endpoint.mta.info")
    |> request.set_path(gtfs_rt_feed_path(feed))
    |> request.set_body(<<>>)

  use res <- result.try(httpc.send_bits(req))
  res.body |> Ok
}

pub fn fetch_gtfs(
  feed feed: GtfsRtFeed,
) -> Result(gtfs_rt_nyct.FeedMessage, FetchGtfsError) {
  use bits <- result.try(fetch_gtfs_rt_bin(feed) |> result.map_error(HttpError))
  protobin.parse_with_config(
    from: bits,
    using: gtfs_rt_nyct.feed_message_decoder(),
    config: protobin.Config(ignore_groups: True),
  )
  |> result.map(fn(parsed) { parsed.value })
  |> result.map_error(ParseError)
}

pub fn analyze(raw: gtfs_rt_nyct.FeedMessage) -> Data {
  let #(arrivals, final_stops) =
    list.fold(
      over: raw.entity,
      from: #(dict.new(), dict.new()),
      with: fn(acc, entity) {
        let #(arrivals, final_stops) = acc
        case entity.data {
          gtfs_rt_nyct.Alert(informed_entities:, header_text:) -> #(
            arrivals,
            final_stops,
          )
          gtfs_rt_nyct.TripUpdate(trip:, stop_time_updates:) -> {
            let new_arrivals = parse_trip_update(trip, stop_time_updates)
            let final_stop = list.last(new_arrivals)
            list.fold(
              over: new_arrivals,
              from: #(arrivals, final_stops),
              with: fn(acc, value) {
                let #(stop_id, train_stopping) = value
                let stop_id = st.erase_direction(stop_id)
                acc
                |> pair.map_first(fn(arrivals) {
                  dict.upsert(in: arrivals, update: stop_id, with: fn(cur) {
                    case cur {
                      option.None -> [train_stopping]
                      option.Some(cur) -> [train_stopping, ..cur]
                    }
                  })
                })
                |> pair.map_second(fn(final_stops) {
                  case
                    final_stop,
                    train_stopping.trip.trip_id |> st.parse_shape_id
                  {
                    Ok(#(final_stop, _)), Ok(shape_id) ->
                      dict.insert(
                        into: final_stops,
                        for: shape_id,
                        insert: final_stop,
                      )
                    _, _ -> final_stops
                  }
                })
              },
            )
          }
          gtfs_rt_nyct.VehiclePosition(
            trip:,
            current_stop_sequence:,
            current_status:,
            timestamp:,
            stop_id:,
          ) -> #(arrivals, final_stops)
        }
      },
    )

  Data(message: raw, arrivals:, final_stops:)
}

// pub fn trains_stopping(
//   feed: gtfs_rt_nyct.FeedMessage,
//   at stop_id: st.StopId,
// ) -> List(TrainStopping) {
//   use acc, entity <- list.fold(over: feed.entity, from: [])

//   case entity.data {
//     gtfs_rt_nyct.TripUpdate(trip:, stop_time_updates:) ->
//       case
//         parse_trip_update(trip, stop_time_updates)
//         |> dict.from_list
//         |> dict.get(stop_id)
//       {
//         Ok(stop) -> [stop, ..acc]
//         Error(Nil) -> acc
//       }
//     _ -> acc
//   }
// }

fn parse_trip_update(
  trip: gtfs_rt_nyct.TripDescriptor,
  stop_time_updates: List(gtfs_rt_nyct.StopTimeUpdate),
) -> List(#(st.StopId, TrainStopping)) {
  use acc, stop <- list.fold(over: stop_time_updates, from: [])

  let train_stopping = {
    let stop_time_event =
      stop.arrival |> option.or(stop.departure) |> option.to_result(Nil)
    use gtfs_rt_nyct.StopTimeEvent(unix) <- result.try(stop_time_event)

    let gtfs_rt_nyct.UnixTime(unix_secs) = unix
    let time = timestamp.from_unix_seconds(unix_secs)

    use stop_id <- result.try(st.parse_stop_id(stop.stop_id))

    TrainStopping(trip:, time:, stop_id:)
    |> Ok
  }

  case train_stopping {
    Error(Nil) -> acc
    Ok(train_stopping) -> [#(train_stopping.stop_id, train_stopping), ..acc]
  }
}
