defmodule MaintenanceWeb.PageController do
  use MaintenanceWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
