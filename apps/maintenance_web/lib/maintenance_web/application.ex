defmodule MaintenanceWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      MaintenanceWeb.Telemetry,
      # Start the Endpoint (http/https)
      MaintenanceWeb.Endpoint
      # Start a worker by calling: MaintenanceWeb.Worker.start_link(arg)
      # {MaintenanceWeb.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MaintenanceWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl Application
  def config_change(changed, _new, removed) do
    MaintenanceWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
