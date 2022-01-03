# Rename this file: config/env.secrets.exs

secret_key_base = "YOUR_SECRET_KEY_BASE"
github_access_token = "YOUR_GITHUB_ACCESS_TOKEN"

import Config

config :maintenance, :secret_key_base, secret_key_base
config :maintenance, :github_access_token, github_access_token

path =
  __DIR__
  |> Path.join("..")
  |> Path.join("env.secrets.sh")
  |> Path.expand()

File.write(path, """
export SECRET_KEY_BASE="#{secret_key_base}"
export GITHUB_ACCESS_TOKEN="#{github_access_token}"
""")
