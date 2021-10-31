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
    Maintenance.app_name() |> :code.priv_dir() |> Path.join("database") |> Path.join(Atom.to_string(project))
  end

  @doc """
  Returns the default configuration values for `project`.
  """
  def default(project)

  def default(:elixir) do
    %{
      owner: "eksperimental-dev",
      repo: "elixir",
      git_repo_url: "https://github.com/elixir-lang/elixir",
      forked_git_repo_url: "https://github.com/eksperimental/elixir",
      dev_git_repo_url: "https://github.com/eksperimental-dev/elixir",
      main_branch: "master"
    }
  end

  def default(:otp) do
    %{
      owner: "eksperimental-dev",
      repo: "otp",
      git_repo_url: "https://github.com/erlang/otp",
      forked_git_repo_url: "https://github.com/eksperimental/otp",
      dev_git_repo_url: "https://github.com/eksperimental-dev/otp",
      main_branch: "master",
      regex_gen_unicode_version:
        ~r/(spec_version\(\)\s+->\s+\{)((?<major>\d+),(?<minor>\d+)(,(?<patch>\d+))?)(\}\.\\n)/
    }
  end

  def default(project, key) when is_project(project) and is_atom(key) do
    default(project) |> Map.fetch!(key)
  end

  @doc false
  def github_access_token() do
    Application.fetch_env!(@app_name, :github_access_token)
  end

  @doc false
  def auth_url("https://" <> rest) do
    "https://" <> "eksperimental:" <> github_access_token() <> "@" <> rest
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
end
