@external(erlang, "Elixir.Bcrypt", "hash_pwd_salt")
pub fn hash_password(password: String) -> String

@external(erlang, "Elixir.Bcrypt", "verify_pass")
pub fn verify_password_hash(password: String, hash: String) -> Bool
