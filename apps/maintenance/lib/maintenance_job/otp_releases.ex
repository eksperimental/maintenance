defmodule MaintenanceJob.OtpReleases do
  @moduledoc """
  OTP Releases job.
  """

  @job :otp_releases

  @erlang_download_url "https://erlang.org/download"
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

  defmacrop debug(term) do
    quote bind_quoted: [term: term, line: __CALLER__.line] do
      IO.inspect({line, term}, limit: :infinity, printable_limit: :infinity)
      term
    end
  end

  #############################
  # Callbacks

  @impl MaintenanceJob
  @spec job() :: Maintenance.job()
  def job(), do: @job

  @impl MaintenanceJob
  @spec implements_project?(project :: atom) :: boolean
  def implements_project?(:beam_langs_meta_data), do: true
  def implements_project?(_), do: false

  @doc """
  Updates the `foo` file in the given `project` by creating a Git commit.
  """
  @impl MaintenanceJob
  @spec update(Maintenance.project()) :: MaintenanceJob.status()
  def update(project) when is_project(project) do
    cond do
      not needs_update?(project) ->
        {:ok, :no_update_needed}

      pr_exists?(project, @job) ->
        info("PR exists: no update needed [#{project}]")
        {:ok, :no_update_needed}

      true ->
        fn_task_write_foo = fn ->
          {:ok, otp_versions_table} = get_versions_table()
          # {:ok, otp_versions_table} = Data.get_versions_table()

          versions = parse_otp_versions_table(otp_versions_table)
          # debug(versions)
          # debug(otp_versions_table)

          downloads = parse_erlang_org_downloads()
          tags = parse_github_tags()

          {:ok, gh_releases} = gh_get(@github_releases_url)
          # {:ok, gh_releases} = Data.gh_get()

          releases =
            for {major, patches} <- versions do
              process_patches(major, patches, downloads, tags, gh_releases)
            end

          json_path = Path.join(Git.path(project), "priv/otp_releases.json")
          info("Writting opt releases: #{json_path}")

          :ok = File.write(json_path, create_release_json(releases))
          Git.add(project, json_path)
        end

        run_tasks(project, [fn_task_write_foo])
    end
  end

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

  #########################
  # Helpers

  defp bool(term), do: not (!term)

  def needs_update?(_project) do
    # {:ok, otp_versions_table} = get_versions_table()

    # latest_otp_version =
    #   otp_versions_table
    #   |> Enum.at(-1)
    #   |> elem(1)
    #   |> List.first()

    # json_path = Path.join(Git.path(project), "priv/otp_releases.json")

    # otp_releases = Jason.decode(json_path)

    true
  end

  @spec run_tasks(Maintenance.project(), [(() -> :ok)]) :: MaintenanceJob.status()
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
    :ok = Git.commit(project, "Update otp_releases.json")

    data = %{
      title: "Update OTP releases",
      db_key: @job,
      db_value: true
    }

    result =
      case Git.submit_pr(project, @job, data) do
        :ok ->
          {:ok, :updated}

        {:error, _} = error ->
          IO.inspect(data)
          IO.warn("Could not create PR, failed with: " <> inspect(error))
          error
      end

    :ok = Git.checkout(project, previous_branch)

    result
  end

  defp pr_exists?(:beam_langs_meta_data, job) when is_atom(job) do
    bool(get_sample_project_db_entry(:beam_langs_meta_data, job))
  end

  defp get_sample_project_db_entry(project, job)
       when is_project(project) and is_atom(job) do
    DB.get(project, job)
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
            link = @erlang_download_url <> "/" <> download
            value = Map.put(info, key, link)
            Map.put(map, vsn, value)
        end
    end
  end

  def process_patches(major, patches, downloads, tags, releases) do
    new_patches = pmap(patches, &process_patch(&1, releases, downloads, tags))
    complete_patches = Enum.filter(new_patches, &is_map_key(&1, :readme))
    %{patches: complete_patches, latest: List.last(complete_patches), release: major}
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

    Enum.flat_map(
      Map.to_list(matches),
      fn {key, match} ->
        case Enum.find(assets, fn asset -> Regex.match?(match, Map.get(asset, "name")) end) do
          nil ->
            []

          value ->
            [{key, %{url: Map.get(value, "browser_download_url"), id: Map.get(value, "id")}}]
        end
      end
    )
    |> Enum.into(%{})
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
      {_Key, %{id: _, url: url}} ->
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

  defp gh_get(url) do
    request_headers = [
      {"Accept", "application/vnd.github.v3+json"},
      {"Authorization", "token " <> Maintenance.github_access_token!()}
    ]

    response = Req.get!(url, headers: request_headers)

    case response do
      %{status: 200} -> get_link(response)
      _ -> :error
    end
  end

  defp get_link(%{headers: headers} = response) do
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
            {:ok, body ++ next_json}
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
