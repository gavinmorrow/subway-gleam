import gleam/dict
import gleam/http
import gleam/http/request.{type Request, Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import logging
import subway_gleam/server/time_zone

fn log(
  message: String,
  at level: logging.LogLevel,
  with context: Context,
) -> Nil {
  let now = {
    let now = timestamp.system_time()
    use offset <- result.map(time_zone.new_york_offset(now))

    let #(
      calendar.Date(year:, month:, day:),
      calendar.TimeOfDay(hours:, minutes:, seconds:, nanoseconds: _),
    ) = timestamp.to_calendar(now, offset)

    let year = year |> int.to_string |> string.pad_start(to: 4, with: "0")
    let month =
      month
      |> calendar.month_to_int
      |> int.to_string
      |> string.pad_start(to: 2, with: "0")
    let day = day |> int.to_string |> string.pad_start(to: 2, with: "0")
    let hours = hours |> int.to_string |> string.pad_start(to: 2, with: "0")
    let minutes = minutes |> int.to_string |> string.pad_start(to: 2, with: "0")
    let seconds = seconds |> int.to_string |> string.pad_start(to: 2, with: "0")

    year
    <> "-"
    <> month
    <> "-"
    <> day
    <> " "
    <> hours
    <> ":"
    <> minutes
    <> ":"
    <> seconds
    <> " "
  }
  let now = result.unwrap(now, or: "")

  let message = now <> message <> "\t<< " <> context_to_string(context)
  logging.log(level, message)
}

pub fn emergency(message: String, with context: Context) -> Nil {
  log(message, logging.Emergency, with: context)
}

pub fn alert(message: String, with context: Context) -> Nil {
  log(message, logging.Alert, with: context)
}

pub fn critical(message: String, with context: Context) -> Nil {
  log(message, logging.Critical, with: context)
}

pub fn error(message: String, with context: Context) -> Nil {
  log(message, logging.Error, with: context)
}

pub fn warning(message: String, with context: Context) -> Nil {
  log(message, logging.Warning, with: context)
}

pub fn notice(message: String, with context: Context) -> Nil {
  log(message, logging.Notice, with: context)
}

pub fn info(message: String, with context: Context) -> Nil {
  log(message, logging.Info, with: context)
}

pub fn debug(message: String, with context: Context) -> Nil {
  log(message, logging.Debug, with: context)
}

pub fn request(
  req: Request(req),
  next: fn(Request(req), Context) -> Response(res),
) -> Response(res) {
  let Request(method:, path:, query:, ..) = req

  let id = int.random(0x1_0000_0000) |> int.to_base16
  let context = context([#("req_id", id)])

  log(
    "Handling request",
    at: logging.Info,
    with: context
      |> add_context([
        #("method", method |> http.method_to_string),
        #("path", path),
        #("query", query |> option.unwrap(or: "")),
      ]),
  )

  let res = next(req, context)
  let response.Response(status:, headers: _, body: _) = res

  log(
    "Returning response",
    at: logging.Info,
    with: context |> add_context([#("status", status |> int.to_string)]),
  )

  res
}

pub opaque type Context {
  Context(data: dict.Dict(String, String))
}

pub fn context(data: List(#(String, String))) -> Context {
  Context(data: dict.from_list(data))
}

pub fn new_context() -> Context {
  context([])
}

pub fn add_context(
  into context: Context,
  add pairs: List(#(String, String)),
) -> Context {
  let new_data = dict.from_list(pairs)
  Context(data: dict.merge(new_data, into: context.data))
}

fn context_to_string(context: Context) -> String {
  context.data
  |> dict.to_list
  |> list.map(fn(pair) {
    let #(key, value) = pair
    key <> "=" <> value
  })
  |> string.join(with: "\t")
}
