//// Haversine distance (<https://en.wikipedia.org/wiki/Haversine_formula>)

import gleam/float
import gleam/result
import gleam_community/maths.{cos}

// Found using <https://planetcalc.com/7721/>
/// The radius of the Earth in kilometers at 40º 42′ 46.74″
/// (the latitude of New York City).
pub const radius: Float = 6369.082609272675

/// The haversine distance from point a (lat, lon) to point b (lat, lon).
/// Expressed in kilometers.
pub fn distance(from a: #(Float, Float), to b: #(Float, Float)) -> Float {
  let #(a_lat, a_lon) = a
  let #(b_lat, b_lon) = b

  let a_lat = maths.degrees_to_radians(a_lat)
  let a_lon = maths.degrees_to_radians(a_lon)
  let b_lat = maths.degrees_to_radians(b_lat)
  let b_lon = maths.degrees_to_radians(b_lon)

  let d_lat = b_lat -. a_lat
  let d_lon = b_lon -. a_lon

  let hav =
    { 1.0 -. cos(d_lat) +. cos(a_lat) *. cos(b_lat) *. { 1.0 -. cos(d_lon) } }
    /. 2.0

  let theta = {
    let sqrt = float.square_root(hav) |> result.unwrap(or: 0.0)
    let sqrt = float.clamp(sqrt, min: -1.0, max: 1.0)
    // Assert is okay b/c just clamped the sqrt to [-1.0, 1.0] above
    let assert Ok(asin) = maths.asin(sqrt)
    2.0 *. asin
  }

  radius *. theta
}
