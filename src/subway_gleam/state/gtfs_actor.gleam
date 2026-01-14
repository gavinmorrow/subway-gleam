import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/time/timestamp
import subway_gleam/internal/util
import subway_gleam/rt

pub type Subject =
  process.Subject(Message)

pub type State {
  State(self: Subject, data: Data)
}

pub type Data {
  Data(current: rt.Data, last_updated: timestamp.Timestamp)
}

pub type Message {
  Get(process.Subject(Data))
  Update
  SetData(Result(Data, rt.FetchGtfsError))
}

pub fn gtfs_actor() -> Result(actor.Started(Subject), actor.StartError) {
  actor.new_with_initialiser(60 * 1000, fn(self) {
    use data <- result.try(
      fetch_all_rt_feeds()
      |> result.replace_error("fetch gtfs_rt error"),
    )
    let state = State(self:, data:)

    actor.initialised(state) |> actor.returning(self) |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(state: State, msg: Message) -> actor.Next(State, Message) {
  case msg {
    Get(reply) -> {
      actor.send(reply, state.data)
      actor.continue(state)
    }
    Update -> {
      process.spawn(fn() {
        fetch_all_rt_feeds()
        |> SetData
        |> process.send(state.self, _)
      })

      actor.continue(state)
    }
    SetData(Error(_)) -> actor.continue(state)
    SetData(Ok(data)) -> actor.continue(State(..state, data:))
  }
}

fn fetch_all_rt_feeds() -> Result(Data, rt.FetchGtfsError) {
  let current_time = util.current_time()

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

  Data(data, last_updated: current_time) |> Ok
}
