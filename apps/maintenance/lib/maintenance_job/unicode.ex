defmodule MaintenanceJob.Unicode do
  @moduledoc """
  Updates the Unicode Character Database.
  """

  import Maintenance, only: [is_project: 1]
  import Maintenance.Project, only: [config: 1]
  alias Maintenance.{Git, DB}

  @behaviour MaintenanceJob

  @type version :: %Version{}
  @type response :: %Finch.Response{}
  @type response_status :: pos_integer()
  @type contents :: %{required(file_name :: String.t()) => file_contents :: String.t()}

  @otp_regex_gen_unicode_version ~r/(spec_version\(\)\s+->\s+\{)((?<major>\d+),(?<minor>\d+)(,(?<patch>\d+))?)(\}\.\\n)/

  defguard is_version(term) when is_struct(term, Version)

  #############################
  # Callbacks

  @impl MaintenanceJob
  @spec implements_project?(atom) :: boolean
  def implements_project?(:elixir), do: true
  def implements_project?(:otp), do: true
  def implements_project?(_), do: false

  @doc """
  Updates the Unicode in the given `project` by creating a git commit.
  """
  @impl MaintenanceJob
  @spec update(Maintenance.project()) :: MaintenanceJob.status()
  def update(project) when is_project(project) do
    %{
      needs_update?: needs_update?,
      current_unicode_version: _current_unicode_version,
      latest_unicode_version: latest_unicode_version
    } = calculate_update(project)

    if needs_update? do
      {:ok, contents_ucd} = get_latest_ucd()
      update(project, latest_unicode_version, contents_ucd)
    else
      {:ok, :no_update_needed}
    end
  end

  #############################
  # API

  @doc """
  Converts `string` to `%Version{}` struct.
  """
  @spec to_version(String.t()) :: version
  def to_version(string) when is_binary(string) do
    Version.parse!(string)
  end

  @doc """
  Converts `string` to `%Version{}` struct.
  """
  @spec to_tuple(version) :: {Version.major(), Version.minor(), Version.patch()}
  def to_tuple(%Version{major: major, minor: minor, patch: patch}) do
    {major, minor, patch}
  end

  #########################
  # Helpers

  @spec calculate_update(Maintenance.project()) :: %{
          needs_update?: boolean,
          current_unicode_version: version,
          latest_unicode_version: version
        }
  defp calculate_update(project) when is_project(project) do
    {:ok, current_unicode_version} = get_current_unicode_version(project)
    {:ok, latest_unicode_version} = get_latest_unicode_version()

    %{
      needs_update?: Version.compare(latest_unicode_version, current_unicode_version) == :gt,
      current_unicode_version: current_unicode_version,
      latest_unicode_version: latest_unicode_version
    }
  end

  @doc false
  @spec update(Maintenance.project(), version(), contents()) :: MaintenanceJob.status()
  def update(project = :elixir, version, contents) do
    if pr_exists?(project, :unicode, version) do
      {:ok, :no_update_needed}
    else
      git_path = Git.path(project)
      unicode_dir = Path.join([git_path, "lib", "elixir", "unicode"])
      elixir_dir = Path.join([git_path, "lib", "elixir"])

      fn_tasks =
        for {dir, file_name} <- [
              {unicode_dir, "UnicodeData.txt"},
              {unicode_dir, "PropList.txt"}
            ] do
          fn ->
            File.write!(
              Path.join(dir, Path.basename(file_name)),
              Map.get(contents, file_name)
            )
          end
        end

      # Replace SpecialCasing.txt by copying original and removing conditional mappings
      fn_task_special_casing = fn ->
        regex = ~r{(#\s+=+\n#\s+Conditional Mappings\n.+)(#\s+EOF\n)}s
        special_casing = Regex.replace(regex, Map.get(contents, "SpecialCasing.txt"), "\\2")
        File.write(Path.join(unicode_dir, "SpecialCasing.txt"), special_casing)

        # Update String.Unicode.version/0
        string_unicode_module_path = Path.join([elixir_dir, "unicode", "unicode.ex"])
        regex_string_unicode_module = ~r/(def\s+version,\s+do:\s+)({\d+\s*,\s+\d+\s*,\s+\d+})/

        string_unicode_module =
          File.read!(string_unicode_module_path)
          |> String.replace(
            regex_string_unicode_module,
            "\\1{#{version.major}, #{version.minor}, #{version.patch}}"
          )

        File.write(string_unicode_module_path, string_unicode_module)
      end

      # Update String module docs (version and link)
      fn_task_string_module = fn ->
        string_module_path = Path.join([elixir_dir, "lib", "string.ex"])

        regex_string_module =
          ~r{(\[The Unicode Standard,\s+Version\s+)(\d+\.\d+\.\d+)(\]\([^\)]+/Unicode)(\d+\.\d+\.\d+)(/\)\.)}

        string_module =
          File.read!(string_module_path)
          |> String.replace(regex_string_module, "\\g{1}#{version}\\g{3}#{version}\\g{5}")

        File.write(string_module_path, string_module)
      end

      all_fn_tasks = [fn_task_special_casing, fn_task_string_module | fn_tasks]
      run_tasks(project, version, all_fn_tasks)
    end
  end

  def update(project = :otp, version, contents) do
    if pr_exists?(project, :unicode, version) do
      {:ok, :no_update_needed}
    else
      git_path = Git.path(project)
      unicode_spec_dir = Path.join([git_path, "lib", "stdlib", "uc_spec"])
      unicode_test_dir = Path.join([git_path, "lib", "stdlib", "test", "unicode_util_SUITE_data"])

      fn_tasks =
        for {dir, file_name} <- [
              {unicode_spec_dir, "CaseFolding.txt"},
              {unicode_spec_dir, "CompositionExclusions.txt"},
              {unicode_spec_dir, "PropList.txt"},
              {unicode_spec_dir, "SpecialCasing.txt"},
              {unicode_spec_dir, "UnicodeData.txt"},
              {unicode_spec_dir, "emoji/emoji-data.txt"},
              {unicode_test_dir, "auxiliary/GraphemeBreakProperty.txt"},
              {unicode_test_dir, "auxiliary/GraphemeBreakTest.txt"},
              {unicode_test_dir, "auxiliary/LineBreakTest.txt"},
              {unicode_test_dir, "NormalizationTest.txt"}
            ] do
          fn ->
            File.write!(
              Path.join(dir, Path.basename(file_name)),
              Map.get(contents, file_name)
            )
          end
        end

      # lib/stdlib/uc_spec/README-UPDATE.txt
      fn_task_readme_update = fn ->
        readme_update_path = Path.join([unicode_spec_dir, "README-UPDATE.txt"])
        regex_version = ~r{(\d+\.\d+\.\d+)}

        string_readme_update =
          File.read!(readme_update_path)
          |> String.replace(regex_version, to_string(version))

        File.write(readme_update_path, string_readme_update)
      end

      # lib/stdlib/uc_spec/gen_unicode_mod.escript
      fn_task_gen_unicode = fn ->
        gen_unicode_path = Path.join([unicode_spec_dir, "gen_unicode_mod.escript"])

        string_gen_unicode =
          File.read!(gen_unicode_path)
          |> String.replace(
            @otp_regex_gen_unicode_version,
            "\\g{1}#{version.major},#{version.minor}\\g{3}"
          )

        File.write(string_gen_unicode, string_gen_unicode)
      end

      all_fn_tasks = [fn_task_readme_update, fn_task_gen_unicode | fn_tasks]
      run_tasks(project, version, all_fn_tasks)
    end
  end

  @spec run_tasks(Maintenance.project(), version(), [(() -> :ok)]) :: {:ok, :updated}
  def run_tasks(project, version, tasks)
      when is_list(tasks) do
    {:ok, _} = Git.cache_repo(project)

    config = config(project)

    :ok = Git.checkout(project, config.main_branch)
    {:ok, previous_branch} = Git.get_branch(project)

    new_branch = branch(version)

    if Git.branch_exists?(project, new_branch) do
      :ok = Git.delete_branch(project, new_branch)
    end

    :ok = Git.checkout_new_branch(project, new_branch)

    tasks
    |> Task.async_stream(& &1.(), timeout: :infinity)
    |> Stream.run()

    # Commit
    :ok = Git.commit(project, commit_msg(version))

    data = %{
      title: "Update Unicode to #{version}",
      db_key: {:unicode, MaintenanceJob.Unicode.to_tuple(version)},
      db_value: version
    }

    :ok = Git.submit_pr(project, :unicode, data)
    :ok = Git.checkout(project, previous_branch)

    {:ok, :updated}
  end

  defp commit_msg(unicode_version) when is_version(unicode_version) do
    """
    Update Unicode to version #{unicode_version}

    This is an automated commit created by the Maintenance project
    #{Maintenance.git_repo_url()}
    """
  end

  defp branch(version) when is_version(version) do
    "unicode_#{version}"
  end

  defp pr_exists?(project, job, version)
       when is_project(project) and is_atom(job) and is_version(version) do
    if get_unicode_db_entry(project, job, version) do
      true
    else
      false
    end
  end

  defp pr_exists?(project, job, version)
       when is_project(project) and is_atom(job) and is_version(version) do
    {:ok, result} = DB.select(project, min_key: {job, 0}, reverse: true, pipe: [take: 1])

    case result do
      [{_, result}] ->
        if Version.compare(version, result.version) == :gt do
          false
        else
          true
        end

      [] ->
        false
    end
  end

  defp get_unicode_db_entry(project, job, version)
       when is_project(project) and is_atom(job) and is_version(version) do
    DB.get(project, {job, to_tuple(version)})
  end

  #############################
  # UCD

  @doc """
  Returns the latest Unicode version available.
  """
  @spec get_latest_unicode_version() :: {:ok, %Version{}} | :error
  def get_latest_unicode_version() do
    result =
      "https://www.unicode.org/Public/UCD/latest/ReadMe.txt"
      |> Req.get!()
      |> then(
        &Regex.named_captures(
          ~r{https://www.unicode.org/Public/zipped/(?<version>\d+\.\d+.\d+)/},
          &1.body
        )
      )

    case result do
      nil -> :error
      %{"version" => version} -> {:ok, to_version(version)}
    end
  end

  @doc """
  Get the UCD zipped file.

  If it has been previously retrieved, it will be obtained from the cache.
  """
  @spec get_ucd(version) :: {:ok, contents} | {:error, Mint.Types.status()}
  def get_ucd(version) when is_version(version) do
    response = Req.get!("https://www.unicode.org/Public/zipped/#{version}/UCD.zip")

    case response.status do
      200 ->
        body = Map.new(response.body, fn {k, v} -> {List.to_string(k), v} end)

        Task.Supervisor.start_child(Maintenance.TaskSupervisor, fn ->
          write(version, body)
        end)

        {:ok, body}

      _ ->
        {:error, response.status}
    end
  end

  @doc """
  Gets the latest UCD zipped file.
  """
  @spec get_latest_ucd() ::
          {:ok, contents}
          | {:error, response_status}
  def get_latest_ucd() do
    {:ok, latest_version} = get_latest_unicode_version()

    case read(latest_version) do
      {:ok, contents} ->
        {:ok, contents}

      {:error, _} ->
        case get_ucd(latest_version) do
          {:ok, contents} ->
            {:ok, contents}

          {:error, error_status} ->
            {:error, error_status}
        end
    end
  end

  @doc """
  Gets the current Unicode version for the given `project`.
  """
  @spec get_current_unicode_version(Maintenance.project()) :: {:ok, version} | :error
  def get_current_unicode_version(:elixir) do
    result =
      "https://raw.githubusercontent.com/elixir-lang/elixir/main/lib/elixir/unicode/unicode.ex"
      |> Req.get!()
      |> then(&Regex.named_captures(~r/def version, do: {(?<version>\d+, \d+, \d+)}/, &1.body))

    case result do
      %{"version" => version_string} ->
        version =
          String.split(version_string, ",")
          |> Enum.map(&String.trim/1)
          |> Enum.join(".")
          |> to_version()

        # {:ok, to_version("13.0.0")}
        {:ok, version}

      nil ->
        :error
    end
  end

  def get_current_unicode_version(:otp) do
    result =
      Req.get!(
        "https://raw.githubusercontent.com/erlang/otp/master/lib/stdlib/uc_spec/gen_unicode_mod.escript"
      )
      |> then(&Regex.named_captures(@otp_regex_gen_unicode_version, &1.body))

    case result do
      %{"major" => major, "minor" => minor, "patch" => ""} ->
        version = Enum.join([major, minor, 0], ".") |> to_version()
        {:ok, version}

      %{"major" => major, "minor" => minor, "patch" => patch} ->
        version = Enum.join([major, minor, patch], ".") |> to_version()
        {:ok, version}

      nil ->
        :error
    end
  end

  #############################
  # Cache

  @doc """
  Return the path of the UCD file for the given `version`·
  """
  @spec ucd_path(version()) :: Path.t()
  def ucd_path(version) when is_version(version) do
    Path.join(ucd_path(), to_string(version))
  end

  defp ucd_path() do
    Maintenance.cache_path() |> Path.join("UCD")
  end

  @doc """
  Writes the UCD file in Erlang terms contents.
  """
  @spec write(version(), contents()) :: :ok
  def write(version, contents) when is_version(version) do
    dir = ucd_path(version)
    tmp_dir = Path.join([dir, Integer.to_string(System.monotonic_time(:nanosecond))])
    File.mkdir_p!(tmp_dir)

    tmp_path = Path.join([tmp_dir, "UCD.bin"])
    File.write!(tmp_path, :erlang.term_to_binary(contents))

    path = Path.join([dir, "UCD.bin"])
    File.rename!(tmp_path, path)
    File.rmdir(tmp_dir)
  end

  @doc """
  Reads the UCD file cached by the give `version`.
  """
  @spec read(version()) :: {:ok, contents()} | {:error, File.posix()}
  def read(version) when is_version(version) do
    dir = ucd_path(version)

    case File.read(Path.join(dir, "UCD.bin")) do
      {:ok, binary} ->
        {:ok, :erlang.binary_to_term(binary)}

      {:error, _} = error ->
        error
    end
  end
end
