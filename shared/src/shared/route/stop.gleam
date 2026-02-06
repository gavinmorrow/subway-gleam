import gleam/time/duration
import gleam/time/timestamp
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub fn view(
  name name: String,
  last_updated last_updated,
  transfers transfers,
  alert_summary alert_summary,
  uptown uptown,
  downtown downtown,
) -> Element(msg) {
  html.div([], [
    html.h1([], [
      html.text(name),
    ]),
    html.aside([], [
      html.text(
        "Last updated "
        <> { last_updated |> timestamp.to_rfc3339(duration.hours(-4)) },
      ),
    ]),
    html.aside([], [html.text("Transfer to:"), ..transfers]),
    html.aside([], [
      html.a([attribute.href("./alerts")], [html.text(alert_summary)]),
    ]),
    html.h2([], [html.text("Uptown")]),
    html.ul([attribute.class("arrival-list")], uptown),
    html.h2([], [html.text("Downtown")]),
    html.ul([attribute.class("arrival-list")], downtown),
  ])
}
