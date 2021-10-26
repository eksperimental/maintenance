import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :maintenance_web, MaintenanceWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "dHhRR7KdA2GbGm3nQYee1Kiv4qVu7Nxd17vHKpJXf4L/8KN069SSp5MjB/Ps915u",
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

# In test we don't send emails.
config :maintenance, Maintenance.Mailer, adapter: Swoosh.Adapters.Test

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
