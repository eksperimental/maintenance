defmodule MaintenanceJob.SampleJob do
  @moduledoc """
  Sample MaintenanceJob module.

  What this sample job does it to check for the file `YEAR_MONTH.md` and checks if the file contains the string of the current `YEAR-MONTH` for example "2022-01".
  """

  @behaviour MaintenanceJob

  import Maintenance, only: [is_project: 1]

  require Logger

  alias Maintenance.DB
  alias Maintenance.Git
  alias Maintenance.Util

  @job :sample_job
  # 5 minutes
  @req_options [receive_timeout: 60_000 * 5]
  @year_month_url "https://raw.githubusercontent.com/maintenance-beam/sample_project/main/YEAR_MONTH.md"

  @type response :: %Finch.Response{}
  @type response_status :: pos_integer()
  @type contents :: %{required(file_name :: String.t()) => file_contents :: String.t()}

  #############################
  # Callbacks

  @impl MaintenanceJob
  @spec job() :: Maintenance.job()
  def job(), do: @job

  @impl MaintenanceJob
  @spec implements_project?(project :: atom) :: boolean
  def implements_project?(:sample_project), do: true
  def implements_project?(project) when is_atom(project), do: false

  @doc """
  Updates the `YEAR_MONTH.md` file in the given `project` by creating a Git commit.
  """
  @impl MaintenanceJob
  @spec update(Maintenance.project()) :: MaintenanceJob.status()
  def update(project) when is_project(project) do
    year_month_string = Calendar.strftime(DateTime.utc_now(), "%Y-%m")
    db_value = {:year_month, year_month_string}
    pr_exists? = pr_exists?(project, @job, db_value)
    db_entry = DB.get(project, @job)

    cond do
      needs_update?(project, @job, db_value) == false ->
        if pr_exists? do
          Util.info("PR exists: no update needed [#{project}]: #{db_entry.url}")
        end

        {:ok, :no_update_needed}

      pr_exists? ->
        Util.info("PR exists: no update needed [#{project}]:  #{db_entry.url}")

        {:ok, :no_update_needed}

      true ->
        fn_task_write_year_month = fn ->
          year_month_path =
            project
            |> Git.path()
            |> Path.join("YEAR_MONTH.md")

          Util.info("Writing YEAR_MONTH: #{year_month_path}")

          :ok = File.write(year_month_path, year_month_string)
          Git.add(project, year_month_path)

          {:year_month, year_month_string}
        end

        run_tasks(project, [fn_task_write_year_month], {:year_month, year_month_string})
    end
  end

  defp pr_exists?(project, job, db_value) when is_atom(job) do
    db_value == DB.get(project, job)[:value]
  end

  @doc """
  Check online for the contents of `YEAR_MONTH.md`.

  If the logs in our database have been updated in the past five days, we don't check for the online version.
  If not, we check it just in case it has been updated after our last commit.
  """
  @impl MaintenanceJob
  @spec needs_update?(Maintenance.project(), MaintenanceJob.t(), tuple()) :: boolean()
  def needs_update?(project, db_key, db_value)

  def needs_update?(_project, job, {:year_month, year_month_string}) when is_atom(job) do
    case get_remote_file_contents(@year_month_url) do
      {:ok, contents} ->
        dbg(year_month_string != String.trim(contents))

      :error ->
        true
    end
  end

  @impl MaintenanceJob
  @spec run_tasks(Maintenance.project(), [(-> :ok)], term()) :: MaintenanceJob.status()
  def run_tasks(project, tasks, _additional_term \\ nil) when is_list(tasks) do
    {:ok, _new_branch, _previous_branch} = Git.setup_repo(project)

    [ok: {:year_month, year_month_string}] =
      tasks
      |> Task.async_stream(& &1.(), timeout: :infinity)
      |> Enum.to_list()

    commit_message = "Update YEAR_MONTH.md"

    pr_data = %{
      title: "Update Year-Month",
      db_key: @job,
      db_value: {:year_month, year_month_string}
    }

    Git.checkout_new_branch_and_produce_commit!(project, @job, commit_message, pr_data)
  end

  #########################
  # Helpers

  @doc """
  Gets the current Unicode version for the given `project`.
  """
  @spec get_remote_file_contents(String.t()) :: {:ok, contents :: String.t()} | :error
  def get_remote_file_contents(url) do
    response = Req.get!(url, @req_options)

    case response do
      %{status: 200} ->
        {:ok, Map.fetch!(response, :body)}

      _other ->
        :error
    end
  end
end
