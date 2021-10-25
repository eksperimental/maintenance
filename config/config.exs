# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

# Configure Mix tasks and generators
config :maintenance,
  ecto_repos: [Maintenance.Repo]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :maintenance, Maintenance.Mailer, adapter: Swoosh.Adapters.Local

# Swoosh API client is needed for adapters other than SMTP.
config :swoosh, :api_client, false

config :maintenance_web,
  ecto_repos: [Maintenance.Repo],
  generators: [context_app: :maintenance]

# Configures the endpoint
config :maintenance_web, MaintenanceWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: MaintenanceWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Maintenance.PubSub,
  live_view: [signing_salt: "ZLNdKdGy"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.12.18",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2016 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/maintenance_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :tentacat, :extra_headers, [{"Accept", "application/vnd.github.black-cat-preview+json"}]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "env.local.exs"
import_config "#{config_env()}.exs"