import gleam/json
import lustre/attribute
import lustre/element
import lustre/element/html

const script_root = "/static/"

pub fn hydration_scripts(
  module_name: String,
  model: json.Json,
) -> element.Element(msg) {
  element.fragment([
    html.script(
      [attribute.type_("application/json"), attribute.id("model")],
      json.to_string(model),
    ),
    html.script(
      [
        attribute.type_("module"),
        attribute.src(script_root <> module_name <> ".js"),
      ],
      "",
    ),
  ])
}
