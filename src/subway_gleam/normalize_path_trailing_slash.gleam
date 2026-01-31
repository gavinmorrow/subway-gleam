import gleam/string
import wisp

pub fn normalize_path_trailing_slash(
  req: wisp.Request,
  next: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  case string.ends_with(req.path, "/") {
    True -> next(req)
    False -> wisp.permanent_redirect(to: req.path <> "/")
  }
}
