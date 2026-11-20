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

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :maintenance, env: config_env()

config :maintenance, data_dir: Path.join(Path.expand("~"), "maintenance_data")
config :maintenance, data_dir_backup: Path.join(Path.expand("~"), "maintenance_data_backup")

config :maintenance, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

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
  author_email: "eksperimental@tutamail.com",
  project_configs: %{
    elixir: %{
      repo: "elixir",
      main_branch: "main",
      owner: %{
        origin: "elixir-lang",
        upstream: owner_upstream,
        dev: owner_dev
      }
    },
    otp: %{
      repo: "otp",
      main_branch: "master",
      owner: %{
        origin: "erlang",
        upstream: owner_upstream,
        dev: owner_dev
      },
      author_name: "Eksperimental",
      author_email: "eksperimental@tutamail.com"
    }
  }

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
