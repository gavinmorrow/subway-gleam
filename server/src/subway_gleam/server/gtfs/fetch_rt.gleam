import gleam/http/request
import gleam/httpc
import gleam/result
import gleam/string
import gtfs_rt_nyct
import protobin
import simplifile

import subway_gleam/gtfs/env
import subway_gleam/gtfs/rt

fn fetch_gtfs_rt_bin(feed: rt.GtfsRtFeed) -> Result(BitArray, httpc.HttpError) {
  case env.use_local_rt() {
    True -> {
      let name = gtfs_rt_feed_filename(feed)
      let path = "../gtfs_rt_samples/" <> name
      let assert Ok(bits) = simplifile.read_bits(from: path)
      Ok(bits)
    }
    False -> {
      let req: request.Request(BitArray) =
        request.new()
        |> request.set_host("api-endpoint.mta.info")
        |> request.set_path(gtfs_rt_feed_path(feed))
        |> request.set_body(<<>>)

      use res <- result.try(httpc.send_bits(req))
      res.body |> Ok
    }
  }
}

pub fn fetch_gtfs(
  feed feed: rt.GtfsRtFeed,
) -> Result(gtfs_rt_nyct.FeedMessage, rt.FetchGtfsError) {
  use bits <- result.try(
    fetch_gtfs_rt_bin(feed) |> result.map_error(rt.HttpError),
  )

  let assert Ok(Nil) = case env.save_fetched_rt() {
    True -> {
      let filename = gtfs_rt_feed_filename(feed)
      simplifile.write_bits(bits, to: "../gtfs_rt_samples/" <> filename)
    }
    False -> Ok(Nil)
  }

  protobin.parse_with_config(
    from: bits,
    using: gtfs_rt_nyct.feed_message_decoder(),
    config: protobin.Config(ignore_groups: True),
  )
  |> result.map(fn(parsed) { parsed.value })
  |> result.map_error(rt.ParseError)
}

fn gtfs_rt_feed_filename(feed: rt.GtfsRtFeed) -> String {
  case feed {
    rt.ACESr -> "nyct_gtfs-ace"
    rt.BDFMSf -> "nyct_gtfs-bdfm"
    rt.G -> "nyct_gtfs-g"
    rt.JZ -> "nyct_gtfs-jz"
    rt.L -> "nyct_gtfs-l"
    rt.NQRW -> "nyct_gtfs-nqrw"
    rt.S1234567 -> "nyct_gtfs"
    rt.Si -> "nyct_gtfs-si"
    rt.Alerts -> "camsys_subway-alerts"
  }
}

fn gtfs_rt_feed_path(feed: rt.GtfsRtFeed) -> String {
  "Dataservice/mtagtfsfeeds/"
  <> gtfs_rt_feed_filename(feed) |> string.replace(each: "_", with: "%2F")
}
