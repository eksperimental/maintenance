defmodule Mix.Tasks.Maintenance.Status do
  @moduledoc """
  Shows which maintenance jobs are due, one line for each project and job.

      mix maintenance.status [PROJECT [JOB]] [--fork OWNER]

  A job is up to date, due, or due with a pull request already open on the fork of OWNER.
  OWNER defaults to `GITHUB_ACCOUNT`.
  It reads from unicode.org and GitHub, and does not touch the Git checkouts. It works
  without `GITHUB_ACCESS_TOKEN`.
  """

  @shortdoc "Shows which maintenance jobs are due"

  use Mix.Task

  alias Maintenance.CLI

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {options, names} = OptionParser.parse!(args, strict: [fork: :string])
    fork = CLI.fork!(options[:fork])

    rows = for {project, job} <- pairs(names), do: row(project, job, fork)
    widths = Enum.zip_with(rows, &widest/1)

    for row <- rows do
      line = format(row, widths)
      Mix.shell().info(line)
    end
  end

  defp widest(column) do
    column
    |> Enum.map(&String.length/1)
    |> Enum.max()
  end

  defp format(row, widths) do
    row
    |> Enum.zip_with(widths, &String.pad_trailing/2)
    |> Enum.join("  ")
    |> String.trim_trailing()
  end

  defp pairs([]) do
    for project <- Maintenance.projects(), job <- Maintenance.jobs(project), do: {project, job}
  end

  defp pairs([project_name]) do
    project = CLI.project!(project_name)

    for job <- Maintenance.jobs(project), do: {project, job}
  end

  defp pairs(names = [_project_name, _job_name]) do
    [CLI.project_and_job!(names, "")]
  end

  defp pairs(_names),
    do: Mix.raise("Usage: mix maintenance.status [PROJECT [JOB]] [--fork OWNER]")

  defp row(project, job, fork) do
    {versions, state} =
      case Maintenance.status(project, job, fork) do
        {:due, info} -> {"#{info.current} -> #{info.latest}", "due"}
        {:up_to_date, info} -> {to_string(info.current), "up to date"}
        {:pr_exists, info, url} -> {"#{info.current} -> #{info.latest}", "PR open: " <> url}
        {:error, reason} -> Mix.raise("Could not check #{project} #{job}: #{inspect(reason)}")
      end

    [Atom.to_string(project), Atom.to_string(job), versions, state]
  end
end
