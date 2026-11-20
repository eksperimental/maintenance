import Config

# Print only warnings and errors during test
config :logger, level: :warn

# In test we don't send emails.
config :maintenance, Maintenance.Mailer, adapter: Swoosh.Adapters.Test
