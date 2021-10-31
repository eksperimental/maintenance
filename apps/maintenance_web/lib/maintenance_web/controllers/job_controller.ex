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
        entry: entry,
      }
    end

    render(conn, "index.html", projects: projects, jobs: jobs, entries: entries)
  end

  def show_projects(conn, _args) do
    projects = Maintenance.projects()
    render(conn, "show.html", projects: projects)
  end  

  def show_jobs(conn, %{"project" => project}) do
    jobs = Maintenance.jobs()
    render(conn, "show.html", project: project, jobs: jobs)
  end  

  def show_entries(conn, %{"project" => project, "job" => job}) do
    entries = Maintenance.Project.list_entries_by_job(String.to_atom(project), String.to_atom(job))
    render(conn, "entries.html", project: project, job: job, entries: entries)
  end  

end
