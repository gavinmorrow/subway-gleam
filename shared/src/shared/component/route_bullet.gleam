import lustre/attribute
import lustre/element
import lustre/element/html

pub type RouteBullet {
  RouteBullet(
    text: String,
    shape: BulletShape,
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

pub type BulletShape {
  Circle
  Diamond
}

fn bullet_shape_string(shape: BulletShape) -> String {
  case shape {
    Circle -> "circle"
    Diamond -> "diamond"
  }
}
