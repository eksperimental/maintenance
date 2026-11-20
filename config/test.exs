import Config

# Print only warnings and errors during test
config :logger, level: :warning

# Keep test repositories away from the real cache in ~/maintenance_data.
config :maintenance, data_dir: Path.expand("../_build/test/maintenance_data", __DIR__)

# In test we don't send emails.
config :maintenance, Maintenance.Mailer, adapter: Swoosh.Adapters.Test

# Route GitHub API requests to Req.Test stubs.
config :maintenance, :github_req_options, plug: {Req.Test, Maintenance.Github}
