import gleam/dynamic/decode
import gleam/json
import gleam/string
import lustre/attribute
import lustre/element
import lustre/element/html

import subway_gleam/gtfs/st

pub type RouteBullet {
  RouteBullet(
    text: String,
    shape: st.BulletShape,
    color: String,
    text_color: String,
  )
}

pub fn route_bullet(bullet: RouteBullet) -> element.Element(msg) {
  // let route_text = st.route_to_long_id(route.id)
  // TODO: make this less hacky. maybe pass around separate "diamond express" property?
  // let assert Ok(route_text) = string.first(route_text)

  // let shape = case st.bullet_shape(for: route.id) {
  // st.Circle -> "circle"
  // st.Diamond -> "diamond"
  // }

  let RouteBullet(text:, shape:, color:, text_color:) = bullet

  html.span(
    [
      attribute.class("route-bullet"),
      attribute.class("bullet-" <> bullet_shape_string(shape)),
      attribute.style("--color-bullet-bg", "#" <> color),
      attribute.style("--color-bullet-text", "#" <> text_color),
    ],
    [html.text(text)],
  )
}

pub fn from_route_data(data: st.RouteData) -> RouteBullet {
  // TODO: make this less hacky. maybe pass around separate "diamond express" property?
  // TODO: this fails on the SIR, and would fail if the IBX ever becomes a thing
  let assert Ok(text) = string.first(data.short_name)

  RouteBullet(
    text:,
    shape: st.bullet_shape(data.id),
    color: data.color,
    text_color: data.text_color,
  )
}

fn bullet_shape_decoder() -> decode.Decoder(st.BulletShape) {
  use shape <- decode.then(decode.string)
  case shape {
    "circle" -> decode.success(st.Circle)
    "diamond" -> decode.success(st.Diamond)
    _ -> decode.failure(st.Circle, expected: "BulletShape")
  }
}

fn bullet_shape_string(shape: st.BulletShape) -> String {
  case shape {
    st.Circle -> "circle"
    st.Diamond -> "diamond"
  }
}

pub fn decoder() -> decode.Decoder(RouteBullet) {
  use text <- decode.field("text", decode.string)
  use shape <- decode.field("shape", bullet_shape_decoder())
  use color <- decode.field("color", decode.string)
  use text_color <- decode.field("text_color", decode.string)
  decode.success(RouteBullet(text:, shape:, color:, text_color:))
}

pub fn to_json(bullet: RouteBullet) -> json.Json {
  let RouteBullet(text:, shape:, color:, text_color:) = bullet

  json.object([
    #("text", json.string(text)),
    #("shape", json.string(bullet_shape_string(shape))),
    #("color", json.string(color)),
    #("text_color", json.string(text_color)),
  ])
}
