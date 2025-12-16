//// A sample schedule to use that doesn't take forever to parse.

import subway_gleam/st.{
  type ShapeId, A, B, C, D, E, F, G, J, L, M, N, N1, N2, N3, N4, N5, N6, N7,
  North, Q, R, S, Schedule, Service, Sf, Si, South, Sr, Stop, StopId, Trips, W,
  Z, parse_shape_id,
}

import gleam/dict
import gleam/option.{None, Some}

fn shape_id(shape_id: String) -> ShapeId {
  let assert Ok(shape_id) = parse_shape_id(shape_id)
  shape_id
}

/// A sample schedule to use that doesn't take 15sec to parse.
pub fn schedule() {
  todo
}
