defmodule Maintenance.Project do
  @moduledoc """
  Module that contains the specific code for udpating each project.
  """

  import Maintenance, only: [default: 2, is_project: 1]
  import Maintenance.UCD, only: [is_version: 1]
  alias Maintenance.{Git, UCD, DB}

  @doc false
  @spec update(Maintenance.project(), UCD.version(), UCD.contents()) :: :ok | nil
  def update(project = :elixir, version, contents) do
    if pr_exists?(project, :unicode, version) do
      :ok
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
      run_update(project, version, all_fn_tasks)
    end
  end

  def update(project = :otp, version, contents) do
    if pr_exists?(project, :unicode, version) do
      :ok
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
            default(:otp, :regex_gen_unicode_version),
            "\\g{1}#{version.major},#{version.minor}\\g{3}"
          )

        File.write(string_gen_unicode, string_gen_unicode)
      end

      all_fn_tasks = [fn_task_readme_update, fn_task_gen_unicode | fn_tasks]
      run_update(project, version, all_fn_tasks)
    end
  end

  @spec run_update(Maintenance.project(), UCD.version(), [(() -> :ok)]) :: :ok
  def run_update(project, version, tasks)
      when is_list(tasks) do
    {:ok, _} = Git.cache_repo(project)

    :ok = Git.checkout(project, default(project, :main_branch))
    {:ok, previous_branch} = Git.get_branch(project)

    new_branch = branch(version)

    if Git.branch_exists?(project, new_branch) do
      :ok = Git.delete_branch(project, new_branch)
    end

    :ok = Git.checkout_new_branch(project, new_branch)

    tasks
    |> Task.async_stream(& &1.())
    |> Stream.run()

    # Commit
    :ok = Git.commit(project, unicode_commit_msg(version))
    :ok = Git.submit_pr(project, :unicode, %{version: version})
    :ok = Git.checkout(project, previous_branch)
  end

  defp unicode_commit_msg(unicode_version) when is_version(unicode_version) do
    """
    Update Unicode to version #{unicode_version}

    This is an automated commit.
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

  # defp get_latest_unicode_db_entry(project, job, version)
  #      when is_project(project) and is_atom(job) and is_version(version) do
  #   {:ok, results} = DB.select(project, min_key: {job, 0}, reverse: true, pipe: [take: 1])

  #   case results do
  #     [{_, entry}] -> entry
  #     [] -> nil
  #   end
  # end

  defp get_unicode_db_entry(project, job, version)
       when is_project(project) and is_atom(job) and is_version(version) do
    DB.get(project, {job, UCD.to_tuple(version)})
  end

  def list_entries_by_job(project, job) when is_project(project) and is_atom(job) do
    # {:ok, result} = DB.select(project, min_key: {job, 0}, reverse: true, pipe: [reduce: fn ])
    {:ok, results} = DB.select(project, reverse: true)

    Enum.filter(results, fn
      {{^job, _}, _v} ->
        true

      _ ->
        false
    end)
  end

  def list() do
    Maintenance.projects()
  end
end
