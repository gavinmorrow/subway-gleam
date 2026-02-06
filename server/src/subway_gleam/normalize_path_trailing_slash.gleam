import gleam/option
import gleam/string
import wisp

pub fn normalize_path_trailing_slash(
  req: wisp.Request,
  next: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  case string.ends_with(req.path, "/") {
    True -> next(req)
    False ->
      case req.query {
        option.Some(q) -> wisp.redirect(to: req.path <> "/?" <> q)
        option.None -> wisp.permanent_redirect(to: req.path <> "/")
      }
  }
}
