defmodule Maintenance.Project do
  @moduledoc """
  Module that contains the specific code for updating each project.
  """

  alias Maintenance.DB

  # Add new projects here
  @type t :: :sample_project | :elixir | :otp | :beam_langs_meta_data

  @typep remote :: :origin | :upstream

  defguardp is_project(term) when is_atom(term)

  @doc """
  Returns the configuration key-values for `project`.
  """
  @spec config(Maintenance.project()) :: map()
  def config(project) do
    project_configs = Application.fetch_env!(:maintenance, :project_configs)

    Map.fetch!(project_configs, project)
  end

  @spec config(Maintenance.project(), atom()) :: any()
  def config(project, key) when is_project(project) and is_atom(key) do
    project
    |> config()
    |> Map.fetch!(key)
  end

  @spec list_entries_by_job(Maintenance.project(), Maintenance.job()) :: any()
  def list_entries_by_job(project, job) when is_project(project) and is_atom(job) do
    # {:ok, result} = DB.select(project, min_key: {job, 0}, reverse: true, pipe: [reduce: fn ])
    {:ok, results} = DB.select(project, reverse: true)

    Enum.filter(results, fn
      {{^job, _}, _v} -> true
      {^job, _v} -> true
      _other -> false
    end)
  end

  @spec list() :: [Maintenance.project()]
  def list() do
    project_configs = Application.fetch_env!(:maintenance, :project_configs)

    Map.keys(project_configs)
  end

  @doc """
  Returns the git_url from `config/0` based on whether the app
  is running in full production mode or not.
  """
  @spec get_git_url(t() | map(), remote) :: String.t()
  def get_git_url(project_or_config, remote)

  def get_git_url(project, remote) when is_project(project) do
    config = config(project)

    get_git_url(config, remote)
  end

  def get_git_url(config, remote) when is_map(config) and remote in [:upstream, :origin] do
    if Maintenance.prod_release?() do
      "https://github.com/#{config.owner.origin}/#{config.repo}"
    else
      owner = Map.get(config.owner, remote)

      "https://github.com/#{owner}/#{config.repo}"
    end
  end

  @doc """
  Returns the project owner from `config/0` based on whether the app
  is running in full production mode or not.
  """
  @spec get_owner(t() | map(), remote) :: String.t()
  def get_owner(project_or_config, remote)

  def get_owner(project, remote) when is_project(project) do
    config = config(project)

    get_owner(config, remote)
  end

  def get_owner(config, remote) when is_map(config) and remote in [:origin, :upstream] do
    if Maintenance.prod_release?() do
      config.owner.origin
    else
      Map.get(config.owner, remote)
    end
  end
end
