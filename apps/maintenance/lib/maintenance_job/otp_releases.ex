defmodule MaintenanceJob.OtpReleases do
  @moduledoc """
  OTP Releases job.
  """

  @job :otp_releases

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
          IO.inspect({__ENV__.line, otp_versions_table})

          versions = parse_otp_versions_table(otp_versions_table)
          IO.inspect({__ENV__.line, versions})

          downloads = parse_erlang_org_downloads()
          IO.inspect({__ENV__.line, downloads})

          # tags = parse_github_tags()
          # IO.inspect {__ENV__.line, tags}

          {:ok, gHReleases} =
            gh_get("https://api.github.com/repos/erlang/otp/releases?per_page=100")

          IO.inspect({__ENV__.line, gHReleases})

          # releases =
          #   Map.map( versions, fn key, val ->
          #     process_patches(key, val, downloads, tags, gHReleases)
          #   end)

          # IO.inspect {__ENV__.line, releases}

          # :ok =
          #   File.write(
          #     Path.join(Maintenance.cache_path(), "otp_releases.json"),
          #     create_release_json(releases)
          #   )

          # :ok

          # info("Writting foo file. [#{project}]")
        end

        run_tasks(project, [fn_task_write_foo])
    end
  end

  @doc """
  Gets the versions tables from OTP repository.
  """
  @spec get_versions_table() :: {:ok, contents :: String.t()} | :error
  def get_versions_table() do
    result = Req.get!("https://raw.githubusercontent.com/erlang/otp/master/otp_versions.table")

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
    result =
      "https://erlang.org/download"
      |> Req.get!()

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
    # case get_versions_table() do
    #   {:ok, _contents} -> false
    #   :error -> true
    # end
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
    :ok = Git.commit(project, "Add foo file")

    data = %{
      title: "Add foo file",
      db_key: @job,
      db_value: true
    }

    result =
      case Git.submit_pr(project, @job, data) do
        :ok ->
          {:ok, :updated}

        {:error, _} = error ->
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

  defp parse_erlang_org_downloads() do
    {:ok, the_downloads} = get_downloads()
    IO.inspect({__ENV__.line, the_downloads})

    downloads = Regex.scan(~r{<a href="([^"/]+)"}, the_downloads, capture: :all_but_first)
    IO.inspect({__ENV__.line, downloads})

    regexes = %{
      readme: ~R{^(?:otp_src_|OTP-)(.*)\.(?:readme|README)$}s,
      erlang_download_readme: ~R{^(?:otp_src_|OTP-)(.*)\.(?:readme|README)$}s,
      html: ~R{^otp_(?:doc_)?html_(.*)\.tar\.gz$}s,
      man: ~R{^otp_(?:doc_)?man_(.*)\.tar\.gz$}s,
      win32: ~R{^otp_win32_(.*)\.exe$}s,
      win64: ~R{^otp_win64_(.*)\.exe$}s,
      src: ~R{^otp_src_(.*)\.tar\.gz$}s
    }

    Enum.reduce(
      downloads,
      %{},
      fn [download], vsns ->
        results =
          Enum.reduce(
            regexes,
            [],
            fn {_key, regex}, acc ->
              case Regex.run(regex, download, capture: :all_but_first) do
                nil ->
                  acc

                x ->
                  [x | acc]
              end
            end
          )

        case results do
          ms ->
            :lists.foldl(
              fn {vsn, key}, map ->
                info = :maps.get(vsn, map, %{})

                Map.put(
                  map,
                  vsn,
                  Map.put(
                    info,
                    key,
                    :erlang.iolist_to_binary(['https://erlang.org/download/', download])
                  )
                )
              end,
              vsns,
              ms
            )
        end
      end
    )
  end

  defp parse_github_tags() do
    {:ok, json} = gh_get("https://api.github.com/repos/erlang/otp/tags?per_page=100")

    :maps.from_list(
      for tag <- json do
        tagName = :maps.get("name", tag)

        case :re.run(tagName, 'OTP[-_](.*)', [{:capture, :all_but_first, :binary}]) do
          {:match, [vsn]} ->
            {vsn, {tagName, :maps.get("tarball_url", tag)}}

          :nomatch ->
            {tagName, {tagName, :maps.get("tarball_url", tag)}}
        end
      end
    )
  end

  defp process_patches(major, patches, downloads, tags, releases) do
    newPatches =
      pmap(
        fn patch ->
          process_patch(patch, releases, downloads, tags)
        end,
        patches
      )

    completePatches =
      :lists.filter(
        fn patch ->
          :maps.is_key(:readme, patch)
        end,
        newPatches
      )

    %{patches: completePatches, latest: hd(completePatches), release: major}
  end

  defp process_patch(patchVsn, releases, downloads, tags) do
    erlangOrgDownload = :maps.get(patchVsn, downloads, %{})

    case :lists.search(
           fn release ->
             :string.equal(:maps.get("tag_name", release), 'OTP-' ++ patchVsn)
           end,
           releases
         ) do
      {:value, json} ->
        assets = fetch_assets(:maps.get("assets", json))

        patch = %{
          name: patchVsn,
          tag_name: :maps.get("tag_name", json),
          published_at: :maps.get("published_at", json),
          html_url: :maps.get("html_url", json)
        }

        :maps.merge(
          erlangOrgDownload,
          :maps.merge(patch, assets)
        )

      false ->
        {tagName, src} = :maps.get(patchVsn, tags, {:undefined, :undefined})

        :maps.merge(
          %{tag_name: tagName, src: src, name: patchVsn},
          erlangOrgDownload
        )
    end
  end

  defp fetch_assets(assets) do
    matches = %{
      readme: '^OTP-.*\\.README$',
      html: '^otp_doc_html.*',
      man: '^otp_doc_man.*',
      win32: '^otp_win32.*',
      win64: '^otp_win64.*',
      src: '^otp_src.*'
    }

    :maps.from_list(
      :lists.flatmap(
        fn {key, match} ->
          case :lists.search(
                 fn asset ->
                   :re.run(
                     :maps.get(
                       "name",
                       asset
                     ),
                     match
                   ) !== :nomatch
                 end,
                 assets
               ) do
            {:value, v} ->
              [{key, %{url: :maps.get("browser_download_url", v), id: :maps.get("id", v)}}]

            false ->
              []
          end
        end,
        :maps.to_list(matches)
      )
    )
  end

  defp create_release_json(releases) do
    Jason.encode(
      Enum.map(
        Map.to_list(releases),
        fn {_Key, release} ->
          Map.merge(release, %{
            latest: strip_ids(Map.get(release, :latest)),
            patches:
              for patch <- Map.get(release, :patches) do
                strip_ids(patch)
              end
          })
        end
      )
    )
  end

  defp strip_ids(patch) do
    Map.map(
      patch,
      fn
        _Key, %{id: _, url: url} ->
          url

        _, value ->
          value
      end
    )
  end

  defp pmap(fun, list) do
    refs =
      for a <- list do
        {_, ref} =
          spawn_monitor(fn ->
            exit(fun.(a))
          end)

        ref
      end

    for ref <- refs do
      receive do
        {:DOWN, ^ref, _, _, value} ->
          value
      end
    end
  end

  # TODO: Implement this function
  defp gh_get(url) do
    request_headers = [
      {"Accept", "application/vnd.github.v3+json"},
      {"Authorization", "token " <> Maintenance.github_access_token!()}
    ]

    response = Req.get!(url, headers: request_headers)

    case response do
      %{status: 200} ->
        get_link(response)

      _ ->
        :error
    end
  end

  defp get_link(%{headers: headers} = response) do
    case List.keyfind(headers, "link", 0) do
      {"link", link} ->
        # <https://api.github.com/repositories/374927/releases?per_page=100&page=2>; rel="next", <https://api.github.com/repositories/374927/releases?per_page=100&page=2>; rel="last"
        case Regex.run(~r/<([^>]+)>; rel="next"/, link, capture: :all_but_first) do
          nil ->
            body = Map.fetch!(response, :body)
            {:ok, Jason.decode!(body)}

          [next_url] ->
            {:ok, next_json} = gh_get(next_url)
            body = Map.fetch!(response, :body)
            {:ok, Jason.decode!(body) ++ next_json}
        end
    end
  end
end
