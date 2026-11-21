defmodule Mix.Tasks.Maintenance.Run do
  @moduledoc """
  Builds the commit of a maintenance job in the local checkout of the project.

      mix maintenance.run PROJECT JOB

  It refreshes the checkout under `~/maintenance_data/cache`, writes the files and commits
  them on a new branch. Nothing is pushed. It can be run again: it starts from the
  upstream branch each time. If a pull request for the branch exists on one of the forks,
  it prints its URL and changes nothing.

  Inspect the commit, then run `mix maintenance.publish` to open the pull request.
  """

  @shortdoc "Builds the commit of a maintenance job locally"

  use Mix.Task

  alias Maintenance.CLI
  alias Maintenance.Git

  @usage "mix maintenance.run PROJECT JOB"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {[], names} = OptionParser.parse!(args, strict: [])
    {project, job} = CLI.project_and_job!(names, @usage)

    case Maintenance.run(project, job) do
      :up_to_date ->
        Mix.shell().info("#{project} #{job} is up to date. Nothing to do.")

      {:pr_exists, url} ->
        Mix.shell().info("A pull request already exists: #{url}")

      {:committed, %{branch: branch, path: path}} ->
        {:ok, stat} = Git.diff_stat(project, branch)

        Mix.shell().info("""
        Committed #{branch} in #{path}

        #{stat}

        Inspect the commit:
          git -C #{path} show --stat #{branch}

        Push it and open the pull request:
          mix maintenance.publish #{project} #{job} --fork FORK

        #{CLI.forks_help()}\
        """)

      {:error, reason} ->
        Mix.raise("Could not build the commit for #{project} #{job}: #{inspect(reason)}")
    end
  end
end
