import gleam/pgo
import gleam/io
import gleam/string
import gleam/list
import gleam/regex
import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/option.{Some}
import wisp.{type Response}

pub fn db() {
  pgo.Config(
    ..pgo.default_config(),
    port: 5433,
    host: "localhost",
    database: "currency_exchange",
    user: "postgres",
    password: Some("postgres"),
    pool_size: 15,
  )
  |> pgo.connect()
}

pub fn wrap_json_error_response(err) {
  io.debug(err)
  json_empty_response(response_type: "error")
}

pub fn json_empty_response(response_type r_type: String) {
  case r_type {
    "empty_object" -> json_error_response_empty_object()
    "empty_array" -> json_error_response_empty_array()
    _ -> json_response_error("")
  }
}

pub fn json_response_error(err: String) -> Response {
  case err {
    "" -> [#("data", json.string("Error with service"))]
    _ -> [#("data", json.string(err))]
  }
  |> json_builder(422)
}

pub fn json_response_success() -> Response {
  [#("data", json.string("Action completed successfully"))]
  |> json_builder(200)
}

pub fn validate_required_fields(
  fields: Dict(String, String),
  req_fields: List(String),
) -> List(String) {
  let null_errors = check_null_fields(fields, req_fields)
  let empty_fields_errors = {
    fields
    |> dict.filter(fn(_key, value) { value == "" })
    |> dict.fold([], fn(acc, key, _value) {
      list.prepend(acc, key <> " cannot be empty")
    })
  }
  list.concat([null_errors, empty_fields_errors])
}

fn check_null_fields(
  fields: Dict(String, String),
  req_fields: List(String),
) -> List(String) {
  req_fields
  |> list.filter(fn(ele) {
    fields
    |> dict.keys()
    |> list.contains(any: ele)
    == False
  })
  |> list.map(fn(ele) { ele <> " is a required field" })
}

pub fn validate_length(
  err_result: List(String),
  fields: Dict(String, String),
  k: String,
  len_dir: String,
  val: Int,
) -> List(String) {
  let res =
    fields
    |> dict.filter(fn(key, value) {
      case len_dir {
        "min" -> {
          key == k && string.length(value) < val
        }
        _ -> {
          key == k && string.length(value) > val
        }
      }
    })
    |> dict.fold([], fn(acc, key, _value) {
      case len_dir {
        "min" -> list.prepend(acc, key <> " cannot be of length less than 5")
        _ -> list.prepend(acc, key <> " cannot be of length more than 8")
      }
    })
  list.concat([err_result, res])
}

pub fn check_reqex(
  err_result: List(String),
  fields: Dict(String, String),
  k: String,
  regexpr: String,
  err_msg: String,
) -> List(String) {
  let res =
    fields
    |> dict.filter(fn(key, value) {
      key == k
      && {
        let assert Ok(re) = regex.from_string(regexpr)
        regex.check(re, value)
      }
    })
  let res_size = dict.size(res)
  case res_size {
    res_size if res_size > 0 -> list.concat([err_result, [err_msg]])
    _ -> err_result
  }
}

pub fn halt() {
  panic as "testing--"
}

pub fn json_error_response_array(arr) -> Response {
  [#("data", json.array(from: arr, of: json.string))]
  |> json_builder(200)
}

fn json_error_response_empty_object() -> Response {
  [#("data", json.object([]))]
  |> json_builder(200)
}

fn json_error_response_empty_array() -> Response {
  [#("data", json.array([], fn(empty) { empty }))]
  |> json_builder(200)
}

fn json_builder(object: List(#(String, Json)), code: Int) {
  object
  |> json.object()
  |> json.to_string_builder()
  |> wisp.json_response(code)
}
