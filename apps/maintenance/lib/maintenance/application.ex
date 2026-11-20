defmodule Maintenance.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl Application
  def start(_type, _args) do
    if Maintenance.publish?() do
      Logger.info("Publishing enabled. Jobs push branches and open pull requests.")
    else
      Logger.warning(
        "Publishing disabled. Jobs will not push branches or open pull requests. " <>
          "Set MAINTENANCE_PUBLISH=true to enable it."
      )
    end

    children = [
      # Start a worker by calling: Maintenance.Worker.start_link(arg)
      # {Maintenance.Worker, arg}
      Maintenance.DB,
      {Task.Supervisor, name: Maintenance.TaskSupervisor}
    ]

    options = [strategy: :one_for_one, name: Maintenance.Supervisor]
    Supervisor.start_link(children, options)
  end
end
