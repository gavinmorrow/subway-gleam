import lustre/attribute
import lustre/element
import lustre/element/html
import subway_gleam/st

pub fn route_bullet(route: st.RouteData) -> element.Element(msg) {
  // TODO: fix diamond expresses so they don't have X in the name
  let route_text = st.route_to_long_id(route.id)

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
