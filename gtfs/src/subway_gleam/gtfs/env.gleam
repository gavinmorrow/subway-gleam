import envoy
import gleam/int
import gleam/result
import gleam/time/timestamp

pub fn use_local_st() -> Bool {
  case envoy.get("gtfs_st") {
    Ok("local") -> True
    _ -> False
  }
}

pub fn use_local_rt() -> Bool {
  case envoy.get("gtfs_rt") {
    Ok("local") -> True
    _ -> False
  }
}

pub fn save_fetched_st() -> Bool {
  case envoy.get("save_fetched_st") {
    Ok("true") -> True
    _ -> False
  }
}

pub fn save_fetched_rt() -> Bool {
  case envoy.get("save_fetched_rt") {
    Ok("true") -> True
    _ -> False
  }
}

/// The latest time the rt feed was fetched.
pub fn rt_time() -> timestamp.Timestamp {
  case
    use_local_rt(),
    envoy.get("gtfs_rt_fetch_time") |> result.try(int.parse)
  {
    True, Ok(time) -> timestamp.from_unix_seconds(time)
    _, _ -> timestamp.system_time()
  }
}
