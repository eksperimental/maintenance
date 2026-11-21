defmodule Maintenance.CLI do
  @moduledoc """
  Turns the arguments of the Mix tasks into projects, jobs and forks, and their errors into
  text.

  The project and job names come from the user, so they are matched against the strings of
  the configured atoms and never converted to atoms. A mismatch raises `Mix.Error` and lists the valid values.
  """

  @doc """
  Returns the project and the job of the positional `args`, which must be exactly the two names.
  """
  @spec project_and_job!([String.t()], usage :: String.t()) ::
          {Maintenance.project(), Maintenance.job()}
  def project_and_job!([project_name, job_name], _usage) do
    project = project!(project_name)

    {project, job!(project, job_name)}
  end

  def project_and_job!(_args, usage), do: Mix.raise("Usage: " <> usage)

  @spec project!(String.t()) :: Maintenance.project()
  def project!(name), do: find!(Maintenance.projects(), name, "project", "projects")

  @spec job!(Maintenance.project(), String.t()) :: Maintenance.job()
  def job!(project, name) do
    find!(Maintenance.jobs(project), name, "job for #{project}", "jobs for #{project}")
  end

  @doc """
  Returns the account given as `--fork`, or the one in `GITHUB_ACCOUNT` without it.
  """
  @spec fork!(String.t() | nil) :: Maintenance.fork()
  def fork!(nil) do
    Maintenance.github_account() ||
      Mix.raise(
        "Pass --fork OWNER, or add `export GITHUB_ACCOUNT=<your account>` to .env " <>
          "and run `source .env`."
      )
  end

  def fork!(""), do: Mix.raise("--fork needs the GitHub account that holds the fork")
  def fork!(owner), do: owner

  @doc """
  Describes the error `reason` of a task for the user.
  """
  @spec describe_error(term()) :: String.t()
  def describe_error({:not_found, repo}), do: repo <> " not found on GitHub"

  def describe_error({:rate_limited, reset_at}),
    do: "GitHub rate limit reached, try again after " <> Calendar.strftime(reset_at, "%H:%M UTC")

  def describe_error({:current_unicode_version_not_found, url}),
    do: "current Unicode version not found in " <> url

  def describe_error({:latest_unicode_version_not_found, url}),
    do: "latest Unicode version not found at " <> url

  def describe_error({:download_failed, url, status}),
    do: "could not download #{url} (HTTP #{status})"

  def describe_error(error = %Req.TransportError{}),
    do: "network error (" <> Exception.message(error) <> ")"

  def describe_error(reason), do: inspect(reason)

  defp find!(atoms, name, singular, plural) do
    Enum.find(atoms, &(Atom.to_string(&1) == name)) ||
      Mix.raise(
        "Unknown #{singular} #{inspect(name)}. Valid #{plural}: " <>
          Enum.map_join(atoms, ", ", &Atom.to_string/1)
      )
  end
end
