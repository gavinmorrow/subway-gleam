import lustre/attribute
import lustre/element
import lustre/element/html

pub fn route_bullet(route_id: String) -> element.Element(msg) {
  html.span([attribute.class("route-bullet")], [html.text(route_id)])
}
