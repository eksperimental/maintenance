defmodule Maintenance do
  @moduledoc """
  Documentation for `Maintenance`.
  """

  require Application
  require Logger

  @app_name :maintenance
  # TODO: replace bellow :maintenance with @app when minimum required Elixir version fixes this
  @git_repo_url Application.compile_env(:maintenance, :git_repo_url)
  @data_dir Application.compile_env!(:maintenance, :data_dir)

  @type project :: Maintenance.Project.t()
  @type job :: MaintenanceJob.t()

  defguard is_job(term) when is_atom(term)

  defguard is_project(term) when is_atom(term)

  @doc false
  @spec app_name() :: atom()
  def app_name(), do: @app_name

  @doc false
  @spec git_repo_url() :: String.t()
  def git_repo_url(), do: @git_repo_url

  @doc false
  @spec data_dir() :: String.t()
  def data_dir(), do: @data_dir

  @doc false
  @spec cache_path() :: String.t()
  def cache_path() do
    Path.join(data_dir(), "cache")
  end

  @doc false
  @spec db_path(Maintenance.Project.t()) :: String.t()
  def db_path(project) when is_project(project) do
    data_dir()
    |> Path.join("database")
    |> Path.join(Atom.to_string(project))
  end

  @doc false
  @spec author_email() :: String.t()
  def author_email(), do: Application.fetch_env!(@app_name, :author_email)

  @spec author_github_account() :: String.t()
  def author_github_account(), do: Application.fetch_env!(@app_name, :author_github_account)

  @spec author_name() :: String.t()
  def author_name(), do: Application.fetch_env!(@app_name, :author_name)

  @doc false
  @spec auth_url(String.t()) :: String.t()
  def auth_url("https://" <> rest) do
    "https://" <> author_github_account() <> ":" <> github_access_token!() <> "@" <> rest
  end

  @doc false
  @spec github_access_token!() :: String.t()
  def github_access_token!(), do: Application.fetch_env!(@app_name, :github_access_token)

  @doc """
  List projects
  """
  @spec projects() :: nonempty_list(project)
  def projects(), do: Maintenance.Project.list()

  @doc """
  List jobs for the given `project`.
  """
  @spec jobs(project) :: [job]
  def jobs(project) when is_project(project) do
    with {:ok, modules} <- :application.get_key(:maintenance, :modules) do
      Enum.reduce(modules, [], fn module, acc ->
        with behaviours <- list_behaviours(module),
             true <- MaintenanceJob in behaviours,
             true <- module.implements_project?(project),
             job <- module.job() do
          [job | acc]
        else
          _other -> acc
        end
      end)
    end
  end

  defp list_behaviours(module) do
    attributes = module.module_info(:attributes)

    attributes
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  # Public helpers

  @doc """
  Returns the MIX_ENV value, as an atom.
  """
  @spec env!() :: atom()
  def env!() do
    Application.fetch_env!(@app_name, :env)
  end
end
