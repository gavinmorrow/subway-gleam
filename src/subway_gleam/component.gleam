import lustre/attribute
import lustre/element
import lustre/element/html
import subway_gleam/st

pub fn route_bullet(route: st.Route) -> element.Element(msg) {
  // TODO: fix diamond expresses so they don't have X in the name
  let route_text = st.route_to_long_id(route)

  let shape = case st.bullet_shape(for: route) {
    st.Circle -> "circle"
    st.Diamond -> "diamond"
  }

  html.span(
    [
      attribute.class("route-bullet"),
      attribute.class("bullet-" <> shape),
    ],
    [html.text(route_text)],
  )
}
