defmodule MaintenanceJob.Unicode do
  @moduledoc """
  Updates the Unicode Character Database.
  """

  import Maintenance, only: [is_project: 1]
  import Maintenance.Project, only: [config: 1]
  alias Maintenance.{Git, DB, Util}
  use Util

  @behaviour MaintenanceJob

  @type version :: %Version{}
  @type response :: %Finch.Response{}
  @type response_status :: pos_integer()
  @type contents :: %{required(file_name :: String.t()) => file_contents :: String.t()}
  @type file_type :: :UCD | :UTS39

  @job :unicode
  @otp_regex_gen_unicode_version ~r/(spec_version\(\)\s+->\s+\{)((?<major>\d+),(?<minor>\d+)(,(?<patch>\d+))?)(\}\.\\n)/

  defguard is_version(term) when is_struct(term, Version)

  defguard is_file_type(term) when term in [:UCD, :UTS39]

  #############################
  # Callbacks

  @impl MaintenanceJob
  @spec job() :: MaintenanceJob.t()
  def job(), do: @job

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
      {:ok, contents_ucd} = get_latest(:UCD)
      {:ok, contents_uts39} = get_latest(:UTS39)
      update(project, latest_unicode_version, %{UCD: contents_ucd, UTS39: contents_uts39})
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

  # ELIXIR: The steps for creating the PR, are described at the top of the String.Unicode module source code:
  # https://github.com/elixir-lang/elixir/blob/main/lib/elixir/unicode/unicode.ex
  #
  # How to update the Unicode files
  # Unicode files can be found in https://www.unicode.org/Public/VERSION_NUMBER/ where VERSION_NUMBER
  # is the current Unicode version.
  #
  # 1. Replace UnicodeData.txt by copying original
  # 2. Replace PropertyValueAliases.txt by copying original
  # 3. Replace PropList.txt by copying original
  # 4. Replace ScriptExtensions.txt by copying original
  # 5. Replace Scripts.txt by copying original
  # 6. Replace SpecialCasing.txt by copying original
  # 7. Replace confusables.txt by copying original
  #    (from https://www.unicode.org/Public/security/VERSION_NUMBER/)
  # 8. Replace IdentifierType.txt by copying original
  #    (from https://www.unicode.org/Public/security/VERSION_NUMBER/)
  # 9. Update String.Unicode.version/0 and on String module docs (version and link)
  @doc false
  @spec update(Maintenance.project(), version(), %{file_type() => contents()}) ::
          MaintenanceJob.status()
  def update(project = :elixir, version, contents) when is_map(contents) do
    if pr_exists?(project, @job, version) do
      Util.info("PR exists: no update needed [#{project}]")
      {:ok, :no_update_needed}
    else
      Util.info("Writing files in repo [#{project}]")

      git_path = Git.path(project)
      unicode_dir = Path.join([git_path, "lib", "elixir", "unicode"])
      elixir_dir = Path.join([git_path, "lib", "elixir"])

      # UCD
      # Replace UnicodeData.txt by copying original
      # Replace PropertyValueAliases.txt by copying original
      # Replace PropList.txt by copying original
      # Replace ScriptExtensions.txt by copying original
      # Replace Scripts.txt by copying original
      # Replace SpecialCasing.txt by copying original

      # UTS39
      # Replace confusables.txt by copying original
      #  (from https://www.unicode.org/Public/security/VERSION_NUMBER/)
      # Replace IdentifierType.txt by copying original
      #  (from https://www.unicode.org/Public/security/VERSION_NUMBER/)

      fn_tasks =
        for {dir, file_type, file_name} <- [
              # UCD
              {unicode_dir, :UCD, "UnicodeData.txt"},
              {unicode_dir, :UCD, "PropertyValueAliases.txt"},
              {unicode_dir, :UCD, "PropList.txt"},
              {unicode_dir, :UCD, "ScriptExtensions.txt"},
              {unicode_dir, :UCD, "Scripts.txt"},
              {unicode_dir, :UCD, "SpecialCasing.txt"},

              # UTS39
              {unicode_dir, :UTS39, "confusables.txt"},
              {unicode_dir, :UTS39, "IdentifierType.txt"}
            ] do
          fn ->
            File.write!(
              Path.join(dir, Path.basename(file_name)),
              Map.get(contents[file_type], file_name)
            )
          end
        end

      fn_task_special_casing = fn ->
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

      # Update String.Unicode.version/0 and on String module docs (version and link)
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
      run_tasks(project, all_fn_tasks, version)
    end
  end

  # OTP: There is no specific documentation on how to update to a new Unicode version,
  # the closes to this is https://github.com/erlang/otp/blob/master/lib/stdlib/uc_spec/README-UPDATE.txt
  # the main source of information is the escript that builds the unicode module:
  # https://github.com/erlang/otp/blob/master/lib/stdlib/uc_spec/gen_unicode_mod.escript
  # https://github.com/erlang/otp/blob/master/lib/stdlib/test/io_proto_SUITE.erl
  #
  # When updating the Unicode version please follow these steps:
  #
  # The latest vesrion of the Unicode Character Database can be found at
  # https://www.unicode.org/Public/UCD/latest/ucd/
  #
  # 1. Copy the following files to lib/stdlib/uc_spec/ replacing existing ones.
  # Nosubfolder should be created.
  #   - CaseFolding.txt
  #   - CompositionExclusions.txt
  #   - EastAsianWidth.txt
  #   - PropList.txt
  #   - SpecialCasing.txt
  #   - UnicodeData.txt
  #   - auxiliary/GraphemeBreakProperty.txt
  #   - emoji/emoji-data.txt
  #
  # 2. Copy the following test files to lib/stdlib/test/unicode_util_SUITE_data/
  # replacing existing ones. No subfolder should be created.
  #   - NormalizationTest.txt
  #   - auxiliary/GraphemeBreakTest.txt
  #   - auxiliary/LineBreakTest.txt
  #
  # 3. Update the "spec_version()" function in the generator by replacing the Unicode
  # version in lib/stdlib/uc_spec/gen_unicode_mod.escript
  #
  # 4. Read the release notes by visiting https://www.unicode.org/versions/latest/
  # and assess if additional changes are necessary in the Erlang code.
  #
  # 5. Replace all ocurrences of previous version of Unicode with the new one in
  # this very same file (lib/stdlib/uc_spec/README-UPDATE.txt).
  # Remember to update these instructions if a new file is added or any other change
  # is required for future version updates.
  #
  # 6. Run the test for the Unicode suite from the OTP repository root dir.
  #    $ export ERL_TOP=$PWD
  #    $ export PATH=$ERL_TOP/bin:$PATH
  #    $ ./otp_build all -a && ./otp_build tests
  #    $ cd release/tests/test_server
  #    $ erl
  #    erl> ts:install().
  #    erl> ts:run(stdlib, unicode_SUITE, [batch]).
  #
  def update(project = :otp, version, contents) do
    if pr_exists?(project, @job, version) do
      Util.info("PR exists: no update needed [#{project}, #{version}]")
      {:ok, :no_update_needed}
    else
      Util.info("Writtings files in repo [#{project}, #{version}]")

      git_path = Git.path(project)
      unicode_spec_dir = Path.join([git_path, "lib", "stdlib", "uc_spec"])

      unicode_test_dir = Path.join([git_path, "lib", "stdlib", "test", "unicode_util_SUITE_data"])

      fn_tasks =
        for {dir, file_type, file_path} <- [
              # lib/stdlib/uc_spec/
              {unicode_spec_dir, :UCD, "CaseFolding.txt"},
              {unicode_spec_dir, :UCD, "CompositionExclusions.txt"},
              {unicode_spec_dir, :UCD, "EastAsianWidth.txt"},
              {unicode_spec_dir, :UCD, "PropList.txt"},
              {unicode_spec_dir, :UCD, "SpecialCasing.txt"},
              {unicode_spec_dir, :UCD, "UnicodeData.txt"},
              {unicode_spec_dir, :UCD, "auxiliary/GraphemeBreakProperty.txt"},
              {unicode_spec_dir, :UCD, "emoji/emoji-data.txt"},

              # lib/stdlib/test/unicode_util_SUITE_data/
              {unicode_test_dir, :UCD, "NormalizationTest.txt"},
              {unicode_test_dir, :UCD, "auxiliary/GraphemeBreakTest.txt"},
              {unicode_test_dir, :UCD, "auxiliary/LineBreakTest.txt"}
            ] do
          fn ->
            File.write!(
              Path.join(dir, Path.basename(file_path)),
              Map.get(contents[file_type], file_path)
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

        gen_unicode_version =
          if version.patch == 0 do
            "#{version.major},#{version.minor}"
          else
            "#{version.major},#{version.minor},#{version.patch}"
          end

        string_gen_unicode =
          String.replace(
            File.read!(gen_unicode_path),
            @otp_regex_gen_unicode_version,
            "\\g{1}" <> gen_unicode_version <> "\\g{7}"
          )

        File.write(gen_unicode_path, string_gen_unicode)
      end

      all_fn_tasks = [fn_task_readme_update, fn_task_gen_unicode | fn_tasks]
      run_tasks(project, all_fn_tasks, version)
    end
  end

  @impl MaintenanceJob
  @spec run_tasks(Maintenance.project(), [(() -> :ok)], version()) :: MaintenanceJob.status()
  def run_tasks(project, tasks, version)
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
      db_key: {@job, MaintenanceJob.Unicode.to_tuple(version)},
      db_value: version
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

  defp commit_msg(unicode_version) when is_version(unicode_version) do
    """
    Update Unicode to version #{unicode_version}

    This is an automated commit created by the Maintenance project
    #{Maintenance.git_repo_url()}

    Before merging, please read the release notes by visiting
    <http://www.unicode.org/versions/Unicode#{unicode_version}/>
    and assess if additional changes are necessary in the code base.
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
  @spec get_latest_unicode_version() :: {:ok, Version.t()} | :error
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
  Gets a Unicode file.

  `file_type` can be:
  - `:UCD` - Retrives the Unicode Character Database in zippped format.
  - `:UTS39` -  Unicode Technical Standard #39; retrieves the Unicode Security Data in zipped format.

  If it has been previously retrieved, it will be obtained from the cache.
  The file zip file is received and stored as a map, where the key of every entry
  is the relative path within the zip file.
  """
  @spec get!(file_type, version) :: {:ok, contents} | {:error, Mint.Types.status()}
        when file_type: :UCD | :UTS39
  def get!(:UCD, version) when is_version(version) do
    get!(:UCD, version, "https://www.unicode.org/Public/zipped/#{version}/UCD.zip")
  end

  def get!(:UTS39, version) when is_version(version) do
    get!(
      :UTS39,
      version,
      "https://www.unicode.org/Public/security/#{version}/uts39-data-#{version}.zip"
    )
  end

  defp get!(file_type, version, url)
       when is_file_type(file_type) and is_version(version) and is_binary(url) do
    response = Req.get!(url)

    case response.status do
      200 ->
        body = Map.new(response.body, fn {k, v} -> {List.to_string(k), v} end)

        Task.Supervisor.start_child(Maintenance.TaskSupervisor, fn ->
          write(file_type, version, body)
        end)

        {:ok, body}

      _ ->
        {:error, response.status}
    end
  end

  @doc """
  Gets the latest UCD zipped file.
  """
  @spec get_latest(file_type) :: {:ok, contents} | {:error, response_status}
  def get_latest(file_type) when is_file_type(file_type) do
    {:ok, latest_version} = get_latest_unicode_version()

    case read(file_type, latest_version) do
      {:ok, contents} ->
        {:ok, contents}

      {:error, _} ->
        case get!(file_type, latest_version) do
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
      # "https://raw.githubusercontent.com/maintenance-beam/elixir/main/lib/elixir/unicode/unicode.ex"
      |> Req.get!()
      |> then(&Regex.named_captures(~r/def version, do: {(?<version>\d+, \d+, \d+)}/, &1.body))

    case result do
      %{"version" => version_string} ->
        version =
          String.split(version_string, ",")
          |> Enum.map_join(".", &String.trim/1)
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
  @spec get_path(file_type, version()) :: Path.t()
  def get_path(file_type, version) when is_file_type(file_type) and is_version(version) do
    Path.join(get_path(file_type), to_string(version))
  end

  defp get_path(file_type) when is_file_type(file_type) do
    Maintenance.cache_path() |> Path.join(to_string(file_type))
  end

  @doc """
  Writes the UCD file in Erlang terms contents.
  """
  @spec write(file_type, version(), contents()) :: :ok
  def write(file_type, version, contents) when is_file_type(file_type) and is_version(version) do
    dir = get_path(file_type, version)
    tmp_dir = Path.join([dir, Integer.to_string(System.monotonic_time(:nanosecond))])
    File.mkdir_p!(tmp_dir)

    tmp_path = Path.join([tmp_dir, "#{file_type}.bin"])
    File.write!(tmp_path, :erlang.term_to_binary(contents))

    path = Path.join([dir, "#{file_type}.bin"])
    File.rename!(tmp_path, path)
    File.rmdir(tmp_dir)
  end

  @doc """
  Reads the UCD file cached by the give `version`.
  """
  @spec read(file_type, version()) :: {:ok, contents()} | {:error, File.posix()}
  def read(file_type, version) when is_file_type(file_type) and is_version(version) do
    dir = get_path(file_type, version)

    case File.read(Path.join(dir, "#{file_type}.bin")) do
      {:ok, binary} ->
        {:ok, :erlang.binary_to_term(binary)}

      {:error, _} = error ->
        error
    end
  end
end
