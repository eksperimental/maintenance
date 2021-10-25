defmodule Maintenance do
  alias Maintenance.{UCD, Project}

  @app_name :maintenance
  @projects [:elixir, :otp]

  @type project :: :elixir | :otp

  @moduledoc """
  Documentation for `Maintenance`.
  """

  defguard is_project(term) when term in @projects

  @doc false
  def app_name(), do: @app_name

  @doc false
  def cache_path() do
    Maintenance.app_name() |> :code.priv_dir() |> Path.join("cache")
  end

  @doc false
  def db_path() do
    Maintenance.app_name() |> :code.priv_dir() |> Path.join("database")
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

  @doc """
  Updates the Unicode in the given `project` by creating a git commit.

  This is the entry point to update the Unicode.
  """
  @spec update(project) :: :ok
  def update(project) when is_project(project) do
    %{
      needs_update?: needs_update?,
      current_unicode_version: _current_unicode_version,
      latest_unicode_version: latest_unicode_version
    } = UCD.calculate_update(project)

    if needs_update? do
      {:ok, contents_ucd} = UCD.get_latest_ucd()
      Project.update(project, latest_unicode_version, contents_ucd)
    else
      :ok
    end
  end

  @doc false
  def github_access_token() do
    Application.fetch_env!(@app_name, :github_access_token)
  end

  @doc false
  def auth_url("https://" <> rest) do
    "https://" <> "eksperimental:" <> github_access_token() <> "@" <> rest
  end
end
