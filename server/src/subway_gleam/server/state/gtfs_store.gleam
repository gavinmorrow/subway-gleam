import booklet.{type Booklet}
import gleam/erlang/process
import gleam/list
import gleam/result
import gleam/set.{type Set}
import gleam/time/timestamp

import subway_gleam/gtfs/rt
import subway_gleam/server/gtfs/fetch_rt
import subway_gleam/shared/util

pub opaque type GtfsStore {
  GtfsStore(data: Booklet(Data), watchers: Booklet(Set(process.Subject(Nil))))
}

pub type Data {
  Data(current: rt.Data, last_updated: timestamp.Timestamp)
}

pub fn new() -> Result(GtfsStore, rt.FetchGtfsError) {
  use data <- result.map(fetch_all_rt_feeds())
  let data = booklet.new(data)
  let watchers = booklet.new(set.new())
  GtfsStore(data:, watchers:)
}

pub fn get(from store: GtfsStore) -> Data {
  booklet.get(from: store.data)
}

pub fn update(store: GtfsStore) -> Nil {
  process.spawn(fn() {
    use data <- result.map(fetch_all_rt_feeds())
    // Update data
    booklet.set(store.data, to: data)
    // Notify watchers
    store.watchers |> booklet.get |> set.map(process.send(_, Nil))
  })
  Nil
}

pub fn subscribe_watcher(
  to store: GtfsStore,
  watcher watcher: process.Subject(Nil),
) -> Nil {
  let watchers = booklet.get(store.watchers)
  booklet.set(store.watchers, to: set.insert(watcher, into: watchers))
}

pub fn unsubscribe_watcher(
  from store: GtfsStore,
  watcher watcher: process.Subject(Nil),
) -> Nil {
  let watchers = booklet.get(store.watchers)
  booklet.set(store.watchers, to: set.delete(watcher, from: watchers))
}

fn fetch_all_rt_feeds() -> Result(Data, rt.FetchGtfsError) {
  let current_time = util.current_time()

  use data <- result.try(
    list.try_fold(
      over: rt.all_feeds,
      from: rt.empty_data(),
      with: fn(acc, feed) {
        use rt <- result.map(
          fetch_rt.fetch_gtfs(feed:)
          |> result.map(rt.analyze),
        )
        acc |> rt.data_merge(from: rt)
      },
    ),
  )

  Data(data, last_updated: current_time) |> Ok
}
