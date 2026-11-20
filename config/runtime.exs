import Config

config :maintenance, publish?: System.get_env("MAINTENANCE_PUBLISH") in ["1", "true"]
