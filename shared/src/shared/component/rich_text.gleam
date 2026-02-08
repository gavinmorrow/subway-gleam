import lustre/element

import subway_gleam/gtfs/rt/rich_text

pub fn as_html(rich_text: rich_text.RichText) -> element.Element(msg) {
  let rich_text.RichText(raw_html:) = rich_text
  element.unsafe_raw_html("", "div", [], raw_html)
}
