defmodule Maintenance.Project do
  @moduledoc """
  Module that contains the specific code for udpating each project.
  """

  alias Maintenance.DB

  # Add new projects here
  @type t :: :sample_project | :elixir | :otp | :beam_langs_meta_data

  @typep remote :: :upstream | :origin | :dev

  # NOTE:
  # - maintenance-beam is the organization under which repositories are forked, and the PRs are created.
  # - maintenance-beam-app is the user that create the PRs. The GitHub token access belongs to this user.
  #     Also for dev/testing, the repositories are under maintenance-beam-app

  @owner_dev "maintenance-beam-app"

  @project_configs %{
    elixir: %{
      main_branch: "main",
      owner_upstream: "elixir-lang",
      owner_origin: "maintenance-beam",
      owner_dev: @owner_dev,
      repo: "elixir"
    },
    otp: %{
      main_branch: "master",
      owner_upstream: "erlang",
      owner_origin: "maintenance-beam",
      owner_dev: @owner_dev,
      repo: "otp"
    },
    sample_project: %{
      main_branch: "main",
      owner_upstream: "maintenance-beam",
      owner_origin: "maintenance-beam-app",
      owner_dev: @owner_dev,
      repo: "sample_project"
    },
    beam_langs_meta_data: %{
      main_branch: "main",
      owner_upstream: "eksperimental",
      owner_origin: "maintenance-beam-app",
      owner_dev: @owner_dev,
      repo: "beam_langs_meta_data"
    }
  }

  @projects Map.keys(@project_configs)

  defguardp is_project(term) when term in @projects

  build_config = fn %{
                      main_branch: main_branch,
                      owner_upstream: owner_upstream,
                      owner_origin: owner_origin,
                      owner_dev: owner_dev,
                      repo: repo
                    } ->
    %{
      main_branch: main_branch,
      repo: repo,
      owner: %{
        upstream: owner_upstream,
        origin: owner_origin,
        dev: owner_dev
      },
      git_url: %{
        upstream: "https://github.com/#{owner_upstream}/#{repo}",
        origin: "https://github.com/#{owner_origin}/#{repo}",
        dev: "https://github.com/#{owner_dev}/#{repo}"
      }
    }
  end

  @doc """
  Returns the configuration key-values for `project`.
  """
  def config(project)

  for {project, config} <- @project_configs do
    result = config |> build_config.() |> Macro.escape()

    def config(unquote(project)) do
      unquote(result)
    end
  end

  def config(project, key) when is_project(project) and is_atom(key) do
    config(project) |> Map.fetch!(key)
  end

  def list_entries_by_job(project, job) when is_project(project) and is_atom(job) do
    # {:ok, result} = DB.select(project, min_key: {job, 0}, reverse: true, pipe: [reduce: fn ])
    {:ok, results} = DB.select(project, reverse: true)

    Enum.filter(results, fn
      {{^job, _}, _v} ->
        true

      {^job, _v} ->
        true

      _ ->
        false
    end)
  end

  def list(), do: @projects

  @doc """
  Returns the git_url from `config/0` based on whether the app
  is running in full production mode or not.
  """
  @spec git_url(t() | map(), remote) :: String.t()
  def git_url(project_or_config, remote)

  def git_url(project, remote) when is_project(project) do
    config = config(project)
    git_url(config, remote)
  end

  def git_url(config, remote) when is_map(config) and remote in [:dev, :origin] do
    Map.get(config.git_url, remote)
  end

  def git_url(config, :upstream) when is_map(config) do
    if Maintenance.full_production?() do
      config.git_url.upstream
    else
      config.git_url.dev
    end
  end

  @doc """
  Returns the project owner from `config/0` based on whether the app
  is running in full production mode or not.
  """
  @spec owner(t() | map(), remote) :: String.t()
  def owner(project_or_config, remote)

  def owner(project, remote) when is_project(project) do
    config = config(project)
    owner(config, remote)
  end

  def owner(config, remote) when is_map(config) and remote in [:dev, :origin] do
    Map.get(config.owner, remote)
  end

  def owner(config, :upstream) when is_map(config) do
    if Maintenance.full_production?() do
      config.owner.upstream
    else
      config.owner.dev
    end
  end
end
