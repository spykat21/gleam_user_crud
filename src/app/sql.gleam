pub fn list_all(
  accepts_arguments with_vals: Bool,
  table table: String,
) -> String {
  case with_vals {
    False -> "SELECT * FROM " <> table

    True -> "SELECT * FROM " <> table <> " WHERE id = $1"
  }
}

pub fn find(
  colum cols: String,
  table table: String,
  where cond_str: String,
) -> String {
  "SELECT " <> cols <> " FROM " <> table <> " WHERE " <> cond_str
}

pub fn insert(
  colums cols: String,
  values vals: String,
  tbl table: String,
) -> String {
  "INSERT INTO " <> table <> " (" <> cols <> ") VALUES  (" <> vals <> ")"
}

pub fn update(
  set set_str: String,
  where where_str: String,
  table table_str: String,
) -> String {
  "UPDATE " <> table_str <> " SET " <> set_str <> " WHERE " <> where_str <> " "
}
