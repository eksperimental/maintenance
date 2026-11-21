defmodule Maintenance.CLI do
  @moduledoc """
  Turns the arguments of the Mix tasks into projects, jobs and forks.

  The arguments come from the user, so they are matched against the strings of the configured
  atoms and never converted to atoms. A mismatch raises `Mix.Error` and lists the valid values.
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

  @spec fork!(String.t() | nil) :: Maintenance.fork()
  def fork!(nil), do: Mix.raise("Missing --fork.\n\n" <> forks_help())

  def fork!(name) do
    if name in Maintenance.forks() do
      name
    else
      Mix.raise("Unknown fork #{inspect(name)}.\n\n" <> forks_help())
    end
  end

  @doc """
  Describes the forks that `--fork` accepts, one on each line.
  """
  @spec forks_help() :: String.t()
  def forks_help() do
    forks = Maintenance.fork_descriptions()

    width =
      forks
      |> Enum.map(fn {fork, _description} -> String.length(fork) end)
      |> Enum.max()

    lines =
      Enum.map_join(forks, "\n", fn {fork, description} ->
        "  " <> String.pad_trailing(fork, width) <> "  " <> description
      end)

    """
    Forks for --fork. The pull request is opened inside the fork, never in the upstream project.
    #{lines}\
    """
  end

  defp find!(atoms, name, singular, plural) do
    Enum.find(atoms, &(Atom.to_string(&1) == name)) ||
      Mix.raise(
        "Unknown #{singular} #{inspect(name)}. Valid #{plural}: " <>
          Enum.map_join(atoms, ", ", &Atom.to_string/1)
      )
  end
end
