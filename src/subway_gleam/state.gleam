import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/time/timestamp

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
  RtActorState(self: process.Subject(RtActorMessage), data: RtData)
}

pub type RtData {
  RtData(current: rt.Data, last_updated: timestamp.Timestamp)
}

pub type RtActorMessage {
  Get(process.Subject(RtData))
  Update
  SetData(Result(RtData, rt.FetchGtfsError))
}

pub fn fetch_gtfs(state: State) -> RtData {
  actor.call(state.rt_actor.data, waiting: 100, sending: Get)
}

fn fetch_all() -> Result(RtData, rt.FetchGtfsError) {
  let current_time = timestamp.system_time()

  use data <- result.try(
    list.try_fold(
      over: rt.all_feeds,
      from: rt.empty_data(),
      with: fn(acc, feed) {
        use rt <- result.map(
          rt.fetch_gtfs(feed:)
          |> result.map(rt.analyze),
        )
        acc |> rt.data_merge(from: rt)
      },
    ),
  )

  RtData(data, last_updated: current_time) |> Ok
}

pub fn rt_actor() -> Result(
  actor.Started(process.Subject(RtActorMessage)),
  actor.StartError,
) {
  actor.new_with_initialiser(60 * 1000, fn(self) {
    use data <- result.try(
      fetch_all()
      |> result.replace_error("fetch gtfs_rt error"),
    )
    let state = RtActorState(self:, data:)

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
        fetch_all()
        |> SetData
        |> process.send(state.self, _)
      })

      actor.continue(state)
    }
    SetData(Error(_)) -> actor.continue(state)
    SetData(Ok(data)) -> actor.continue(RtActorState(..state, data:))
  }
}
