defmodule Mix.Tasks.Maintenance.Run do
  @moduledoc """
  Builds the commit of a maintenance job in the local checkout of the project.

      mix maintenance.run PROJECT JOB [--fork OWNER]

  It refreshes the checkout under `~/maintenance_data/cache`, writes the files and commits
  them on a new branch. Nothing is pushed. It can be run again: it starts from the
  upstream branch each time. If an open pull request for the branch exists on the fork of OWNER,
  it prints its URL and changes nothing. OWNER defaults to `GITHUB_ACCOUNT`.

  The commit is authored with your own Git identity, from `git config user.name` and
  `user.email` or the `GIT_AUTHOR_*` and `GIT_COMMITTER_*` variables. It stops if Git
  does not know who you are.

  Inspect the commit, then run `mix maintenance.publish` to open the pull request.
  """

  @shortdoc "Builds the commit of a maintenance job locally"

  use Mix.Task

  alias Maintenance.CLI
  alias Maintenance.Git

  @usage "mix maintenance.run PROJECT JOB [--fork OWNER]"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {options, names} = OptionParser.parse!(args, strict: [fork: :string])
    {project, job} = CLI.project_and_job!(names, @usage)
    fork = CLI.fork!(options[:fork])

    case Maintenance.run(project, job, fork) do
      :up_to_date ->
        Mix.shell().info("#{project} #{job} is up to date. Nothing to do.")

      {:pr_exists, url} ->
        Mix.shell().info("An open pull request already exists: #{url}")

      {:committed, %{branch: branch, path: path}} ->
        with {:ok, stat} <- Git.diff_stat(project, branch),
             {:ok, author} <- Git.commit_author(project, branch) do
          Mix.shell().info("""
          Committed #{branch} as #{author} in #{path}

          #{stat}

          Inspect the commit:
            git -C #{path} show --stat #{branch}

          Push it and open the pull request in the fork of #{fork}:
            mix maintenance.publish #{project} #{job}#{fork_option(options)}
          """)
        else
          {:error, reason} ->
            Mix.raise(
              "Committed #{branch} in #{path}, but could not describe it: " <>
                CLI.describe_error(reason)
            )
        end

      {:error, :missing_git_identity} ->
        Mix.raise("""
        Git does not know who you are, so there is nobody to commit as. Run:
          git config --global user.name "Your Name"
          git config --global user.email "you@example.com"\
        """)

      {:error, reason} ->
        Mix.raise(
          "Could not build the commit for #{project} #{job}: #{CLI.describe_error(reason)}"
        )
    end
  end

  defp fork_option(options) do
    if fork = options[:fork], do: " --fork " <> fork, else: ""
  end
end
