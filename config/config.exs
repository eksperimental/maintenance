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

config :maintenance, data_dir: Path.join(Path.expand("~"), "maintenance_data")

config :maintenance, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Pull requests are opened inside a fork, never in the upstream project.
# - maintenance-beam is the organization under which repositories are forked.
# - maintenance-beam-app is the user that creates the PRs. The GitHub access token belongs to this user.
config :maintenance,
  git_repo_url: "https://github.com/eksperimental/maintenance",
  author_github_account: "maintenance-beam-app",
  author_name: "Maintenance App",
  author_email: "eksperimental@tutamail.com",
  forks: ["maintenance-beam", "maintenance-beam-app"],
  project_configs: %{
    elixir: %{
      repo: "elixir",
      main_branch: "main",
      owner: "elixir-lang"
    },
    otp: %{
      repo: "otp",
      main_branch: "master",
      owner: "erlang",
      author_name: "Eksperimental",
      author_email: "eksperimental@tutamail.com"
    }
  }

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
