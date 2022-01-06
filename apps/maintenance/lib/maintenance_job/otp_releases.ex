defmodule MaintenanceJob.OtpReleases do
  @moduledoc """
  OTP Releases job.
  """

  alias Maintenance.Util
  use Util

  @job :otp_releases
  # 5 minutes
  @req_options [receive_timeout: 60_000 * 5]

  @erlang_download_url "https://erlang.org/download/"
  @github_tags_url "https://api.github.com/repos/erlang/otp/tags?per_page=100"
  @version_table_url "https://raw.githubusercontent.com/erlang/otp/master/otp_versions.table"
  @github_releases_url "https://api.github.com/repos/erlang/otp/releases?per_page=100"

  import Maintenance, only: [is_project: 1, info: 1]
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
  @spec job() :: Maintenance.job()
  def job(), do: @job

  @impl MaintenanceJob
  @spec implements_project?(project :: atom) :: boolean
  def implements_project?(:beam_langs_meta_data), do: true
  def implements_project?(project) when is_atom(project), do: false

  @doc """
  Updates the `foo` file in the given `project` by creating a Git commit.
  """
  @impl MaintenanceJob
  @spec update(Maintenance.project()) :: MaintenanceJob.status()
  def update(project) when is_project(project) do
    {:ok, otp_versions_table} = get_versions_table()
    otp_versions_table_hash = Util.hash(String.trim(otp_versions_table))

    if needs_update?(project, @job, {:otp_versions_table, otp_versions_table_hash}) == false do
      info(
        "PR exists: no update needed [#{project}]: " <> DB.get(:beam_langs_meta_data, @job).url
      )

      {:ok, :no_update_needed}
    else
      fn_task_write_foo = fn ->
        versions = parse_otp_versions_table(otp_versions_table)

        downloads = parse_erlang_org_downloads()
        tags = parse_github_tags()

        {:ok, gh_releases} = gh_get(@github_releases_url)

        releases =
          for {major, patches} <- versions do
            process_patches(major, patches, downloads, tags, gh_releases)
          end
          |> :lists.reverse()

        json_path = Path.join(Git.path(project), "priv/otp_releases.json")
        info("Writting opt releases: #{json_path}")

        :ok = File.write(json_path, create_release_json(releases))
        Git.add(project, json_path)

        otp_versions_table_hash = Util.hash(String.trim(otp_versions_table))
        {:otp_versions_table, otp_versions_table_hash}
      end

      run_tasks(project, [fn_task_write_foo])
    end
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
    {:ok, _} = Git.cache_repo(project)

    :ok = Git.checkout(project, config(project, :main_branch))
    {:ok, previous_branch} = Git.get_branch(project)

    new_branch = Util.unique_branch_name(to_string(project))

    if Git.branch_exists?(project, new_branch) do
      :ok = Git.delete_branch(project, new_branch)
    end

    :ok = Git.checkout_new_branch(project, new_branch)

    [ok: {:otp_versions_table, otp_versions_table_hash}] =
      tasks
      |> Task.async_stream(& &1.(), timeout: :infinity)
      |> Enum.to_list()

    data = %{
      title: "Update OTP releases",
      db_key: @job,
      db_value: {:otp_versions_table, otp_versions_table_hash}
    }

    # Commit
    commit_msg = "Update otp_releases.json"

    fn_result =
      case Git.commit(project, commit_msg) do
        :ok ->
          result = submit_pr(project, @job, data)
          fn -> result end

        {:error, error} ->
          with {msg, 1} <- error,
               "nothing to commit, working tree clean" <-
                 String.trim(msg) |> String.split("\n") |> List.last() do
            fn ->
              IO.puts("Project is already up-to-date: " <> inspect(error))
              {:ok, :no_update_needed}
            end
          else
            _ ->
              fn -> raise("Could not commit: " <> inspect(error)) end
          end
      end

    :ok = Git.checkout(project, previous_branch)
    fn_result.()
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
  @spec get_versions_table() :: {:ok, contents :: String.t()} | :error
  def get_versions_table() do
    result = Req.get!(@version_table_url)

    case result do
      %{status: 200} ->
        {:ok, Map.fetch!(result, :body)}

      _ ->
        :error
    end
  end

  @doc """
  Gets the downloads page from https://erlang.org
  """
  @spec get_downloads() :: {:ok, contents :: String.t()} | :error
  def get_downloads() do
    result = Req.get!(@erlang_download_url)

    case result do
      %{status: 200} ->
        {:ok, Map.fetch!(result, :body)}

      _ ->
        :error
    end
  end

  def parse_otp_versions_table(versions_table) do
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

  def parse_erlang_org_downloads() do
    {:ok, the_downloads} = get_downloads()
    downloads = Regex.scan(~r{<a href="([^"/]+)"}, the_downloads, capture: :all_but_first)

    regexes = %{
      readme: ~R{^(?:otp_src_|OTP-)(.*)\.(?:readme|README)$}s,
      erlang_download_readme: ~R{^(?:otp_src_|OTP-)(.*)\.(?:readme|README)$}s,
      html: ~R{^otp_(?:doc_)?html_(.*)\.tar\.gz$}s,
      man: ~R{^otp_(?:doc_)?man_(.*)\.tar\.gz$}s,
      win32: ~R{^otp_win32_(.*)\.exe$}s,
      win64: ~R{^otp_win64_(.*)\.exe$}s,
      src: ~R{^otp_src_(.*)\.tar\.gz$}s
    }

    for [download] <- downloads, reduce: %{} do
      vsns ->
        results =
          for {key, regex} <- regexes, reduce: [] do
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

  def process_patches(major, patches, downloads, tags, releases) do
    new_patches = pmap(patches, &process_patch(&1, releases, downloads, tags))
    complete_patches = Enum.filter(new_patches, &is_map_key(&1, :readme))
    %{patches: complete_patches, latest: List.first(complete_patches), release: major}
  end

  def process_patch(patch_vsn, releases, downloads, tags) do
    erlang_org_download = Map.get(downloads, patch_vsn, %{})

    case Enum.find(releases, fn release ->
           charlist_equal?(Map.get(release, "tag_name"), 'OTP-' ++ patch_vsn)
         end) do
      nil ->
        {tag_name, src} = Map.get(tags, patch_vsn, {nil, nil})
        Map.merge(erlang_org_download, %{tag_name: tag_name, src: src, name: patch_vsn})

      json ->
        assets = fetch_assets(Map.get(json, "assets"))

        patch = %{
          name: patch_vsn,
          tag_name: Map.get(json, "tag_name"),
          published_at: Map.get(json, "published_at"),
          html_url: Map.get(json, "html_url")
        }

        Map.merge(erlang_org_download, Map.merge(patch, assets))
    end
  end

  defp charlist_equal?(charlist1, charlist2) do
    :string.equal(charlist1, charlist2)
  end

  defp fetch_assets(assets) do
    matches = %{
      readme: ~R{^OTP-.*\\.README$},
      html: ~R{^otp_doc_html.*},
      man: ~R{^otp_doc_man.*},
      win32: ~R{^otp_win32.*},
      win64: ~R{^otp_win64.*},
      src: ~R{^otp_src.*}
    }

    Enum.flat_map(Map.to_list(matches), &fetch_asset(&1, assets))
    |> Enum.into(%{})
  end

  defp fetch_asset({key, match}, assets) do
    case Enum.find(assets, fn asset -> Regex.match?(match, Map.get(asset, "name")) end) do
      nil ->
        []

      value ->
        [{key, %{url: Map.get(value, "browser_download_url"), id: Map.get(value, "id")}}]
    end
  end

  defp create_release_json(releases) do
    Jason.encode!(
      for release <- releases do
        Map.merge(release, %{
          latest: strip_ids(release[:latest]),
          patches:
            for patch <- release[:patches] do
              strip_ids(patch)
            end
        })
      end,
      pretty: true
    )
  end

  defp strip_ids(patch) do
    Enum.filter(patch, fn
      {_key, %{id: _, url: url}} ->
        url

      {_, value} ->
        value
    end)
    |> Enum.into(%{})
  end

  defp pmap(collection, func) do
    collection
    |> Enum.map(&Task.async(fn -> func.(&1) end))
    |> Enum.map(&Task.await/1)
  end

  @doc false
  def gh_get(url) do
    request_headers = [
      {"Accept", "application/vnd.github.v3+json"},
      {"Authorization", "token " <> Maintenance.github_access_token!()}
    ]

    response = Req.get!(url, [headers: request_headers] ++ @req_options)

    case response do
      %{status: 200} -> get_link(response)
      _ -> :error
    end
  end

  defp get_link(response = %{headers: headers}) do
    case List.keyfind(headers, "link", 0) do
      {"link", link} ->
        # <https://api.github.com/repositories/374927/releases?per_page=100&page=2>; rel="next", <https://api.github.com/repositories/374927/releases?per_page=100&page=2>; rel="last"
        case Regex.run(~r/<([^>]+)>; rel="next"/, link, capture: :all_but_first) do
          nil ->
            body = Map.fetch!(response, :body)
            {:ok, body}

          [next_url] ->
            {:ok, next_json} = gh_get(next_url)
            body = Map.fetch!(response, :body)
            {:ok, List.wrap(body) ++ next_json}
        end
    end
  end

  def parse_github_tags() do
    {:ok, json} = gh_get(@github_tags_url)

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
end
