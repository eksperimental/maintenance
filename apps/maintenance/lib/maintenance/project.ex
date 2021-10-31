defmodule Maintenance.Project do
  @moduledoc """
  Module that contains the specific code for udpating each project.
  """

  alias Maintenance.DB
  import Maintenance, only: [is_project: 1]

  def list_entries_by_job(project, job) when is_project(project) and is_atom(job) do
    # {:ok, result} = DB.select(project, min_key: {job, 0}, reverse: true, pipe: [reduce: fn ])
    {:ok, results} = DB.select(project, reverse: true)

    Enum.filter(results, fn
      {{^job, _}, _v} ->
        true

      _ ->
        false
    end)
  end

  def list() do
    Maintenance.projects()
  end
end
