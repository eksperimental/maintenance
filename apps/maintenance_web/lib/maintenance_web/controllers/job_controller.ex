defmodule MaintenanceWeb.JobController do
  use MaintenanceWeb, :controller

  def index(conn, _params) do
    jobs = Maintenance.jobs()
    projects = Maintenance.projects()

    entries =
      for job <- jobs,
          project <- projects,
          {_k, entry} <- Maintenance.Project.list_entries_by_job(project, job) do
        %{
          job: job,
          project: project,
          entry: entry
        }
      end

    render(conn, "index.html", projects: projects, jobs: jobs, entries: entries)
  end
end
