import wisp.{type Request, type Response}
import gleam/string_builder
import app/middleware
import app/controller/user

pub fn handle_request(req: Request) -> Response {
  use req <- middleware.setup(req)
  let segments = wisp.path_segments(req)
  case segments {
    [] -> {
      let html = string_builder.from_string("Welcome Home....")
      wisp.ok()
      |> wisp.html_body(html)
    }

    ["users", ..] -> user.controller(req, segments)

    _ -> wisp.not_found()
  }
}
