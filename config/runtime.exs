import Config

github_access_token =
  case config_env() do
    :test -> ""
    _ -> System.fetch_env!("GITHUB_ACCESS_TOKEN")
  end

config :maintenance,
  github_access_token: github_access_token,
  publish?: System.get_env("MAINTENANCE_PUBLISH") in ["1", "true"]
