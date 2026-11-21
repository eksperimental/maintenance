defmodule MaintenanceJob do
  @moduledoc """
  Behaviour to be implemented by the jobs.

  Note that a job can be implemented for several projects, that is why we always pass the project as an argument.
  """

  @typedoc """
  The job.
  """
  @type t :: atom()

  @typedoc """
  What a job knows about a project: its `current` version, the `latest` one, and the
  `branch` that `c:prepare/2` commits to.
  """
  @type info :: %{current: Version.t(), latest: Version.t(), branch: String.t()}

  @doc """
  Returns the atom representation of the job.
  """
  @callback job() :: t()

  @doc """
  Return `true` when the job is implemented for `project`; otherwise `false`.
  """
  @callback implements_project?(Maintenance.project()) :: boolean

  @doc """
  Returns whether `project` is due for the job.

  It only reads from the network and never touches the Git checkout.
  """
  @callback status(Maintenance.project()) :: {:due, info} | {:up_to_date, info} | {:error, term()}

  @doc """
  Writes the changes for the `info` that `c:status/1` returned and commits them on its
  `branch`.

  It never pushes, and it never asks GitHub.
  """
  @callback prepare(Maintenance.project(), info) ::
              {:ok, :committed, branch :: String.t()} | {:error, term()}
end
