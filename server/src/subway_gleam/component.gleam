import gleam/string
import lustre/attribute
import lustre/element
import lustre/element/html
import subway_gleam/st

pub fn route_bullet(route: st.RouteData) -> element.Element(msg) {
  let route_text = st.route_to_long_id(route.id)
  // TODO: make this less hacky. maybe pass around separate "diamond express" property?
  let assert Ok(route_text) = string.first(route_text)

  let shape = case st.bullet_shape(for: route.id) {
    st.Circle -> "circle"
    st.Diamond -> "diamond"
  }

  html.span(
    [
      attribute.class("route-bullet"),
      attribute.class("bullet-" <> shape),
      attribute.style("--color-bullet-bg", "#" <> route.color),
      attribute.style("--color-bullet-text", "#" <> route.text_color),
    ],
    [html.text(route_text)],
  )
}
