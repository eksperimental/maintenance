defmodule Maintenance.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      Maintenance.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Maintenance.PubSub}
      # Start a worker by calling: Maintenance.Worker.start_link(arg)
      # {Maintenance.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Maintenance.Supervisor)
  end
end
