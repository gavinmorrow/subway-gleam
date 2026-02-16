import gleam/dynamic/decode
import gleam/json

import subway_gleam/gtfs/st

pub fn decoder() -> decode.Decoder(st.StopId) {
  use stop_id <- decode.then(decode.string)
  st.StopId(stop_id) |> decode.success
}

pub fn to_json(stop_id: st.StopId) -> json.Json {
  let st.StopId(stop_id) = stop_id
  json.string(stop_id)
}

pub fn to_dict_key(stop_id: st.StopId) -> String {
  let st.StopId(stop_id) = stop_id
  stop_id
}
