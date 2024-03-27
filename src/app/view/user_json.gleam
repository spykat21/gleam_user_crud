import gleam/json.{type Json}
import wisp.{type Response}
import gleam/list
import app/model/user_model.{type User}

pub fn list(users: List(User)) -> Response {
  [
    #(
      "data",
      json.array(users, fn(user) { data(user, ignore_fields: ["password"]) }),
    ),
  ]
  |> json_response()
}

pub fn show(user: User) {
  [#("data", data(user, []))]
  |> json_response()
}

fn data(user: User, ignore_fields fields: List(String)) {
  [
    #("id", json.string(user.id)),
    #("name", json.string(user.name)),
    #("username", json.string(user.username)),
    #("password", json.string(user.password)),
  ]
  |> list.filter(fn(ele) {
    fields
    |> list.contains(any: ele.0)
    == False
  })
  |> json.object()
}

fn json_response(response_object: List(#(String, Json))) -> Response {
  response_object
  |> json.object()
  |> json.to_string_builder()
  |> wisp.json_response(200)
}
