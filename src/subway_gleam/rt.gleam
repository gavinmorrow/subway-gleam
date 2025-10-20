import gleam/http/request
import gleam/httpc
import gleam/list
import gleam/option
import gleam/result
import gleam/time/timestamp
import gtfs_rt_nyct
import protobin

import subway_gleam/st

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

pub fn trains_stopping(
  feed: gtfs_rt_nyct.FeedMessage,
  at stop_id: st.StopId,
) -> List(TrainStopping) {
  use acc, entity <- list.fold(over: feed.entity, from: [])

  case entity.data {
    gtfs_rt_nyct.TripUpdate(trip:, stop_time_updates:) -> {
      let is_stop = fn(update: gtfs_rt_nyct.StopTimeUpdate) {
        case st.parse_stop_id(update.stop_id) {
          Error(Nil) -> False
          Ok(id) -> id.route == stop_id.route && id.id == stop_id.id
        }
      }

      let stop = {
        use stop <- result.try(list.find(stop_time_updates, one_that: is_stop))

        let stop_time_event =
          stop.arrival |> option.or(stop.departure) |> option.to_result(Nil)
        use gtfs_rt_nyct.StopTimeEvent(unix) <- result.try(stop_time_event)

        let gtfs_rt_nyct.UnixTime(unix_secs) = unix
        let time = timestamp.from_unix_seconds(unix_secs)

        use stop_id <- result.try(st.parse_stop_id(stop.stop_id))

        TrainStopping(trip:, time:, stop_id:)
        |> Ok
      }

      case stop {
        Ok(stop) -> [stop, ..acc]
        Error(Nil) -> acc
      }
    }
    _ -> acc
  }
}
