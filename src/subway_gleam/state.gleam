import gleam/erlang/process
import gleam/option
import gleam/otp/actor
import gleam/result
import gleam/time/timestamp
import gtfs_rt_nyct

import subway_gleam/rt
import subway_gleam/st

pub type State {
  State(
    priv_dir: String,
    schedule: st.Schedule,
    rt_actor: actor.Started(process.Subject(RtActorMessage)),
  )
}

pub type RtActorState {
  RtActorState(
    self: process.Subject(RtActorMessage),
    feed: rt.GtfsRtFeed,
    data: RtData,
  )
}

pub type RtData {
  RtData(current: gtfs_rt_nyct.FeedMessage, last_updated: timestamp.Timestamp)
}

pub type RtActorMessage {
  Get(process.Subject(RtData))
  Update
  SetData(Result(RtData, rt.FetchGtfsError))
}

pub fn rt_actor(
  feed feed: rt.GtfsRtFeed,
) -> Result(actor.Started(process.Subject(RtActorMessage)), actor.StartError) {
  actor.new_with_initialiser(60 * 1000, fn(self) {
    let current_time = timestamp.system_time()
    use rt <- result.try(
      rt.fetch_gtfs(feed:) |> result.replace_error("fetch gtfs_rt error"),
    )
    let data = RtData(current: rt, last_updated: current_time)
    let state = RtActorState(self:, feed:, data:)

    actor.initialised(state) |> actor.returning(self) |> Ok
  })
  |> actor.on_message(rt_handle_message)
  |> actor.start
}

fn rt_handle_message(
  state: RtActorState,
  msg: RtActorMessage,
) -> actor.Next(RtActorState, RtActorMessage) {
  case msg {
    Get(reply) -> {
      actor.send(reply, state.data)
      actor.continue(state)
    }
    Update -> {
      process.spawn(fn() {
        let time_started = timestamp.system_time()
        rt.fetch_gtfs(feed: state.feed)
        |> result.map(RtData(current: _, last_updated: time_started))
        |> SetData
        |> process.send(state.self, _)
      })

      actor.continue(state)
    }
    SetData(Error(_)) -> actor.continue(state)
    SetData(Ok(data)) -> actor.continue(RtActorState(..state, data:))
  }
}
