# credo:disable-for-this-file Credo.Check.Refactor.AppendSingleItem
defmodule MaintenanceJob.Unicode do
  @moduledoc """
  Updates the Unicode Character Database.
  """

  @behaviour MaintenanceJob

  import Maintenance, only: [is_project: 1]

  alias Maintenance.Git
  alias Maintenance.Util

  @job :unicode
  @req_options Application.compile_env(:maintenance, :unicode_req_options, [])
  @latest_version_url "https://www.unicode.org/versions/latest/"
  @otp_regex_gen_unicode_version ~r/(spec_version\(\)\s+->\s+\{)((?<major>\d+),(?<minor>\d+)(,(?<patch>\d+))?)(\}\.\\n)/

  #############################
  # Types

  @type version :: %Version{}
  @type response :: %Finch.Response{}
  @type response_status :: pos_integer()
  @type download_error ::
          {:download_failed, url :: String.t(), response_status} | Exception.t()
  @type contents :: %{required(file_name :: String.t()) => file_contents :: String.t()}
  @type file_type :: :UCD | :UTS39

  #############################
  # Guards

  defguard is_version(term) when is_struct(term, Version)

  defguard is_file_type(term) when term in [:UCD, :UTS39]

  #############################
  # Callback implementations

  @impl MaintenanceJob
  @spec job() :: MaintenanceJob.t()
  def job(), do: @job

  @impl MaintenanceJob
  @spec implements_project?(atom) :: boolean
  def implements_project?(:elixir), do: true
  def implements_project?(:otp), do: true
  def implements_project?(_project), do: false

  @doc """
  Compares the Unicode version of `project` with the latest one published by unicode.org.

  When either version cannot be found, the error names it and the URL it was looked up in,
  as returned by `get_current_unicode_version/1` and `get_latest_unicode_version/0`.
  """
  @impl MaintenanceJob
  @spec status(Maintenance.project()) ::
          {:due | :up_to_date, MaintenanceJob.info()}
          | {:error,
             {:current_unicode_version_not_found | :latest_unicode_version_not_found,
              url :: String.t()}
             | Exception.t()}
  def status(project) when is_project(project) do
    with {:ok, current} <- get_current_unicode_version(project),
         {:ok, latest} <- get_latest_unicode_version() do
      info = %{current: current, latest: latest, branch: branch(latest)}

      if Version.compare(latest, current) == :gt do
        {:due, info}
      else
        {:up_to_date, info}
      end
    end
  end

  @doc """
  Updates the Unicode files in the checkout of `project` to the `latest` version that
  `status/1` found, and commits them on a new branch.
  """
  @impl MaintenanceJob
  @spec prepare(Maintenance.project(), MaintenanceJob.info()) ::
          {:ok, :committed, String.t()} | {:error, term()}
  def prepare(project, %{latest: latest}) when is_project(project) do
    with {:ok, contents_ucd} <- get(:UCD, latest),
         {:ok, contents_uts39} <- get(:UTS39, latest) do
      prepare(project, latest, %{UCD: contents_ucd, UTS39: contents_uts39})
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
  Converts `string` to version tuple.
  """
  @spec to_tuple(version) :: {Version.major(), Version.minor(), Version.patch()}
  def to_tuple(%Version{major: major, minor: minor, patch: patch}) do
    {major, minor, patch}
  end

  #########################
  # Helpers

  # ELIXIR: The steps for creating the PR, are described at the top of the String.Unicode module source code:
  # Please check them before running this job.
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
  # 10. make unicode

  @spec prepare(Maintenance.project(), version(), %{file_type() => contents()}) ::
          {:ok, :committed, String.t()} | {:error, term()}
  defp prepare(project = :elixir, version, contents) when is_map(contents) do
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
          path = Path.join(dir, Path.basename(file_name))

          File.write!(path, Map.get(contents[file_type], file_name))
        end
      end

    # Update String.Unicode.version/0
    fn_task_special_casing = fn ->
      string_unicode_module_path = Path.join([elixir_dir, "unicode", "unicode.ex"])
      regex_string_unicode_module = ~r/(def\s+version,\s+do:\s+)({\d+\s*,\s+\d+\s*,\s+\d+})/

      string_unicode_module =
        string_unicode_module_path
        |> File.read!()
        |> String.replace(
          regex_string_unicode_module,
          "\\1{#{version.major}, #{version.minor}, #{version.patch}}"
        )

      File.write(string_unicode_module_path, string_unicode_module)
    end

    # Update Unicode version in lib/elixir/pages/references/unicode-syntax.md
    fn_task_unicode_syntax = fn ->
      unicode_syntax_path = Path.join([elixir_dir, "pages/references/unicode-syntax.md"])

      regex_unicode_syntax = ~r{
          (\[Unicode\s+Standard\s+Annex[^\]]+]
          \(https://[^\]]*\),\s+version\s+)
          \d+\.\d+(?:\.\d+)?  # Captures version like 17.0 or 17.0.1
        }x

      regex_uts39 =
        ~r{(\[Unicode Technical Standard #39\]\([^)]+\) on Security, version )\d+\.\d+(?:\.\d+)?}

      unicode_syntax_content =
        unicode_syntax_path
        |> File.read!()
        |> String.replace(regex_unicode_syntax, "\\g{1}#{version.major}.#{version.minor}")
        |> String.replace(regex_uts39, "\\g{1}#{version.major}.#{version.minor}")

      File.write(unicode_syntax_path, unicode_syntax_content)
    end

    # Update String.Unicode.version/0 and on String module docs (version and link)
    fn_task_string_module = fn ->
      string_module_path = Path.join([elixir_dir, "lib", "string.ex"])

      regex_string_module =
        ~r{(\[The Unicode Standard,\s+Version\s+)(\d+\.\d+\.\d+)(\]\([^\)]+/Unicode)(\d+\.\d+\.\d+)(/\)\.)}

      string_module =
        string_module_path
        |> File.read!()
        |> String.replace(regex_string_module, "\\g{1}#{version}\\g{3}#{version}\\g{5}")

      File.write(string_module_path, string_module)
    end

    all_fn_tasks = [
      fn_task_special_casing,
      fn_task_unicode_syntax,
      fn_task_string_module | fn_tasks
    ]

    run_tasks(project, all_fn_tasks, version)
  end

  # OTP: There is no specific documentation on how to update to a new Unicode version,
  # the closest to this is https://github.com/erlang/otp/blob/master/lib/stdlib/uc_spec/README-UPDATE.txt
  # the main source of information is the escript that builds the unicode module:
  # https://github.com/erlang/otp/blob/master/lib/stdlib/uc_spec/gen_unicode_mod.escript
  # https://github.com/erlang/otp/blob/master/lib/stdlib/test/io_proto_SUITE.erl
  #
  # When updating the Unicode version please follow these steps:
  #
  # The latest version of the Unicode Character Database can be found at
  # https://www.unicode.org/Public/UCD/latest/ucd/
  #
  # 1. Copy the following files to lib/stdlib/uc_spec/ replacing existing ones.
  # Nosubfolder should be created.
  #   - CaseFolding.txt
  #   - CompositionExclusions.txt
  #   - DerivedCoreProperties.txt
  #   - EastAsianWidth.txt
  #   - IndicSyllabicCategory.txt
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
  # 5. Replace all occurrences of the previous version of Unicode with the new one in
  # this very same file (lib/stdlib/uc_spec/README-UPDATE.txt).
  # Remember to update these instructions if a new file is added or any other change
  # is required for future version updates.
  #
  # 6. Check if the test file needs to be updated:
  #
  #    $ (cd lib/stdlib/uc_spec; escript gen_unicode_mod.escript update_tests; rm unicode_util.erl)
  #
  # If lib/stdlib/test/unicode_util_SUITE_data/unicode_table.bin is updated include it in
  # the commit.
  #
  # 7. Run the test for the Unicode suite from the OTP repository root dir.
  #
  #    $ export ERL_TOP=$PWD
  #    $ export PATH=$ERL_TOP/bin:$PATH
  #    $ ./otp_build all -a && ./otp_build tests
  #    $ cd release/tests/test_server
  #    $ erl
  #    erl> ts:install().
  #    erl> ts:run(stdlib, unicode_SUITE, [batch]).
  #    $ cd $ERL_TOP
  #
  defp prepare(project = :otp, version, contents) do
    Util.info("Writings files in repo [#{project}, #{version}]")

    git_path = Git.path(project)
    unicode_spec_dir = Path.join([git_path, "lib", "stdlib", "uc_spec"])

    unicode_test_dir = Path.join([git_path, "lib", "stdlib", "test", "unicode_util_SUITE_data"])

    fn_tasks =
      for {dir, file_type, file_path} <- [
            # lib/stdlib/uc_spec/
            {unicode_spec_dir, :UCD, "CaseFolding.txt"},
            {unicode_spec_dir, :UCD, "CompositionExclusions.txt"},
            {unicode_spec_dir, :UCD, "DerivedCoreProperties.txt"},
            {unicode_spec_dir, :UCD, "EastAsianWidth.txt"},
            {unicode_spec_dir, :UCD, "IndicSyllabicCategory.txt"},
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
          dir
          |> Path.join(Path.basename(file_path))
          |> File.write!(Map.get(contents[file_type], file_path))
        end
      end

    # lib/stdlib/uc_spec/README-UPDATE.txt
    fn_task_readme_update = fn ->
      readme_update_path = Path.join([unicode_spec_dir, "README-UPDATE.txt"])
      regex_version = ~r{(\d+\.\d+\.\d+)}

      string_readme_update =
        readme_update_path
        |> File.read!()
        |> String.replace(regex_version, to_string(version))

      File.write(readme_update_path, string_readme_update)
    end

    # lib/stdlib/uc_spec/vendor.info
    fn_task_vendor_info = fn ->
      vendor_info_path = Path.join([unicode_spec_dir, "vendor.info"])

      vendor_info =
        vendor_info_path
        |> File.read!()
        |> update_vendor_info(version)

      File.write(vendor_info_path, vendor_info)
    end

    # lib/stdlib/uc_spec/gen_unicode_mod.escript
    fn_task_gen_unicode = fn ->
      gen_unicode_path = Path.join([unicode_spec_dir, "gen_unicode_mod.escript"])
      gen_unicode_version = build_unicode_version(version)

      string_gen_unicode =
        gen_unicode_path
        |> File.read!()
        |> String.replace(
          @otp_regex_gen_unicode_version,
          "\\g{1}" <> gen_unicode_version <> "\\g{7}"
        )

      File.write(gen_unicode_path, string_gen_unicode)
    end

    # gen_unicode_mod.escript reads the files written above and its own
    # spec_version(), so it must run only after every other task has finished.
    fn_task_update_tests = fn ->
      Enum.each(
        [fn_task_readme_update, fn_task_vendor_info, fn_task_gen_unicode | fn_tasks],
        & &1.()
      )

      update_otp_tests(unicode_spec_dir)
    end

    run_tasks(project, [fn_task_update_tests], version)
  end

  @doc false
  @spec update_vendor_info(String.t(), version) :: String.t()
  def update_vendor_info(vendor_info, version) when is_version(version) do
    vendor_info
    |> String.replace(
      ~r{("downloadLocation": "https://www\.unicode\.org/Public/)[^/"]+(/ucd/")},
      "\\g{1}#{version}\\g{2}"
    )
    |> String.replace(~r{("versionInfo": ")[^"]+(")}, "\\g{1}#{version}\\g{2}")
  end

  defp update_otp_tests(unicode_spec_dir) do
    case System.cmd("escript", ~w(gen_unicode_mod.escript update_tests),
           cd: unicode_spec_dir,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        System.cmd("rm", ~w(unicode_util.erl), cd: unicode_spec_dir)
        :ok

      {output, exit_status} ->
        {:error, {:escript_failed, exit_status, output}}
    end
  end

  defp build_unicode_version(version = %Version{patch: 0}) do
    "#{version.major},#{version.minor}"
  end

  defp build_unicode_version(version) when is_struct(version, Version) do
    "#{version.major},#{version.minor},#{version.patch}"
  end

  # Writes the files and commits them on a new branch, then returns to the branch the
  # checkout was on. If anything fails nothing stays behind: no changes and no branch.
  defp run_tasks(project, tasks, version) do
    new_branch = branch(version)

    with {:ok, _new_branch, previous_branch} <- Git.setup_repo(project, new_branch) do
      commit_tasks(project, tasks, version, new_branch, previous_branch)
    end
  end

  defp commit_tasks(project, tasks, version, new_branch, previous_branch) do
    with :ok <- run_in_parallel(tasks),
         :ok <- Git.commit(project, commit_msg(version)) do
      :ok = Git.checkout(project, previous_branch)

      {:ok, :committed, new_branch}
    else
      {:error, _reason} = error ->
        :ok = Git.discard_changes(project)
        :ok = Git.checkout(project, previous_branch)
        :ok = Git.delete_branch(project, new_branch)

        error
    end
  end

  defp run_in_parallel(tasks) do
    failure =
      tasks
      |> Task.async_stream(& &1.(), timeout: :infinity)
      |> Enum.find(&(&1 != {:ok, :ok}))

    case failure do
      nil -> :ok
      {:ok, {:error, _reason} = error} -> error
      other -> {:error, other}
    end
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

  #############################
  # UCD

  @doc """
  Returns the latest Unicode version available.

  The version is read from the redirect of #{@latest_version_url}. When the page does not
  redirect to the page of a Unicode version, the error is
  `{:latest_unicode_version_not_found, url}`. When the page cannot be fetched, the error is
  the exception of the request, such as `Req.TransportError`.
  """
  @spec get_latest_unicode_version() ::
          {:ok, Version.t()}
          | {:error, {:latest_unicode_version_not_found, String.t()} | Exception.t()}
  def get_latest_unicode_version() do
    with {:ok, response} <-
           Req.request([url: @latest_version_url, redirect: false] ++ @req_options) do
      redirect_url =
        case response do
          %Req.Response{status: 302, headers: %{"location" => [redirect_url]}} -> redirect_url
          _other -> ""
        end

      # "https://www.unicode.org/versions/Unicode15.1.0/"
      case Regex.named_captures(
             ~r{https?://www.unicode.org/versions/Unicode(?<version>\d+\.\d+.\d+)/},
             redirect_url
           ) do
        %{"version" => version} ->
          {:ok, to_version(version)}

        nil ->
          {:error, {:latest_unicode_version_not_found, @latest_version_url}}
      end
    end
  end

  @doc """
  Downloads the zipped Unicode files of `version` and caches them.

  `file_type` can be:
  - `:UCD` - the Unicode Character Database.
  - `:UTS39` - Unicode Technical Standard #39, the Unicode Security Data.

  The files are returned as a map, where the key of every entry is its relative path
  within the zip file. When unicode.org answers with another status than 200, the error
  is `{:download_failed, url, status}`. When the request fails, the error is its exception,
  such as `Req.TransportError`.
  """
  @spec download(file_type, version) :: {:ok, contents} | {:error, download_error}
  def download(:UCD, version) when is_version(version) do
    download(:UCD, version, "https://www.unicode.org/Public/#{version}/ucd/UCD.zip")
  end

  def download(:UTS39, version) when is_version(version) do
    download(
      :UTS39,
      version,
      "https://www.unicode.org/Public/#{version}/security/uts39-data-#{version}.zip"
    )
  end

  defp download(file_type, version, url)
       when is_file_type(file_type) and is_version(version) and is_binary(url) do
    case Req.get(url, [decoders: [:zip]] ++ @req_options) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        contents = Map.new(body, fn {k, v} -> {List.to_string(k), v} end)

        Task.Supervisor.start_child(Maintenance.TaskSupervisor, fn ->
          write(file_type, version, contents)
        end)

        {:ok, contents}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:download_failed, url, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc """
  Gets the `file_type` files of `version`, from the cache when they were downloaded before,
  and otherwise with `download/2`.
  """
  @spec get(file_type, version) :: {:ok, contents} | {:error, download_error}
  def get(file_type, version) when is_file_type(file_type) and is_version(version) do
    case read(file_type, version) do
      {:ok, contents} -> {:ok, contents}
      {:error, _posix} -> download(file_type, version)
    end
  end

  @doc """
  Gets the current Unicode version for the given `project`.

  The version is read from a source file of the project on GitHub. When the file holds no
  version where it is expected, the error is `{:current_unicode_version_not_found, url}`,
  with the URL of the file. When the file cannot be fetched, the error is the exception of
  the request, such as `Req.TransportError`.
  """
  @spec get_current_unicode_version(Maintenance.project()) ::
          {:ok, version}
          | {:error, {:current_unicode_version_not_found, String.t()} | Exception.t()}
  def get_current_unicode_version(project = :elixir) do
    url = current_version_url(project)

    with {:ok, response} <- Req.get(url, @req_options) do
      result =
        Regex.named_captures(~r/def version, do: {(?<version>\d+, \d+, \d+)}/, response.body)

      case result do
        %{"version" => version_string} ->
          version =
            version_string
            |> String.split(",")
            |> Enum.map_join(".", &String.trim/1)
            |> to_version()

          # {:ok, to_version("13.0.0")}
          {:ok, version}

        nil ->
          {:error, {:current_unicode_version_not_found, url}}
      end
    end
  end

  def get_current_unicode_version(project = :otp) do
    url = current_version_url(project)

    with {:ok, response} <- Req.get(url, @req_options) do
      result = Regex.named_captures(@otp_regex_gen_unicode_version, response.body)

      case result do
        %{"major" => major, "minor" => minor, "patch" => ""} ->
          version =
            [major, minor, 0]
            |> Enum.join(".")
            |> to_version()

          {:ok, version}

        %{"major" => major, "minor" => minor, "patch" => patch} ->
          version =
            [major, minor, patch]
            |> Enum.join(".")
            |> to_version()

          {:ok, version}

        nil ->
          {:error, {:current_unicode_version_not_found, url}}
      end
    end
  end

  defp current_version_url(:elixir),
    do: "https://raw.githubusercontent.com/elixir-lang/elixir/main/lib/elixir/unicode/unicode.ex"

  defp current_version_url(:otp),
    do:
      "https://raw.githubusercontent.com/erlang/otp/master/lib/stdlib/uc_spec/gen_unicode_mod.escript"

  #############################
  # Cache

  @doc """
  Return the path of the UCD file for the given `version`·
  """
  @spec get_path(file_type, version()) :: Path.t()
  def get_path(file_type, version) when is_file_type(file_type) and is_version(version) do
    file_type
    |> get_path()
    |> Path.join(to_string(version))
  end

  defp get_path(file_type) when is_file_type(file_type) do
    Path.join(Maintenance.cache_path(), to_string(file_type))
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

    file_contents =
      dir
      |> Path.join("#{file_type}.bin")
      |> File.read()

    case file_contents do
      {:ok, binary} ->
        {:ok, :erlang.binary_to_term(binary)}

      {:error, _error_value} = error ->
        error
    end
  end
end
