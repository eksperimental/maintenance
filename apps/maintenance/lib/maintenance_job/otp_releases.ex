defmodule MaintenanceJob.OtpReleases do
  # COPYRIGHT NOTICE:
  # Some functions in the this module have been adapted and ported from Erlang into Elixir by the author,
  # taken from the source code of the erlang.org website:
  # https://github.com/erlang/erlang-org
  # See the /NOTICE file for more information about the copyright holders and the license.
  # The files where the code has been taken are:
  # https://github.com/erlang/erlang-org/blob/39521fb11b3545d69bc26e4a5a9b02995a0f4e49/_scripts/src/create-releases.erl
  # https://github.com/erlang/erlang-org/blob/39521fb11b3545d69bc26e4a5a9b02995a0f4e49/_scripts/src/gh.erl

  @moduledoc """
  OTP Releases job.
  """

  @behaviour MaintenanceJob

  use Maintenance.Util

  import Maintenance, only: [is_project: 1]
  import Maintenance.Project, only: [config: 2]

  alias Maintenance.{Git, Github, DB, Util}

  @job :otp_releases

  @erlang_download_url "https://erlang.org/download/"
  @github_tags_url "https://api.github.com/repos/erlang/otp/tags?per_page=100"
  @version_table_url "https://raw.githubusercontent.com/erlang/otp/master/otp_versions.table"
  @github_releases_url "https://api.github.com/repos/erlang/otp/releases?per_page=100"

  @otp_accepted_keys ~W(
    assets
    assets_url
    body
    created_at
    draft
    html_url
    id
    name
    node_id
    prerelease
    published_at
    tag_name
    tarball_url
    target_commitish
    upload_url
    url
    zipball_url
  )a

  @assets_accepted_keys ~W(
    browser_download_url
    content_type
    created_at
    id
    label
    name
    node_id
    size
    state
    url
  )a

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
    {releases_json, releases_json_hash} = releases_json()

    if needs_update?(project, @job, {:otp_releases, releases_json_hash}) == false do
      Util.info(
        "PR exists: no update needed [#{project}]: " <> DB.get(:beam_langs_meta_data, @job).url
      )

      {:ok, :no_update_needed}
    else
      fn_task_write_otp_releases = fn ->
        json_path = Path.join(Git.path(project), "priv/otp_releases.json")
        Util.info("Writting OTP releases: #{json_path}")

        :ok = File.write(json_path, releases_json)
        Git.add(project, json_path)

        {:otp_releases, releases_json_hash}
      end

      run_tasks(project, [fn_task_write_otp_releases])
    end
  end

  defp releases_json() do
    {:ok, otp_versions_table} = get_versions_table()
    versions = parse_otp_versions_table(otp_versions_table)
    downloads = parse_erlang_org_downloads()
    tags = parse_github_tags()

    {:ok, gh_releases} = Github.get!(@github_releases_url)

    patches_downloads =
      downloads
      |> Map.keys()

    patches_gh_releases =
      for map <- gh_releases do
        map["tag_name"]
        |> String.trim_leading("OTP-")
        |> String.trim_leading("OTP_")
      end

    new_versions =
      for {major, patches} <- versions do
        new_patches =
          (patches ++
             filter_patches_by_major(patches_downloads, major) ++
             filter_patches_by_major(patches_gh_releases, major))
          |> Enum.uniq()
          |> Enum.sort(:desc)

        {major, new_patches}
      end
      |> :lists.reverse()

    releases =
      for {major, patches} <- new_versions do
        process_patches(major, patches, downloads, tags, gh_releases)
      end

    releases_json = create_release_json(releases)
    releases_json_hash = Util.hash(releases_json)

    {releases_json, releases_json_hash}
  end

  defp filter_patches_by_major(patches, major) do
    Enum.filter(patches, &String.starts_with?(&1, major))
  end

  @impl MaintenanceJob
  @spec needs_update?(Maintenance.project(), MaintenanceJob.t(), tuple()) :: boolean()
  def needs_update?(project, db_key, db_value)

  def needs_update?(:beam_langs_meta_data, job, value) when is_atom(job) do
    value != DB.get(:beam_langs_meta_data, job)[:value]
  end

  @impl MaintenanceJob
  @spec run_tasks(Maintenance.project(), [(() -> :ok)], term) :: MaintenanceJob.status()
  def run_tasks(project, tasks, _additional_term \\ nil)
      when is_list(tasks) do
    {:ok, _new_branch, previous_branch} = checkout_new_branch(project)

    [ok: {:otp_releases, otp_releases_hash}] =
      tasks
      |> Task.async_stream(& &1.(), timeout: :infinity)
      |> Enum.to_list()

    pr_data = %{
      title: "Update OTP releases",
      db_key: @job,
      db_value: {:otp_releases, otp_releases_hash}
    }

    # Commit
    commit_msg = "Update otp_releases.json"

    result =
      case Git.commit(project, commit_msg) do
        :ok ->
          submit_pr(project, @job, pr_data)

        {:error, error} ->
          with {msg, 1} <- error,
               "nothing to commit, working tree clean" <-
                 String.trim(msg) |> String.split("\n") |> List.last() do
            fn ->
              Util.info("Project is already up-to-date: " <> inspect(error))
              {:ok, :no_update_needed}
            end
          else
            _ ->
              fn -> raise("Could not commit: " <> inspect(error)) end
          end
      end

    :ok = Git.checkout(project, previous_branch)

    if is_function(result, 0) do
      result.()
    else
      result
    end
  end

  defp checkout_new_branch(project) do
    {:ok, _} = Git.cache_repo(project)

    :ok = Git.checkout(project, config(project, :main_branch))
    {:ok, previous_branch} = Git.get_branch(project)

    new_branch = Util.unique_branch_name(to_string(project))

    :ok = Git.checkout_new_branch(project, new_branch)
    {:ok, new_branch, previous_branch}
  end

  defp submit_pr(project, job, data) do
    case Git.submit_pr(project, job, data) do
      :ok ->
        {:ok, :updated}

      {:error, _} = error ->
        IO.warn("Could not create PR, failed with: " <> inspect(error))
        error
    end
  end

  #########################
  # Helpers

  @doc """
  Gets the versions tables from OTP repository.
  """
  @spec get_versions_table() :: {:ok, contents :: String.t()} | {:error, term()}
  def get_versions_table() do
    result = Req.get!(@version_table_url)

    case result do
      %{status: 200} ->
        {:ok, Map.fetch!(result, :body)}

      error ->
        {:error, error}
    end
  end

  @doc """
  Gets the downloads page from https://erlang.org
  """
  @spec get_downloads() :: {:ok, contents :: String.t()} | {:error, term()}
  def get_downloads() do
    result = Req.get!(@erlang_download_url)

    case result do
      %{status: 200} ->
        {:ok, Map.fetch!(result, :body)}

      error ->
        {:error, error}
    end
  end

  defp parse_otp_versions_table(versions_table) do
    lines =
      versions_table
      |> String.trim()
      |> String.split("\n")

    versions =
      for line <- lines do
        version =
          line
          |> String.split(":", parts: 2)
          |> List.first()
          |> String.trim()
          |> String.trim_leading("OTP-")

        major =
          version
          |> String.split(".", parts: 2)
          |> List.first()

        {version, major}
      end

    # |> Enum.sort()

    Enum.group_by(versions, fn {_k, v} -> v end, fn {k, _v} -> k end)
  end

  @asset_regexes %{
    doc_html: ~R{^otp_(?:doc_)?html_(.*)\.tar\.gz$}s,
    doc_man: ~R{^otp_(?:doc_)?man_(.*)\.tar\.gz$}s,
    readme: ~R{^(?:otp_src_|OTP-)(.*)\.(?:readme|README)$}s,
    source: ~R{^otp_src_(.*)\.tar\.gz$}s,
    win32: ~R{^otp_win32_(.*)\.exe$}s,
    win64: ~R{^otp_win64_(.*)\.exe$}s
  }

  defp parse_erlang_org_downloads() do
    {:ok, the_downloads} = get_downloads()
    downloads = Regex.scan(~r{<a href="([^"/]+)"}, the_downloads, capture: :all_but_first)

    for [download] <- downloads, reduce: %{} do
      vsns ->
        results =
          for {key, regex} <- @asset_regexes, reduce: [] do
            acc ->
              case Regex.run(regex, download, capture: :all_but_first) do
                nil ->
                  acc

                [vsn] ->
                  [{vsn, key} | acc]
              end
          end

        for {vsn, key} <- results, reduce: vsns do
          map ->
            info = Map.get(map, vsn, %{})
            link = @erlang_download_url <> download
            value = Map.put(info, key, link)
            Map.put(map, vsn, value)
        end
    end
  end

  defp process_patches(major, patches, downloads, tags, releases) do
    new_patches = pmap(patches, &process_patch(&1, releases, downloads, tags))
    complete_patches = Enum.filter(new_patches, &is_map_key(&1, :tag_name))

    %{patches: complete_patches, latest: List.first(complete_patches), release: major}
  end

  defp process_patch(patch_vsn, releases, downloads, tags) do
    erlang_org_download = Map.get(downloads, patch_vsn, %{})

    case Enum.find(releases, fn release ->
           tag_name = Map.get(release, "tag_name")

           charlist_equal?(tag_name, 'OTP-' ++ patch_vsn) or
             charlist_equal?(tag_name, 'OTP_' ++ patch_vsn)
         end) do
      nil ->
        {tag_name, tarball_url} = Map.get(tags, patch_vsn, {nil, nil})
        # {:ok, tag_date_time} = Git.get_ref_date_time(:otp, tag_name)
        {:ok, commit_id} = Git.get_commit_id(:otp, tag_name)
        {:ok, commit_date_time} = Git.get_ref_date_time(:otp, commit_id)

        erlang_org_download
        |> Util.convert_keys_to_atoms()
        |> filter_keys(:assets)
        |> Map.merge(%{
          created_at: commit_date_time,
          name: patch_vsn,
          # published_at: tag_date_time,
          tag_name: tag_name,
          tarball_url: tarball_url || erlang_org_download["source"]
        })

      json ->
        {assets, json} = Map.pop(json, "assets", [])
        assets = assets |> Util.convert_keys_to_atoms() |> filter_keys(:assets)

        erlang_org_download
        |> Map.merge(json)
        |> Util.convert_keys_to_atoms()
        # |> tap(&IO.inspect({__ENV__.line, &1, limit: :infinity}))
        |> filter_keys(:otp)
        # |> tap(&IO.inspect({__ENV__.line, &1, limit: :infinity}))
        |> Map.merge(%{
          assets: assets,
          name: patch_vsn,
          download_urls: fetch_urls(assets)
        })
    end
  end

  defp charlist_equal?(charlist1, charlist2) do
    :string.equal(charlist1, charlist2)
  end

  defp fetch_urls(assets) do
    Map.to_list(@asset_regexes)
    |> Enum.flat_map(&fetch_asset(&1, assets))
    |> Enum.into(%{})
  end

  defp fetch_asset({key, match}, assets) do
    case Enum.find(assets, fn asset -> Regex.match?(match, Map.get(asset, :name)) end) do
      nil ->
        []

      value ->
        [{key, Map.get(value, :browser_download_url, "")}]
    end
  end

  defp create_release_json(releases) do
    Jason.encode!(
      for release <- releases do
        Map.merge(release, %{
          latest: release.latest,
          patches:
            for patch <- release.patches do
              patch
            end
        })
      end,
      pretty: true
    )
  end

  defp pmap(collection, func) do
    collection
    |> Enum.map(&Task.async(fn -> func.(&1) end))
    |> Enum.map(&Task.await/1)
  end

  defp parse_github_tags() do
    {:ok, json} = Github.get!(@github_tags_url)

    for tag <- json, into: %{} do
      tag_name = Map.get(tag, "name")

      case Regex.run(~r/OTP[-_](.*)/, tag_name, capture: :all_but_first) do
        nil ->
          {tag_name, {tag_name, Map.get(tag, "tarball_url")}}

        [vsn] ->
          {vsn, {tag_name, Map.get(tag, "tarball_url")}}
      end
    end
  end

  defp filter_keys(term, accepted_keys_atom) when is_atom(accepted_keys_atom) do
    filter_keys(term, accepted_keys(accepted_keys_atom))
  end

  defp filter_keys(term, accepted_keys_list)
       when (is_map(term) or is_list(term)) and is_list(accepted_keys_list) do
    Enum.reduce(term, Util.into(term), fn
      {k, v}, acc ->
        if k in accepted_keys_list do
          Util.into(acc, {k, filter_keys(v, accepted_keys_list)})
        else
          acc
        end

      elem, acc ->
        Util.into(acc, filter_keys(elem, accepted_keys_list))
    end)
  end

  defp filter_keys(term, accepted_keys_list) when is_list(accepted_keys_list) do
    term
  end

  # defp accepted_keys(:all), do: @all_accepted_keys
  defp accepted_keys(:otp), do: @otp_accepted_keys
  defp accepted_keys(:assets), do: @assets_accepted_keys
end
