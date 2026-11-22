defmodule Maintenance.Project do
  @moduledoc """
  Module that contains the specific code for updating each project.
  """

  # Add new projects here
  @type t :: :elixir | :otp

  defguardp is_project(term) when is_atom(term)

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
    :maintenance
    |> Application.fetch_env!(:project_configs)
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Returns the URL of the upstream repository of `project`.
  """
  @spec git_url(Maintenance.project()) :: String.t()
  def git_url(project) when is_project(project) do
    %{owner: owner, repo: repo} = config!(project)

    "https://github.com/#{owner}/#{repo}"
  end

  @doc """
  Returns the URL of the repository of `project` in the `fork` account.
  """
  @spec fork_url(Maintenance.project(), String.t()) :: String.t()
  def fork_url(project, fork) when is_project(project) and is_binary(fork) do
    "https://github.com/#{fork}/#{config!(project, :repo)}"
  end
end
