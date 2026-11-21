defmodule Mix.Tasks.Maintenance.Publish do
  @moduledoc """
  Pushes the commit that `mix maintenance.run` built, without rebuilding it, and opens the
  pull request inside a fork.

      mix maintenance.publish PROJECT JOB [--fork OWNER]

  The pull request is opened inside the fork of OWNER, from the new branch into the fork's
  main branch. It is never opened in the upstream project, such as `elixir-lang/elixir` or
  `erlang/otp`. OWNER defaults to `author_github_account` in `config/config.exs`, the
  account that owns `GITHUB_ACCESS_TOKEN`. Any other OWNER must have a fork the token can
  push to.

  The pull request is titled with the subject of the commit. If a pull request for the
  branch already exists on the fork, it prints its URL and pushes nothing.

  This is the only command that needs `GITHUB_ACCESS_TOKEN`: put it in `.env` and run
  `source .env`.
  """

  @shortdoc "Pushes the commit built by maintenance.run and opens the pull request"

  use Mix.Task

  alias Maintenance.CLI

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

      {:pr_exists, url} ->
        Mix.shell().info("A pull request already exists: #{url}")

      {:error, :missing_token} ->
        Mix.raise("GITHUB_ACCESS_TOKEN is not set. Put it in .env and run `source .env`.")

      {:error, :branch_missing} ->
        Mix.raise(
          "There is no commit to publish for #{project} #{job}. " <>
            "Run `mix maintenance.run #{project} #{job}` first."
        )

      {:error, reason} ->
        Mix.raise("Could not publish #{project} #{job}: #{inspect(reason)}")
    end
  end
end
