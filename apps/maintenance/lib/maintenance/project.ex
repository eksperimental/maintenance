defmodule Maintenance.Project do
  @moduledoc """
  Module that contains the specific code for udpating each project.
  """

  alias Maintenance.DB
  import Maintenance, only: [is_project: 1]

  @doc """
  Returns the configuration key-values for `project`.
  """
  def config(project)

  def config(:elixir) do
    %{
      main_branch: "main",
      owner_origin: "maintenance-beam",
      owner_upstream: "elixir-lang",
      repo: "elixir"
    }
    |> build_config()
  end

  def config(:otp) do
    %{
      main_branch: "master",
      owner_origin: "maintenance-beam",
      owner_upstream: "erlang",
      repo: "otp"
    }
    |> build_config()
  end

  def config(:sample_project) do
    %{
      main_branch: "main",
      owner_origin: "maintenance-beam",
      owner_upstream: "maintenance-beam-app",
      repo: "buildable"
    }
    |> build_config()
  end

  def config(project, key) when is_project(project) and is_atom(key) do
    config(project) |> Map.fetch!(key)
  end

  defp build_config(%{
         main_branch: main_branch,
         owner_origin: owner_origin,
         owner_upstream: owner_upstream,
         repo: repo
       }) do
    %{
      main_branch: main_branch,
      owner_origin: owner_origin,
      owner_upstream: owner_upstream,
      repo: repo,
      git_url_upstream: "https://github.com/#{owner_upstream}/#{repo}",
      git_url_origin: "https://github.com/#{owner_origin}/#{repo}"
    }
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

  def list() do
    Maintenance.projects()
  end
end
