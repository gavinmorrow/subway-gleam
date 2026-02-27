import gleam/http/request
import gleam/httpc
import gleam/result
import simplifile

import subway_gleam/gtfs/env
import subway_gleam/gtfs/st

pub fn fetch_bin(feed: st.Feed) -> Result(BitArray, httpc.HttpError) {
  let req: request.Request(BitArray) =
    request.new()
    |> request.set_host("rrgtfsfeeds.s3.amazonaws.com")
    |> request.set_path(feed_path(feed))
    |> request.set_body(<<>>)

  use res <- result.try(httpc.send_bits(req))

  let assert Ok(Nil) = case env.save_fetched_st() {
    True -> simplifile.write_bits(res.body, to: "gtfs_subway.zip")
    False -> Ok(Nil)
  }

  res.body |> Ok
}

fn feed_path(feed: st.Feed) -> String {
  case feed {
    st.Regular -> "gtfs_subway.zip"
    st.Supplemented -> "gtfs_supplemented.zip"
  }
}
