defmodule Maintenance.CLI do
  @moduledoc """
  Turns the arguments of the Mix tasks into projects, jobs and forks.

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
  Returns the account given as `--fork`, or `Maintenance.author_github_account/0` without one.
  """
  @spec fork!(String.t() | nil) :: Maintenance.fork()
  def fork!(nil), do: Maintenance.author_github_account()
  def fork!(""), do: Mix.raise("--fork needs the GitHub account that holds the fork")
  def fork!(owner), do: owner

  defp find!(atoms, name, singular, plural) do
    Enum.find(atoms, &(Atom.to_string(&1) == name)) ||
      Mix.raise(
        "Unknown #{singular} #{inspect(name)}. Valid #{plural}: " <>
          Enum.map_join(atoms, ", ", &Atom.to_string/1)
      )
  end
end
