import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub fn navbar() -> Element(msg) {
  html.nav([attribute.id("navbar")], [
    html.a([attribute.href("/stops")], [html.text("Stops")]),
    html.a([attribute.href("/map")], [html.text("Map")]),
  ])
}
