defmodule MaintenanceWeb.ProjectController do
  use MaintenanceWeb, :controller

  def index(conn, _params) do
    projects = Maintenance.projects()  
    render(conn, "index.html", projects: projects)
  end
end
