defmodule Mix.Tasks.Maintenance do
  @moduledoc """
  Lists the maintenance commands, the projects and jobs they run on, and the forks that
  pull requests can be opened in.

      mix maintenance
  """

  @shortdoc "Lists the maintenance commands, projects and jobs"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("""
    Maintenance updates files in other projects and opens pull requests for the changes.

      mix maintenance.status [PROJECT [JOB]]            Show which jobs are due
      mix maintenance.run PROJECT JOB                   Build the commit locally
      mix maintenance.publish PROJECT JOB --fork FORK   Push that commit and open the pull request

    Projects and their jobs:
    #{projects_and_jobs()}

    #{Maintenance.CLI.forks_help()}\
    """)
  end

  defp projects_and_jobs() do
    projects = Enum.map(Maintenance.projects(), &Atom.to_string/1)

    width =
      projects
      |> Enum.map(&String.length/1)
      |> Enum.max()

    Enum.map_join(Maintenance.projects(), "\n", fn project ->
      jobs = Enum.join(Maintenance.jobs(project), ", ")
      "  " <> String.pad_trailing(Atom.to_string(project), width) <> "  " <> jobs
    end)
  end
end
