import wisp.{type Request, type Response}
import gleam/io
import gleam/pgo.{type Connection, type QueryError, ConstraintViolated}
import gleam/string_builder
import gleam/string
import gleam/dynamic.{type DecodeError, type Dynamic}
import gleam/dict.{type Dict}
import gleam/http.{Delete, Get, Post, Put}
import gleam/list
import gleam/result
import app/model/user_model
import app/elx_ffi/bcrypt.{hash_password, verify_password_hash}
import app/view/user_json
import app/util.{db}
import app/sql

pub fn controller(req: Request, segments: List(String)) {
  let tbl = "tbl_user"
  let base_url = "users"
  let db = db()
  let allowed_methods = [Get, Post, Put, Post]
  let method = req.method
  let segments = segments
  io.debug(segments)
  case method {
    Get -> {
      case segments {
        [base_url] -> list(db, tbl)
        [base_url, id] -> show(db, id, tbl)
        _ -> wisp.not_found()
      }
    }
    Post ->
      case segments {
        [base_url] -> add(req, db, tbl)
        [base_url, "login"] -> login(req, db, tbl)
        _ -> wisp.not_found()
      }

    Put ->
      case segments {
        [base_url, id] -> update(req, id, db, tbl)
        [base_url, "reset_password", id] -> reset_password(req, id, db, tbl)
        _ -> wisp.not_found()
      }
    Delete -> delete(req)
    _ -> wisp.method_not_allowed(allowed_methods)
  }
}

fn add(req: Request, db: Connection, tbl: String) -> Response {
  use json <- wisp.require_json(req)
  let dict_map_res = parse_req_body_to_dict_map(json)
  case dict_map_res {
    Ok(map) -> {
      let validate_errors = validate_fields(map)
      case validate_errors {
        [] -> {
          //Create a query string from the values
          let insert_str_fold = {
            dict.fold(map, "'", fn(acc, key, value) {
              case key {
                "password" -> acc <> hash_password(value) <> "', '"
                _ -> acc <> value <> "', '"
              }
            })
            |> string.drop_right(up_to: 3)
          }
          let res = {
            map
            |> dict.keys
            |> string.join(",")
            //Excute Sql insert with the keys as colums values as the first argument
            |> sql.insert(values: insert_str_fold, tbl: tbl)
            |> pgo.execute(db, [], dynamic.dynamic)
          }
          pgo.disconnect(db)
          case res {
            Ok(_response) -> {
              util.json_response_success()
            }

            Error(ConstraintViolated(message, constraint, _detail)) -> {
              //Adding debugging here for constraint errors
              io.debug(message)
              constraint
              |> string.split("_")
              |> list.first()
              |> result.map(fn(ele) { ele <> " already exists" })
              |> result.unwrap("")
              |> util.json_response_error()
            }

            Error(err) -> {
              util.wrap_json_error_response(err)
            }
          }
        }
        _ -> {
          util.json_error_response_array(validate_errors)
        }
      }
    }

    Error(err) -> {
      util.wrap_json_error_response(err)
    }
  }
}

fn show(db: Connection, id: String, tbl: String) -> Response {
  let result = {
    sql.list_all(accepts_arguments: True, table: tbl)
    |> pgo.execute(db, [pgo.text(id)], user_model.pg_to_4list_strings())
  }
  pgo.disconnect(db)
  case result {
    Ok(result) -> {
      result.rows
      |> list.map(fn(recs) {
        recs
        |> user_model.decode_user_from_pg
      })
      |> list.at(0)
      |> result.map(user_json.show)
      |> result.unwrap(util.json_empty_response(response_type: "empty_object"))
    }
    Error(err) -> {
      util.wrap_json_error_response(err)
    }
  }
}

fn list(db: Connection, tbl: String) {
  let result = {
    sql.list_all(accepts_arguments: False, table: tbl)
    |> pgo.execute(db, [], user_model.pg_to_4list_strings())
  }
  pgo.disconnect(db)
  case result {
    Ok(result) -> {
      let recs =
        result.rows
        |> list.map(fn(recs) {
          recs
          |> user_model.decode_user_from_pg
        })
      case list.is_empty(recs) {
        True -> util.json_empty_response(response_type: "empty_array")
        False -> user_json.list(recs)
      }
    }

    Error(err) -> {
      util.wrap_json_error_response(err)
    }
  }
}

fn update(req: Request, id: String, db: Connection, tbl: String) -> Response {
  use json <- wisp.require_json(req)
  let dict_map_res = parse_req_body_to_dict_map(json)
  case dict_map_res {
    Ok(map) -> {
      let validate_errors = validate_fields_update(map)
      case validate_errors {
        [] -> {
          //Create a query string from the values
          let res =
            {
              dict.fold(map, "", fn(acc, key, value) {
                acc <> key <> " = '" <> value <> "'"
              })
            }
            |> sql.update(where: "id = $1", table: tbl)
            |> pgo.execute(db, [pgo.text(id)], dynamic.dynamic)
          pgo.disconnect(db)
          case res {
            Ok(_response) -> {
              util.json_response_success()
            }

            Error(err) -> {
              util.wrap_json_error_response(err)
            }
          }
        }
        _ -> {
          util.json_error_response_array(validate_errors)
        }
      }
    }

    Error(err) -> {
      util.wrap_json_error_response(err)
    }
  }
}

fn reset_password(
  req: Request,
  id: String,
  db: Connection,
  tbl: String,
) -> Response {
  let find_user_and_compare_old_password = fn(old_password: String) -> Result(
    String,
    QueryError,
  ) {
    let res_find_user = {
      sql.list_all(accepts_arguments: True, table: tbl)
      |> pgo.execute(db, [pgo.text(id)], user_model.pg_to_4list_strings())
    }
    case res_find_user {
      Ok(res_find_user) -> {
        case res_find_user.rows {
          [] -> Ok("user-not-found")
          _ -> {
            let res = {
              res_find_user.rows
              |> list.map(fn(rec) {
                rec
                |> user_model.decode_user_from_pg
              })
              |> list.at(0)
              |> result.map(fn(user) {
                old_password
                |> verify_password_hash(user.password)
              })
            }
            //Wiered hack to get the function to return Ok(Bool)
            case res {
              res if res == Ok(True) -> Ok("True")
              _ -> Ok("invalid-password")
            }
          }
        }
      }
      Error(err) -> {
        Error(err)
      }
    }
  }
  use json <- wisp.require_json(req)
  let dict_map_res = parse_req_body_to_dict_map(json)
  case dict_map_res {
    Ok(map) -> {
      let validate_errors = validate_fields_reset_pass(map)
      case validate_errors {
        [] -> {
          // Had to use unwrap .. result map works .. result map_error giving a wiered feedback
          let old_password = result.unwrap(dict.get(map, "old_password"), "")
          case find_user_and_compare_old_password(old_password) {
            Ok("True") -> {
              let new_map = dict.delete(map, "old_password")
              let res =
                {
                  dict.fold(new_map, "", fn(acc, _key, value) {
                    acc <> " password = '" <> hash_password(value) <> "'"
                  })
                }
                |> sql.update(where: "id = $1", table: tbl)
                |> pgo.execute(db, [pgo.text(id)], dynamic.dynamic)
              pgo.disconnect(db)
              case res {
                Ok(_response) -> {
                  util.json_response_success()
                }

                Error(err) -> {
                  util.wrap_json_error_response(err)
                }
              }
            }
            Ok("user-not-found") -> {
              util.json_response_error("User not found")
            }
            Ok("invalid-password") -> {
              util.json_response_error("Old password is invalid")
            }
            Error(err) -> {
              util.wrap_json_error_response(err)
            }
            _ -> {
              util.json_response_error("User not found")
            }
          }
        }

        _ -> {
          util.json_error_response_array(validate_errors)
        }
      }
    }
    Error(err) -> {
      util.wrap_json_error_response(err)
    }
  }
}

fn delete(req: Request) -> Response {
  let html = string_builder.from_string("Delete user")
  wisp.ok()
  |> wisp.html_body(html)
}

fn login(req: Request, db: Connection, tbl: String) {
  use json <- wisp.require_json(req)
  let dict_map_res = parse_req_body_to_dict_map(json)
  case dict_map_res {
    Ok(map) -> {
      let validate_errors = validate_fields_login(map)
      case validate_errors {
        [] -> {
          let username = result.unwrap(dict.get(map, "username"), "")
          let password = result.unwrap(dict.get(map, "password"), "")
          let res_find_user =
            sql.find(colum: "*", where: "username = $1", table: tbl)
            |> pgo.execute(
              db,
              [pgo.text(username)],
              user_model.pg_to_4list_strings(),
            )
          pgo.disconnect(db)
          case res_find_user {
            Ok(response) -> {
              case response.rows {
                [] -> util.json_response_error("Invalid login credentials")

                _ -> {
                  let recs =
                    response.rows
                    |> list.map(fn(rec) {
                      rec
                      |> user_model.decode_user_from_pg
                    })
                    |> list.at(0)
                  let is_valid_credentials =
                    recs
                    |> result.map(fn(user) {
                      password
                      |> verify_password_hash(user.password)
                    })
                  //Wiered hack to get the function to return Ok(Bool)
                  case is_valid_credentials {
                    res if res == Ok(True) ->
                      recs
                      |> result.map(user_json.show)
                      |> result.unwrap(util.json_response_error(
                        "Invalid login credentials",
                      ))
                    _ -> util.json_response_error("Invalid login credentials")
                  }
                }
              }
            }
            Error(err) -> {
              util.wrap_json_error_response(err)
            }
          }
        }

        _ -> {
          util.json_error_response_array(validate_errors)
        }
      }
    }
    Error(err) -> {
      util.wrap_json_error_response(err)
    }
  }
}

fn validate_fields(fields: Dict(String, String)) -> List(String) {
  fields
  |> util.validate_required_fields(["username", "password", "name"])
  |> util.validate_length(fields, "username", "min", 5)
  |> util.validate_length(fields, "username", "max", 8)
  |> util.check_reqex(fields, "username", "^(.*\\s+.*)+$", "invalid username")
}

fn validate_fields_update(fields: Dict(String, String)) -> List(String) {
  fields
  |> util.validate_required_fields(["name"])
}

fn validate_fields_reset_pass(fields: Dict(String, String)) -> List(String) {
  fields
  |> util.validate_required_fields(["old_password", "new_password"])
}

fn validate_fields_login(fields: Dict(String, String)) -> List(String) {
  fields
  |> util.validate_required_fields(["username", "password"])
}

fn parse_req_body_to_dict_map(
  json: Dynamic,
) -> Result(Dict(String, String), List(DecodeError)) {
  let dict_list = {
    json
    |> dynamic.from()
    |> dynamic.dict(dynamic.string, dynamic.string)
  }
  {
    use map <- result.try(dict_list)
    map
    |> Ok
  }
}
