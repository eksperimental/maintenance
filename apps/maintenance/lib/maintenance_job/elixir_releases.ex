defmodule MaintenanceJob.ElixirReleases do
  # COPYRIGHT NOTICE:
  # Some functions in the this module have been adapted and ported from Erlang into Elixir by the author,
  # taken from the source code of the erlang.org website:
  # https://github.com/elixir-lang/erlang-org
  # See the /NOTICE file for more information about the copyright holders and the license.
  # The files where the code has been taken are:
  # https://github.com/elixir-lang/erlang-org/blob/39521fb11b3545d69bc26e4a5a9b02995a0f4e49/_scripts/src/create-releases.erl
  # https://github.com/elixir-lang/erlang-org/blob/39521fb11b3545d69bc26e4a5a9b02995a0f4e49/_scripts/src/gh.erl

  @moduledoc """
  OTP Releases job.
  """

  @behaviour MaintenanceJob

  import BeamLangsMetaData.Helper, only: [to_version!: 1]
  import Maintenance, only: [is_project: 1]

  require Logger

  alias Maintenance.DB
  alias Maintenance.Git
  alias Maintenance.Github
  alias Maintenance.Util

  @job :elixir_releases
  @github_releases_url "https://api.github.com/repos/elixir-lang/elixir/releases?per_page=100"

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
  def implements_project?(:beam_langs_meta_data), do: true
  def implements_project?(project) when is_atom(project), do: false

  @doc """
  Updates the OTP versions in `beam_langs_meta_data`.
  """
  @impl MaintenanceJob
  @spec update(Maintenance.project()) :: MaintenanceJob.status()
  def update(project) when is_project(project) do
    {:ok, elixir_releases} = Github.fetch(@github_releases_url)

    elixir_releases_json =
      elixir_releases
      |> build_releases()
      |> Jason.encode!(pretty: true)

    elixir_releases_hash = Util.hash(elixir_releases_json)

    if needs_update?(project, @job, {:elixir_releases, elixir_releases_hash}) == false do
      Util.info(
        "PR exists: no update needed [#{project}]: " <> DB.get(:beam_langs_meta_data, @job).url
      )

      {:ok, :no_update_needed}
    else
      fn_task_write_elixir_releases = fn ->
        json_path =
          project
          |> Git.path()
          |> Path.join("priv/elixir_releases.json")

        Util.info("Writing Elixir releases: #{json_path}")

        :ok = File.write(json_path, elixir_releases_json)
        Git.add(project, json_path)

        {:elixir_releases, elixir_releases_hash}
      end

      run_tasks(project, [fn_task_write_elixir_releases])
    end
  end

  @impl MaintenanceJob
  @spec needs_update?(Maintenance.project(), MaintenanceJob.t(), tuple()) :: boolean()
  def needs_update?(project, db_key, db_value)

  def needs_update?(:beam_langs_meta_data, job, value) when is_atom(job) do
    value != DB.get(:beam_langs_meta_data, job)[:value]
  end

  @impl MaintenanceJob
  @spec run_tasks(Maintenance.project(), [(-> :ok)], term) :: MaintenanceJob.status()
  def run_tasks(project, tasks, _additional_term \\ nil)
      when is_list(tasks) do
    [ok: {:elixir_releases, elixir_releases}] =
      tasks
      |> Task.async_stream(& &1.(), timeout: :infinity)
      |> Enum.to_list()

    commit_message = "Update elixir_releases.json"

    pr_data = %{
      title: "Update Elixir releases",
      db_key: @job,
      db_value: {:elixir_releases, elixir_releases}
    }

    Git.checkout_new_branch_and_produce_commit!(project, @job, commit_message, pr_data)
  end

  #########################
  # Helpers

  defp build_assets(assets) do
    for asset <- assets do
      asset
      |> Map.take([
        "browser_download_url",
        "content_type",
        "created_at",
        "id",
        "label",
        "name",
        "node_id",
        "size",
        "state",
        "updated_at",
        "url"
      ])
      |> Map.put("uploader", asset.uploader.login)
    end
  end

  defp tag_name_to_version("v" <> version) do
    to_version!(version)
  end

  @spec build_releases(list()) :: [%{String.t() => any()}]
  def build_releases(list) do
    pre_filtered =
      Enum.reject(list, fn json_entry ->
        json_entry.tag_name
        |> tag_name_to_version()
        |> Version.match?("< 1.0.0")
      end)

    for json_entry <- pre_filtered do
      assets = build_assets(json_entry["assets"])

      json_entry
      |> Map.take([
        "assets_url",
        "body",
        "created_at",
        "draft",
        "html_url",
        "id",
        "name",
        "node_id",
        "prerelease",
        "published_at",
        "tag_name",
        "tarball_url",
        "target_commitish",
        "upload_url",
        "url",
        "zipball_url"
      ])
      |> Map.put("author", json_entry.author.login)
      |> Map.put("assets", assets)
    end
  end
end
