defmodule Maintenance do
  require Application
  require Logger

  @app_name :maintenance
  # TODO: replace bellow :maintenance with @app when minimum required Elixir version fixes this
  @git_repo_url Application.compile_env(:maintenance, :git_repo_url)
  @data_dir Application.compile_env!(:maintenance, :data_dir)

  @projects Maintenance.Project.list()

  @type project :: Maintenance.Project.t()
  @type job :: MaintenanceJob.t()

  @moduledoc """
  Documentation for `Maintenance`.
  """

  defguard is_project(term) when term in @projects
  defguard is_job(term) when is_atom(term)

  @doc false
  def app_name(), do: @app_name

  @doc false
  def git_repo_url(), do: @git_repo_url

  @doc false
  def data_dir() do
    @data_dir
  end

  @doc false
  def cache_path() do
    data_dir()
    |> Path.join("cache")
  end

  @doc false
  def db_path(project) when is_project(project) do
    data_dir()
    |> Path.join("database")
    |> Path.join(Atom.to_string(project))
  end

  @doc false
  def github_access_token!() do
    case Application.fetch_env(@app_name, :github_access_token) do
      {:ok, github_access_token} ->
        github_access_token

      :error ->
        System.fetch_env!("GITHUB_ACCESS_TOKEN")
    end
  end

  @doc false
  def auth_url("https://" <> rest) do
    github_account = Application.fetch_env!(@app_name, :github_account)
    "https://#{github_account}:" <> github_access_token!() <> "@" <> rest
  end

  @doc """
  Logs `message` with info level.
  """
  def info(message) when is_binary(message) do
    Logger.info(message)
  end

  @doc """
  List projects
  """
  @spec projects() :: nonempty_list(project)
  def projects(), do: @projects

  @doc """
  List jobs for the given `project`.
  """
  @spec jobs(project) :: [job]
  def jobs(project) when is_project(project) do
    with {:ok, modules} <- :application.get_key(:maintenance, :modules) do
      Enum.reduce(modules, [], fn module, acc ->
        with behaviours <-
               module.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten(),
             true <- MaintenanceJob in behaviours,
             true <- apply(module, :implements_project?, [project]),
             job <- apply(module, :job, []) do
          [job | acc]
        else
          _ -> acc
        end
      end)
    end
  end

  @doc """
  Returns the MIX_ENV value, as an atom.
  """
  def env!() do
    Application.fetch_env!(app_name(), :env)
  end
end
