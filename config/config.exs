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

# CRONTAB SCHEDULER
job_on_reboot =
  if config_env() == :prod do
    [{"@reboot", {Maintenance.Runner, :update, []}}]
  else
    []
  end

job_regular =
  if config_env() == :prod do
    [
      # Run every 6 hours
      {"0 */6 * * *", {Maintenance.Runner, :update, []}}
    ]
  else
    []
  end

config :maintenance, MaintenanceJob.Scheduler, jobs: job_on_reboot ++ job_regular
config :maintenance, env: config_env()

config :maintenance, data_dir: Path.join(Path.expand("~"), "maintenance_data")
config :maintenance, data_dir_backup: Path.join(Path.expand("~"), "maintenance_data_backup")

config :maintenance, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

if File.exists?(Path.join(Path.expand(__DIR__), "env.secrets.exs")) do
  import_config "env.secrets.exs"
end

# NOTE:
# - maintenance-beam is the organization under which repositories are forked, and the PRs are created.
# - maintenance-beam-app is the user that create the PRs. The GitHub token access belongs to this user.
#     Also for dev/testing, the repositories are under maintenance-beam-app

owner_upstream = "maintenance-beam"
owner_dev = "maintenance-beam-app"

config :maintenance,
  git_repo_url: "https://github.com/eksperimental/maintenance",
  author_github_account: "maintenance-beam-app",
  author_name: "Maintenance App",
  author_email: "maintenance-beam@autistici.org",
  project_configs: %{
    # beam_langs_meta_data: %{
    #   repo: "beam_langs_meta_data",
    #   main_branch: "main",
    #   owner: %{
    #     origin: "eksperimental",
    #     upstream: owner_upstream,
    #     dev: owner_dev
    #   }
    # },
    # elixir: %{
    #   repo: "elixir",
    #   main_branch: "main",
    #   owner: %{
    #     origin: "elixir-lang",
    #     upstream: owner_upstream,
    #     dev: owner_dev
    #   }
    # },
    otp: %{
      repo: "otp",
      main_branch: "master",
      owner: %{
        origin: "erlang",
        upstream: owner_upstream,
        dev: owner_dev
      },
      author_name: "Eksperimental",
      author_email: "eksperimental@autistici.org"
    }
    # sample_project: %{
    #   repo: "sample_project",
    #   main_branch: "main",
    #   owner: %{
    #     origin: "maintenance-beam",
    #     upstream: owner_upstream,
    #     dev: owner_dev
    #   }
    # }
  }

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
