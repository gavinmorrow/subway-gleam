import comp_flags
import gleam/dict
import gleam/http/request
import gleam/httpc
import gleam/list
import gleam/option
import gleam/pair
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import gtfs_rt_nyct
import protobin
import simplifile
import subway_gleam/internal/util

import subway_gleam/rt/rich_text.{type RichText}
import subway_gleam/rt/time_range.{type TimeRange}
import subway_gleam/st

// TODO: find a better name
pub type Data {
  Data(
    arrivals: dict.Dict(st.StopId, List(TrainStopping)),
    final_stops: dict.Dict(st.ShapeId, #(st.StopId, st.Direction)),
    trips: dict.Dict(TrainId, List(TrainStopping)),
    alerts: List(Alert),
  )
}

pub fn empty_data() -> Data {
  Data(
    arrivals: dict.new(),
    final_stops: dict.new(),
    trips: dict.new(),
    alerts: list.new(),
  )
}

pub fn data_merge(into a: Data, from b: Data) -> Data {
  let arrivals =
    dict.combine(a.arrivals, b.arrivals, with: fn(a, b) { list.append(a, b) })
  let final_stops = dict.merge(into: a.final_stops, from: b.final_stops)
  let trips =
    dict.combine(a.trips, b.trips, with: fn(a, b) { list.append(a, b) })
  let alerts = list.append(a.alerts, b.alerts)

  Data(arrivals:, final_stops:, trips:, alerts:)
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

pub type Alert {
  Alert(
    id: String,
    /// Time when the alert should be shown to the user. If missing, the alert
    /// will be shown as long as it appears in the feed. If multiple ranges are
    /// given, the alert will be shown during all of them.
    active_periods: List(TimeRange),
    /// Entities whose users we should notify of this alert.
    target: List(gtfs_rt_nyct.EntitySelector),
    /// A headline to describe the high-level impacts of a disruption. Headlines
    /// are capped at 160 characters.
    header: RichText,
    /// Provides full details of a disruption’s impacts. Details do not have a character limit.
    description: option.Option(RichText),
    /// Time when the message was created in Mercury (not to be confused with
    /// active_period start time.
    created: option.Option(timestamp.Timestamp),
    /// Time when the message was last updated in Mercury. 
    updated: option.Option(timestamp.Timestamp),
    /// The service status category for the alert (e.g. “Delays”).
    ///
    /// While there are a standard set of service status categories, the MTA
    /// may add/remove/change them so data consumers should treat this as a free
    /// text field.
    alert_type: option.Option(String),
    /// An array of station alternatives for some planned work messages. Each
    /// station has an affectedEntity with agencyId and stopId and a notes
    /// object consisting of TranslatedStrings
    station_alternatives: List(#(gtfs_rt_nyct.EntitySelector, RichText)),
    /// Number of seconds before the active_period start time that the MTA sets
    /// a message to appear on our homepage to give customers advance notice
    /// of a planned service change. The value for service alerts is 0 and the
    /// default value for planned work messages is 3600.
    display_before_active: duration.Duration,
    /// A human-readable summary of the dates and times when a planned service
    /// change impacts customers.
    human_readable_active_period: option.Option(RichText),
    /// If the message was duplicated from a previous message, this is the id of
    /// the original message.
    clone_id: option.Option(String),
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

fn gtfs_rt_feed_filename(feed: GtfsRtFeed) -> String {
  case feed {
    ACESr -> "gtfs-ace"
    BDFMSf -> "gtfs-bdfm"
    G -> "gtfs-g"
    JZ -> "gtfs-jz"
    L -> "gtfs-l"
    NQRW -> "gtfs-nqrw"
    S1234567 -> "gtfs"
    Si -> "gtfs-si"
  }
}

fn gtfs_rt_feed_path(feed: GtfsRtFeed) -> String {
  "Dataservice/mtagtfsfeeds/nyct%2F" <> gtfs_rt_feed_filename(feed)
}

pub fn gtfs_rt_feed_from_route(route: st.Route) -> GtfsRtFeed {
  case route {
    st.A | st.C | st.E | st.Sr -> ACESr
    st.B | st.D | st.F | st.FX | st.M | st.Sf -> BDFMSf
    st.G -> G
    st.J | st.Z -> JZ
    st.N | st.Q | st.R | st.W -> NQRW
    st.L -> L
    st.N1
    | st.N2
    | st.N3
    | st.N4
    | st.N5
    | st.N6
    | st.N6X
    | st.N7
    | st.N7X
    | st.S -> S1234567
    st.Si -> Si
  }
}

fn fetch_gtfs_rt_bin(feed: GtfsRtFeed) -> Result(BitArray, httpc.HttpError) {
  case comp_flags.use_local_rt {
    True -> {
      let name = gtfs_rt_feed_filename(feed)
      let path = "./gtfs_rt_samples/" <> name
      let assert Ok(bits) = simplifile.read_bits(from: path)
      Ok(bits)
    }
    False -> {
      let req: request.Request(BitArray) =
        request.new()
        |> request.set_host("api-endpoint.mta.info")
        |> request.set_path(gtfs_rt_feed_path(feed))
        |> request.set_body(<<>>)

      use res <- result.try(httpc.send_bits(req))
      res.body |> Ok
    }
  }
}

pub fn fetch_gtfs(
  feed feed: GtfsRtFeed,
) -> Result(gtfs_rt_nyct.FeedMessage, FetchGtfsError) {
  use bits <- result.try(fetch_gtfs_rt_bin(feed) |> result.map_error(HttpError))

  let assert Ok(Nil) = case comp_flags.save_fetched_rt {
    True -> {
      let filename = gtfs_rt_feed_filename(feed)
      simplifile.write_bits(bits, to: "./gtfs_rt_samples/" <> filename)
    }
    False -> Ok(Nil)
  }

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
      gtfs_rt_nyct.Alert(
        active_periods:,
        informed_entities:,
        header_text:,
        description_text:,
        mercury_alert:,
      ) -> {
        let alert =
          Alert(
            id: entity.id,
            active_periods: list.map(
              active_periods,
              time_range.from_gtfs_rt_nyct,
            ),
            target: informed_entities,
            header: rich_text.from_translated_string(header_text),
            description: option.map(
              description_text,
              rich_text.from_translated_string,
            ),
            created: option.map(mercury_alert, fn(m) {
              util.unix_time_to_timestamp(m.created_at)
            }),
            updated: option.map(mercury_alert, fn(m) {
              util.unix_time_to_timestamp(m.updated_at)
            }),
            alert_type: option.map(mercury_alert, fn(m) { m.alert_type }),
            station_alternatives: option.map(mercury_alert, fn(m) {
              list.map(m.station_alternatives, pair.map_second(
                _,
                with: rich_text.from_translated_string,
              ))
            })
              |> option.unwrap(or: []),
            display_before_active: option.map(mercury_alert, fn(m) {
              m.display_before_active
            })
              // "The value for service alerts is 0 and the default value for planned work
              // messages is 3600."
              // My logic is that if it's in the gtfs ahead of time, it must be planned
              // work, and therefore should have a default of 3600. If it's not planned
              // work, the active period will be *now* so setting it to appear 3600sec
              // early won't change anything.
              |> option.unwrap(or: 3600)
              |> duration.seconds,
            human_readable_active_period: option.then(mercury_alert, fn(m) {
              m.human_readable_active_period
            })
              |> option.map(rich_text.from_translated_string),
            clone_id: option.then(mercury_alert, fn(m) { m.clone_id }),
          )
        Data(..acc, alerts: [alert, ..acc.alerts])
      }
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
