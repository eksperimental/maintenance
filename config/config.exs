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

config :maintenance, :git_repo_url, "https://github.com/eksperimental/maintenance"

config :maintenance, :author_github_account, "maintenance-beam-app"
config :maintenance, :author_name, "Maintenance App"
config :maintenance, :author_email, "maintenance-beam@autistici.org"

# CRONTAB SCHEDULER
job_on_reboot =
  if config_env() == :prod do
    [{"@reboot", {Maintenance.Runner, :update, []}}]
  else
    []
  end

config :maintenance, MaintenanceJob.Scheduler,
  jobs:
    job_on_reboot ++
      [
        # Run every 6 hours
        {"0 */6 * * *", {Maintenance.Runner, :update, []}}
      ]

config :maintenance, env: config_env()

config :maintenance, data_dir: Path.join(Path.expand("~"), "maintenance_data")
config :maintenance, data_dir_backup: Path.join(Path.expand("~"), "maintenance_data_backup")

config :maintenance, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

full_production? =
  case System.get_env("MAINTENANCE_FULL_PRODUCTION") do
    "yes" ->
      true

    "no" ->
      false

    nil ->
      false

    _ ->
      raise(
        "Only \"yes\" and \"not\" are accepted values for Env variable MAINTENANCE_FULL_PRODUCTION"
      )
  end

config :maintenance, :full_production?, full_production?

config_path =
  __DIR__
  |> Path.join("..")
  |> Path.join("config.sh")
  |> Path.expand()

unless File.exists?(config_path) do
  File.write(config_path, """
  # NOTE: Set this to "yes" when in production server and no more testing is done.
  export MAINTENANCE_FULL_PRODUCTION="no"
  """)
end

File.chmod!(config_path, 0o755)

if File.exists?(Path.join(Path.expand(__DIR__), "env.secrets.exs")) do
  import_config "env.secrets.exs"
end

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
