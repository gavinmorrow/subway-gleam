import gleam/erlang/process
import mist
import wisp
import wisp/wisp_mist

import subway_gleam/route

pub fn main() -> Nil {
  wisp.configure_logger()

  let secret_key_base = wisp.random_string(64)

  let assert Ok(_) =
    wisp_mist.handler(handler, secret_key_base)
    |> mist.new
    |> mist.port(8000)
    |> mist.start

  process.sleep_forever()
}

fn handler(req: wisp.Request) -> wisp.Response {
  use req <- route.middleware(req)

  case wisp.path_segments(req) {
    [] -> route.index(req)
    ["stop", stop_id] -> route.stop(req, stop_id)
    _ -> route.not_found(req)
  }
}
