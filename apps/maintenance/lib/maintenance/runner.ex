defmodule Maintenance.Runner do
  @moduledoc """
  This module is invoked to run the jobs.
  """

  import Maintenance, only: [is_job: 1, is_project: 1]

  @doc """
  Updates all jobs for all projects.
  """
  @spec update() :: [{Maintenance.project(), Maintenance.job(), MaintenanceJob.status()}]
  def update() do
    for project <- Maintenance.projects(),
        job <- Maintenance.jobs() do
      {project, job, update(project, job)}
    end
  end

  @doc """
  Runs `job` for `project`.
  """
  @spec update(Maintenance.project(), Maintenance.job()) :: MaintenanceJob.status()
  def update(project, job) when is_project(project) and is_job(job) do
    job_module = get_job_module(job)

    if apply(job_module, :implements_project?, [project]) do
      apply(job_module, :update, [project])
    else
      :not_implemented
    end
  end

  @doc """
  Returns the module that implements the given `job`.
  """
  @spec get_job_module(Maintenance.job()) :: module
  def get_job_module(job) when is_job(job) do
    Module.concat([MaintenanceJob, Macro.camelize(to_string(job))])
  end
end
