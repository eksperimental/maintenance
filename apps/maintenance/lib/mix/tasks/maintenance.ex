defmodule Mix.Tasks.Maintenance do
  @moduledoc """
  Lists the maintenance commands, the projects and jobs they run on, and the default fork
  that pull requests are opened in.

      mix maintenance
  """

  @shortdoc "Lists the maintenance commands, projects and jobs"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("""
    Maintenance updates files in other projects and opens pull requests for the changes.

      mix maintenance.status [PROJECT [JOB]]   Show which jobs are due
      mix maintenance.run PROJECT JOB          Build the commit locally
      mix maintenance.publish PROJECT JOB      Push that commit and open the pull request

    Projects and their jobs:
    #{projects_and_jobs()}

    #{fork_help(Maintenance.github_account())}\
    """)
  end

  defp fork_help(nil) do
    """
    Pull requests are opened inside a fork, never in the upstream project. GITHUB_ACCOUNT
    is not set, so pass --fork OWNER, or add `export GITHUB_ACCOUNT=<your account>` to .env.\
    """
  end

  defp fork_help(account) do
    """
    Pull requests are opened inside the fork of #{account} (GITHUB_ACCOUNT), never in the
    upstream project. Each command takes --fork OWNER to use another fork.\
    """
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
