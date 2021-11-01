defmodule MaintenanceJob do
  @moduledoc """
  Behaviour to be implemented by the jobs.
  """

  @typedoc """
  The status returned by a job:
  - `{:ok, :updated}` - the job was succefully executed; 
  - `{:ok, no_update_needed}` - the job was succesfully run, but no update was needed; 
  - `{:error, term()}` - the job was failed and a term is passed with it;
  - `:not_implemented` - the job was was not executed because it is not implemented;
  """
  @type status :: {:ok, :updated} | {:ok, :no_update_needed} | {:error, term()} | :not_implemented

  @doc """
  Runs the job.

  Returns `:ok` on success, `{:error, any()}` on error, and `nil` if the job is
  not implemented for `project`.
  """
  @callback update(Maintenance.project()) :: status()

  @doc """
  Return `true` when the job is implemented for `project`; otherwise `false`.
  """
  @callback implements_project?(Maintenance.project()) :: boolean
end
