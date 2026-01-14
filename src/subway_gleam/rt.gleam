import gleam/dict

// import gleam/http/request
import gleam/httpc
import gleam/list
import gleam/option
import gleam/result
import gleam/time/timestamp
import gtfs_rt_nyct
import protobin
import simplifile

import subway_gleam/st

// TODO: find a better name
pub type Data {
  Data(
    arrivals: dict.Dict(st.StopId, List(TrainStopping)),
    final_stops: dict.Dict(st.ShapeId, #(st.StopId, st.Direction)),
    trips: dict.Dict(TrainId, List(TrainStopping)),
  )
}

pub fn empty_data() -> Data {
  Data(arrivals: dict.new(), final_stops: dict.new(), trips: dict.new())
}

pub fn data_merge(into a: Data, from b: Data) -> Data {
  let arrivals =
    dict.combine(a.arrivals, b.arrivals, with: fn(a, b) { list.append(a, b) })
  let final_stops = dict.merge(into: a.final_stops, from: b.final_stops)
  let trips =
    dict.combine(a.trips, b.trips, with: fn(a, b) { list.append(a, b) })

  Data(arrivals:, final_stops:, trips:)
}

pub fn data_map_arrivals(data: Data, fun) -> Data {
  Data(..data, arrivals: fun(data.arrivals))
}

pub fn data_map_final_stops(data: Data, fun) -> Data {
  Data(..data, final_stops: fun(data.final_stops))
}

pub type TrainStopping {
  TrainStopping(
    trip: gtfs_rt_nyct.TripDescriptor,
    time: timestamp.Timestamp,
    stop_id: st.StopId,
    direction: st.Direction,
  )
}

pub type TrainId {
  TrainId(String)
}

pub fn train_id_to_string(train_id: TrainId) -> String {
  let TrainId(train_id) = train_id
  train_id
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

pub const all_feeds = [
  ACESr,
  BDFMSf,
  G,
  JZ,
  NQRW,
  L,
  S1234567,
  Si,
]

pub type FetchGtfsError {
  HttpError(httpc.HttpError)
  ParseError(protobin.ParseError)
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

pub fn gtfs_rt_feed_from_route(route: st.Route) -> GtfsRtFeed {
  case route {
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
  // let req: request.Request(BitArray) =
  //   request.new()
  //   |> request.set_host("api-endpoint.mta.info")
  //   |> request.set_path(gtfs_rt_feed_path(feed))
  // |> request.set_body(<<>>)

  // use res <- result.try(httpc.send_bits(req))
  // res.body |> Ok

  // Don't fetch real data while prototyping
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
  let path = "./gtfs_rt_samples/" <> name
  let assert Ok(bits) = simplifile.read_bits(from: path)
  Ok(bits)
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
  list.fold(over: raw.entity, from: empty_data(), with: fn(acc, entity) {
    case entity.data {
      gtfs_rt_nyct.Alert(informed_entities: _, header_text: _) -> acc
      gtfs_rt_nyct.TripUpdate(trip:, stop_time_updates:) -> {
        let new_arrivals = parse_trip_update(trip, stop_time_updates)
        let final_stop = list.last(new_arrivals)

        let train_id = trip.nyct.train_id |> option.map(TrainId)
        let trips =
          train_id
          |> option.map(dict.insert(
            into: acc.trips,
            for: _,
            insert: new_arrivals,
          ))
          |> option.unwrap(or: acc.trips)
        let acc = Data(..acc, trips:)

        list.fold(over: new_arrivals, from: acc, with: fn(acc, train_stopping) {
          Data(
            ..acc,
            arrivals: {
              dict.upsert(
                in: acc.arrivals,
                update: train_stopping.stop_id,
                with: fn(cur) {
                  case cur {
                    option.None -> [train_stopping]
                    option.Some(cur) -> [train_stopping, ..cur]
                  }
                },
              )
            },
            final_stops: {
              case
                final_stop,
                train_stopping.trip.trip_id |> st.parse_shape_id
              {
                Ok(final_stop), Ok(shape_id) ->
                  dict.insert(into: acc.final_stops, for: shape_id, insert: #(
                    final_stop.stop_id,
                    final_stop.direction,
                  ))
                _, _ -> acc.final_stops
              }
            },
          )
        })
      }
      gtfs_rt_nyct.VehiclePosition(
        trip: _,
        current_stop_sequence: _,
        current_status: _,
        timestamp: _,
        stop_id: _,
      ) -> acc
    }
  })
}

fn parse_trip_update(
  trip: gtfs_rt_nyct.TripDescriptor,
  stop_time_updates: List(gtfs_rt_nyct.StopTimeUpdate),
) -> List(TrainStopping) {
  use acc, stop <- list.fold(over: stop_time_updates |> list.reverse, from: [])

  let train_stopping = {
    let stop_time_event =
      stop.arrival |> option.or(stop.departure) |> option.to_result(Nil)
    use gtfs_rt_nyct.StopTimeEvent(unix) <- result.try(stop_time_event)

    let gtfs_rt_nyct.UnixTime(unix_secs) = unix
    let time = timestamp.from_unix_seconds(unix_secs)

    use #(stop_id, direction) <- result.try(st.parse_stop_id(stop.stop_id))
    use direction <- result.try(direction |> option.to_result(Nil))

    TrainStopping(trip:, time:, stop_id:, direction:)
    |> Ok
  }

  case train_stopping {
    Error(Nil) -> acc
    Ok(train_stopping) -> [train_stopping, ..acc]
  }
}
