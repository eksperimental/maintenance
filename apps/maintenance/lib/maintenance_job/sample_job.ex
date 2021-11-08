defmodule MaintenanceJob.SampleJob do
  @moduledoc """
  Test MaintenajeJob module.
  """

  @job :sample_job

  import Maintenance, only: [is_project: 1]
  import Maintenance.Project, only: [config: 2]
  alias Maintenance.{Git, DB}

  @behaviour MaintenanceJob

  @type version :: %Version{}
  @type response :: %Finch.Response{}
  @type response_status :: pos_integer()
  @type contents :: %{required(file_name :: String.t()) => file_contents :: String.t()}

  #############################
  # Callbacks

  @impl MaintenanceJob
  @spec implements_project?(project :: atom) :: boolean
  def implements_project?(:sample_project), do: true
  def implements_project?(_), do: false

  @doc """
  Updates the `foo` file in the given `project` by creating a Git commit.
  """
  @impl MaintenanceJob
  @spec update(Maintenance.project()) :: MaintenanceJob.status()
  def update(project) when is_project(project) do
    if needs_update?(project) do
      if pr_exists?(project, @job) do
        {:ok, :no_update_needed}
      else
        fn_task_write_foo = fn ->
          git_path = Git.path(project)
          foo_path = Path.join([git_path, "foo"])

          File.write(foo_path, "bar")
          Git.add(project, "foo")
        end

        run_tasks(project, [fn_task_write_foo])
      end
    else
      {:ok, :no_update_needed}
    end
  end

  #########################
  # Helpers

  defp bool(term), do: not (!term)

  def needs_update?(project) do
    case get_foo(project) do
      {:ok, _contents} -> false
      :error -> true
    end
  end

  @spec run_tasks(Maintenance.project(), [(() -> :ok)]) :: {:ok, :updated}
  def run_tasks(project, tasks)
      when is_list(tasks) do
    {:ok, _} = Git.cache_repo(project)

    :ok = Git.checkout(project, config(project, :main_branch))
    {:ok, previous_branch} = Git.get_branch(project)

    new_branch = to_string(project)

    if Git.branch_exists?(project, new_branch) do
      :ok = Git.delete_branch(project, new_branch)
    end

    :ok = Git.checkout_new_branch(project, new_branch)

    tasks
    |> Task.async_stream(& &1.(), timeout: :infinity)
    |> Stream.run()

    # Commit
    :ok = Git.commit(project, "Add foo file")

    data = %{
      title: "Add foo file",
      db_key: @job,
      db_value: true,
    }

    :ok = Git.submit_pr(project, @job, data)
    :ok = Git.checkout(project, previous_branch)

    {:ok, :updated}
  end

  defp pr_exists?(:sample_project, job) when is_atom(job) do
    bool(get_sample_project_db_entry(:sample_project, job))
  end

  defp get_sample_project_db_entry(project, job)
       when is_project(project) and is_atom(job) do
    DB.get(project, job)
  end

  @doc """
  Gets the current Unicode version for the given `project`.
  """
  @spec get_foo(Maintenance.project()) :: {:ok, contents :: String.t()} | :error
  def get_foo(:sample_project) do
    result =
      "https://raw.githubusercontent.com/maintenance-beam-app/buildable/main/foo"
      |> Req.get!()

    case result do
      %{status: 200} ->
        {:ok, Map.fetch!(result, :body)}

      _ ->
        :error
    end
  end
end
