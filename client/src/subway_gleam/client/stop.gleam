import gleam/json
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import lustre
import lustre/effect.{type Effect}
import lustre_event_source
import plinth/browser/document
import plinth/browser/element

import subway_gleam/client/stops
import subway_gleam/client/util/set_interval
import subway_gleam/shared/route/stop.{type Model, Model, view}
import subway_gleam/shared/util/live_status.{live_status}
import subway_gleam/shared/util/time.{Time}

pub fn main() -> Result(lustre.Runtime(Msg), lustre.Error) {
  // TODO: handle errors: model not found, and invalid JSON
  let assert Ok(Ok(model)) =
    document.get_element_by_id("model")
    |> result.map(element.inner_text)
    |> result.map(json.parse(_, stop.model_decoder()))

  let is_fav = stops.is_fav_stop(stop.model_to_stop_li(model))
  let model = Model(..model, is_fav:)

  let app = lustre.application(init, update, view(_, ToggleFavBtnPressed))
  let assert Ok(_) = lustre.start(app, onto: "#app", with: model)
}

pub type Msg {
  ToggleFavBtnPressed
  EventSource(lustre_event_source.Message)
  /// Update the current timestamp and time zone offset
  UpdateTime(timestamp.Timestamp, Result(duration.Duration, Nil))
}

fn init(flags: Model) -> #(Model, Effect(Msg)) {
  let update_cur_time = set_interval.update_time(UpdateTime)
  let event_source = lustre_event_source.init("./model_stream", EventSource)

  #(flags, effect.batch([update_cur_time, event_source]))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ToggleFavBtnPressed -> #(
      Model(..model, is_fav: !model.is_fav),
      effect.from(fn(_dispatch) {
        // TODO: handle error
        let assert Ok(_) = case model.is_fav {
          True -> stops.remove_fav_stop(stop.model_to_stop_li(model))
          False -> stops.add_fav_stop(stop.model_to_stop_li(model))
        }
        Nil
      }),
    )

    EventSource(lustre_event_source.Data(data)) -> {
      case json.parse(from: data, using: stop.model_decoder()) {
        Ok(Model(
          id:,
          name:,
          last_updated:,
          transfers:,
          alerted_routes:,
          alert_summary:,
          uptown:,
          downtown:,
          highlighted_train: _,
          event_source: _,
          cur_time: _,
          is_fav: _,
        )) -> #(
          Model(
            ..model,
            id:,
            name:,
            last_updated:,
            transfers:,
            alerted_routes:,
            alert_summary:,
            uptown:,
            downtown:,
          ),
          effect.none(),
        )
        Error(_) -> todo as "handle model decode error"
      }
    }
    EventSource(lustre_event_source.Init(event_source))
    | EventSource(lustre_event_source.OnOpen(event_source)) -> {
      #(Model(..model, event_source: live_status(event_source)), effect.none())
    }
    EventSource(lustre_event_source.Error) -> {
      let live_status = case model.event_source {
        live_status.Connecting(event_source) -> live_status(event_source)
        live_status.Live(event_source) -> live_status(event_source)
        live_status.Unavailable -> live_status.Unavailable
      }
      #(Model(..model, event_source: live_status), effect.none())
    }
    EventSource(lustre_event_source.NoEventSourceClient) -> #(
      Model(..model, event_source: live_status.Unavailable),
      effect.none(),
    )

    UpdateTime(timestamp, time_zone_offset) -> #(
      Model(
        ..model,
        cur_time: Time(
          timestamp:,
          time_zone_offset: time_zone_offset
            |> result.or(model.cur_time.time_zone_offset),
        ),
      ),
      effect.none(),
    )
  }
}
