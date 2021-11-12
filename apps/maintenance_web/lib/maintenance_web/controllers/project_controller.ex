defmodule MaintenanceWeb.ProjectController do
  use MaintenanceWeb, :controller

  def index(conn, _params) do
    projects = Maintenance.projects()
    render(conn, "index.html", projects: projects)
  end

  def index_redirect(conn, _params) do
    redirect(conn, to: "/projects")
  end

  def show_jobs(conn, %{"project" => project}) do
    jobs = project |> String.to_atom() |> Maintenance.jobs()
    render(conn, "show.html", project: project, jobs: jobs)
  end

  def show_entries(conn, %{"project" => project, "job" => job}) do
    entries =
      Maintenance.Project.list_entries_by_job(String.to_atom(project), String.to_atom(job))

    render(conn, "entries.html", project: project, job: job, entries: entries)
  end
end
