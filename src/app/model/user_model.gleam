import gleam/dynamic.{type Dynamic}

pub type User {
  User(id: String, name: String, username: String, password: String)
}

pub fn decode_user_from_json(
  json: Dynamic,
) -> Result(User, dynamic.DecodeErrors) {
  let decoder =
    dynamic.decode4(
      User,
      dynamic.field("id", dynamic.string),
      dynamic.field("name", dynamic.string),
      dynamic.field("username", dynamic.string),
      dynamic.field("password", dynamic.string),
    )
  decoder(json)
}

pub fn decode_user_from_pg(recs: #(String, String, String, String)) -> User {
  User(id: recs.0, name: recs.1, username: recs.2, password: recs.3)
}

pub fn pg_to_4list_strings() {
  dynamic.tuple4(dynamic.string, dynamic.string, dynamic.string, dynamic.string)
}
