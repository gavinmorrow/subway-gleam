import gleam/http/response
import lustre/attribute
import lustre/element
import lustre/element/html
import wisp

pub type LustreRes(msg) {
  Document(head: List(element.Element(msg)), body: List(element.Element(msg)))
  Body(body: List(element.Element(msg)))
}

pub fn lustre_res(
  req: wisp.Request,
  handle_request: fn(wisp.Request) -> #(LustreRes(msg), wisp.Response),
) -> wisp.Response {
  let #(html, res) = handle_request(req)
  let html = to_html(html)

  response.set_body(
    res,
    html
      |> element.to_document_string
      |> wisp.Text,
  )
}

fn to_html(lustre_res: LustreRes(msg)) -> element.Element(msg) {
  let #(head, body) = case lustre_res {
    Body(body:) -> #([], body)
    Document(head:, body:) -> #(head, body)
  }
  html.html([attribute.lang("en-US")], [
    html.head([], [
      html.meta([attribute.charset("UTF-8")]),
      html.meta([
        attribute.name("viewport"),
        attribute.content("width=device-width, initial-scale=1.0"),
      ]),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href("/static/style.css"),
      ]),
      ..head
    ]),
    html.body([], body),
  ])
}
