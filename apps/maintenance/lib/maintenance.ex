defmodule Maintenance do
  @app_name :maintenance

  @projects [:elixir, :otp]
  @jobs [:unicode]

  @type project :: :elixir | :otp
  @type job :: atom

  @moduledoc """
  Documentation for `Maintenance`.
  """

  defguard is_project(term) when term in @projects
  defguard is_job(term) when term in @jobs

  @doc false
  def app_name(), do: @app_name

  @doc false
  def git_repo_url(), do: Application.get_env(@app_name, :git_repo_url)

  @doc false
  def cache_path() do
    Maintenance.app_name() |> :code.priv_dir() |> Path.join("cache")
  end

  @doc false
  def db_path(project) when is_project(project) do
    Maintenance.app_name()
    |> :code.priv_dir()
    |> Path.join("database")
    |> Path.join(Atom.to_string(project))
  end

  @doc false
  def github_access_token() do
    Application.fetch_env!(@app_name, :github_access_token)
  end

  @doc false
  def auth_url("https://" <> rest) do
    github_account = Application.fetch_env!(@app_name, :github_account)
    "https://#{github_account}:" <> github_access_token() <> "@" <> rest
  end

  @doc """
  List projects
  """
  def projects() do
    @projects
  end

  @doc """
  List jobs
  """
  def jobs() do
    @jobs
  end

  @doc """
  Returns the MIX_ENV value, as an atom.
  """
  def env!() do
    Application.fetch_env!(app_name(), :env)
  end
end
