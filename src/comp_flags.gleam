import gleam/time/timestamp

pub const use_local_st: Bool = True

pub const use_local_rt: Bool = True

pub const save_fetched_st: Bool = False

pub const save_fetched_rt: Bool = False

/// The latest time the rt feed was fetched.
pub fn rt_time() -> timestamp.Timestamp {
  timestamp.from_unix_seconds(1_768_910_519)
}
