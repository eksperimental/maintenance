defmodule MaintenanceWeb.JobController do
  use MaintenanceWeb, :controller

  def index(conn, _params) do
    projects = Maintenance.projects()

    entries =
      for project <- projects,
          job <- Maintenance.jobs(project),
          {_k, entry} <- Maintenance.Project.list_entries_by_job(project, job) do
        %{
          job: job,
          project: project,
          entry: entry
        }
      end

    render(conn, "index.html", projects: projects, entries: entries)
  end
end
