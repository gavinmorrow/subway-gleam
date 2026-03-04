import envoy
import gleam/json
import gleam/result
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
      [],
      "globalThis.process = { env: { "
        <> "gtfs_rt: '"
        <> envoy.get("gtfs_rt") |> result.unwrap(or: "undefined")
        <> "', gtfs_rt_fetch_time: '"
        <> envoy.get("gtfs_rt_fetch_time") |> result.unwrap(or: "undefined")
        <> "' } };",
    ),
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
