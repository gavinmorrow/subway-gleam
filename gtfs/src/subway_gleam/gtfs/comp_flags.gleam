import gleam/time/timestamp

pub const use_local_st: Bool = True

pub const use_local_rt: Bool = False

pub const save_fetched_st: Bool = False

pub const save_fetched_rt: Bool = False

/// The latest time the rt feed was fetched.
pub fn rt_time() -> timestamp.Timestamp {
  case use_local_rt {
    True -> timestamp.from_unix_seconds(1_769_567_100)
    False -> timestamp.system_time()
  }
}
