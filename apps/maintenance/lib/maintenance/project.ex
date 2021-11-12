defmodule Maintenance.Project do
  @moduledoc """
  Module that contains the specific code for udpating each project.
  """

  alias Maintenance.DB

  # Add new projects here
  @type t :: :sample_project | :elixir | :otp
  @project_configs %{
    elixir: %{
      main_branch: "main",
      owner_origin: "maintenance-beam",
      owner_upstream: "elixir-lang",
      repo: "elixir"
    },
    otp: %{
      main_branch: "master",
      owner_origin: "maintenance-beam",
      owner_upstream: "erlang",
      repo: "otp"
    },
    sample_project: %{
      main_branch: "main",
      owner_origin: "maintenance-beam",
      owner_upstream: "maintenance-beam-app",
      repo: "buildable"
    }
  }

  @projects Map.keys(@project_configs)

  defguardp is_project(term) when term in @projects

  build_config = fn %{
                      main_branch: main_branch,
                      owner_origin: owner_origin,
                      owner_upstream: owner_upstream,
                      repo: repo
                    } ->
    %{
      main_branch: main_branch,
      owner_origin: owner_origin,
      owner_upstream: owner_upstream,
      repo: repo,
      git_url_upstream: "https://github.com/#{owner_upstream}/#{repo}",
      git_url_origin: "https://github.com/#{owner_origin}/#{repo}"
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
end
