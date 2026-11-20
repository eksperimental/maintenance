import Config

###########
# Variables

release? = not (!System.get_env("RELEASE_MODE"))
prod_release? = release? and config_env() == :prod

###########
# Configs

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.
if config_env() == :prod do
  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :maintenance, Maintenance.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end

release? = not (!System.get_env("RELEASE_MODE"))
prod_release? = release? and config_env() == :prod

github_access_token =
  case config_env() do
    :test -> ""
    _ -> System.fetch_env!("GITHUB_ACCESS_TOKEN")
  end

config :maintenance,
  prod_release?: prod_release?,
  github_access_token: github_access_token
