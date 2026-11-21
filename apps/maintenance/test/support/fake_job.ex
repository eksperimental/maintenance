defmodule MaintenanceJob.FakeJob do
  @moduledoc """
  A job for the :elixir project that reads nothing from the network.

  A test sets its status and the process to notify with
  `Application.put_env(:maintenance, MaintenanceJob.FakeJob, status: status, notify: pid)`.
  `prepare/2` sends `{:prepare, project}` to that process and does no git work.
  """

  @behaviour MaintenanceJob

  @impl MaintenanceJob
  def job(), do: :fake_job

  @impl MaintenanceJob
  def implements_project?(project), do: project == :elixir

  @impl MaintenanceJob
  def status(_project), do: Keyword.fetch!(options(), :status)

  @impl MaintenanceJob
  def prepare(project, info) do
    send(Keyword.fetch!(options(), :notify), {:prepare, project})

    {:ok, :committed, info.branch}
  end

  defp options(), do: Application.fetch_env!(:maintenance, __MODULE__)
end
