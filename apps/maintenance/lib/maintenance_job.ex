defmodule MaintenanceJob do
  @moduledoc """
  Behaviour to be implemented by the jobs.
  """

  require Logger

  @typedoc """
  The job.
  """
  @type t :: atom

  @type tasks :: [(() -> :ok)]

  @typedoc """
  The status returned by a job:
  - `{:ok, :updated}` - the job was succefully executed; 
  - `{:ok, no_update_needed}` - the job was succesfully run, but no update was needed; 
  - `{:error, term()}` - the job was failed and a term is passed with it;
  - `:not_implemented` - the job was was not executed because it is not implemented;
  """
  @type status :: {:ok, :updated} | {:ok, :no_update_needed} | {:error, term()} | :not_implemented

  @doc """
  Retuns the atom representation of the job.
  """
  @callback job() :: t()

  @doc """
  Runs the job.

  Returns `:ok` on success, `{:error, any()}` on error, and `nil` if the job is
  not implemented for `project`.
  """
  @callback update(Maintenance.project()) :: status()

  @doc """
  Runs the tasks generated by `udpate/1`.

  This callback is optional.
  """
  @callback run_tasks(Maintenance.project(), tasks, additional_term :: any) :: status()

  @doc """
  Returns whether the project needs to be updated or not.

  This function will check online or in the database

  - `db_key` is what will be recorded in the database as a key.
  - `db_value` is what will be recorded in the database as a value. this should include a hash of the file that we are checking,
    or a version number.

  This callback is optional.
  """
  @callback needs_update?(Maintenance.project(), db_key :: atom, db_value :: term) :: boolean()

  @doc """
  Return `true` when the job is implemented for `project`; otherwise `false`.
  """
  @callback implements_project?(Maintenance.project()) :: boolean

  @optional_callbacks needs_update?: 3, run_tasks: 3
end
