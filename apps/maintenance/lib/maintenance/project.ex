defmodule Maintenance.Project do
  @moduledoc """
  Module that contains the specific code for updating each project.
  """

  # Add new projects here
  @type t :: :elixir | :otp

  @typep remote :: :dev | :origin | :upstream

  defguardp is_project(term) when is_atom(term)

  defguard is_remote(term) when term in [:dev, :origin, :upstream]

  @doc """
  Returns the configuration key-values for `project`.
  """
  @spec config!(Maintenance.project()) :: map()
  def config!(project) do
    project_configs = Application.fetch_env!(:maintenance, :project_configs)

    Map.fetch!(project_configs, project)
  end

  @spec config(Maintenance.project(), atom()) :: any()
  def config(project, key) when is_project(project) and is_atom(key) do
    config = config!(project)

    case Map.fetch(config, key) do
      {:ok, value} -> value
      :error -> nil
    end
  rescue
    _exception ->
      nil
  end

  @spec config!(Maintenance.project(), atom()) :: any()
  def config!(project, key) when is_project(project) and is_atom(key) do
    project
    |> config!()
    |> Map.fetch!(key)
  end

  @spec list() :: [Maintenance.project()]
  def list() do
    project_configs = Application.fetch_env!(:maintenance, :project_configs)

    Map.keys(project_configs)
  end

  @doc """
  Returns the git_url from `config/0` based on whether the app
  is running in production mode or not.
  """
  @spec get_git_url(t() | map(), remote()) :: String.t()
  def get_git_url(project_or_config, remote)

  def get_git_url(project, remote) when is_project(project) and is_remote(remote) do
    project
    |> config!()
    |> get_git_url(remote)
  end

  def get_git_url(config, remote) when is_map(config) when is_remote(remote) do
    owner = Map.get(config.owner, remote)

    "https://github.com/#{owner}/#{config.repo}"
  end

  @doc """
  Returns the project owner from `config/0` based on whether the app
  is running in production mode or not.
  """
  @spec get_owner(t() | map(), remote()) :: String.t()
  def get_owner(project_or_config, remote)

  def get_owner(project, remote) when is_project(project) and is_remote(remote) do
    project
    |> config!()
    |> get_owner(remote)
  end

  def get_owner(config, remote) when is_map(config) and is_remote(remote) do
    Map.get(config.owner, remote)
  end
end
