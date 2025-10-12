//// Work with the static GTFS data.

pub type Feed {
  /// This file represents the "normal" subway schedule and does not include
  /// most temporary service changes, though some long term service changes may
  /// be included. It is typically updated a few times a year.
  Regular
  /// This file includes most, but not all, service changes for the next seven
  /// calendar days. Generally, the 'simpler' the service change, the more
  /// likely it will not be included. Beyond that period, service changes will
  /// not be included. It is updated **hourly**.
  Supplemented
}

pub type Schedule

pub fn fetch(feed: Feed) -> Schedule {
  let url = case feed {
    Regular -> "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_subway.zip"
    Supplemented -> "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_supplemented.zip"
  }
  todo
}
