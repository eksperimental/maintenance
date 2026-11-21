defmodule Mix.Tasks.Maintenance.Publish do
  @moduledoc """
  Pushes the commit that `mix maintenance.run` built, without rebuilding it, and opens the
  pull request inside a fork.

      mix maintenance.publish PROJECT JOB [--fork OWNER]

  The pull request is opened inside the fork of OWNER, from the new branch into the fork's
  main branch. It is never opened in the upstream project, such as `elixir-lang/elixir` or
  `erlang/otp`. OWNER defaults to `GITHUB_ACCOUNT`, usually the account that owns
  `GITHUB_ACCESS_TOKEN`. Any other OWNER must have a fork the token can push to.

  The pull request is titled with the subject of the commit. If an open pull request for the
  branch already exists on the fork, it prints its URL and pushes nothing. It pushes nothing
  either when the job is up to date.

  The fork's main branch is fast-forwarded in the same push. If it has commits the upstream
  project does not have, nothing is pushed, and the command tells how to discard them on
  GitHub.

  This is the only command that needs `GITHUB_ACCESS_TOKEN`: put it in `.env` and run
  `source .env`.
  """

  @shortdoc "Pushes the commit built by maintenance.run and opens the pull request"

  use Mix.Task

  alias Maintenance.CLI
  alias Maintenance.Project

  @usage "mix maintenance.publish PROJECT JOB [--fork OWNER]"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {options, names} = OptionParser.parse!(args, strict: [fork: :string])
    {project, job} = CLI.project_and_job!(names, @usage)
    fork = CLI.fork!(options[:fork])

    case Maintenance.publish(project, job, fork) do
      {:opened, url} ->
        Mix.shell().info("Opened #{url}")

      :up_to_date ->
        Mix.shell().info("#{project} #{job} is up to date. Nothing to do.")

      {:pr_exists, url} ->
        Mix.shell().info("An open pull request already exists: #{url}")

      {:error, :missing_token} ->
        Mix.raise("GITHUB_ACCESS_TOKEN is not set. Put it in .env and run `source .env`.")

      {:error, :branch_missing} ->
        Mix.raise(
          "There is no commit to publish for #{project} #{job}. " <>
            "Run `mix maintenance.run #{project} #{job}` first."
        )

      {:error, :fork_main_diverged} ->
        project
        |> fork_main_diverged_message(fork, args)
        |> Mix.raise()

      {:error, reason} ->
        Mix.raise("Could not publish #{project} #{job}: #{inspect(reason)}")
    end
  end

  defp fork_main_diverged_message(project, fork, args) do
    %{owner: owner, repo: repo, main_branch: main_branch} = Project.config!(project)

    """
    The #{main_branch} branch of #{fork}/#{repo} has commits that #{owner}/#{repo} does not \
    have, so nothing was pushed. To discard them, open https://github.com/#{fork}/#{repo}, \
    click Sync fork, then Discard commits. Then run \
    `mix maintenance.publish #{Enum.join(args, " ")}` again.\
    """
  end
end
