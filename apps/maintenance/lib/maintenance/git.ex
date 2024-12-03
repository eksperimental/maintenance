defmodule Maintenance.Git do
  @moduledoc """
  Module that deals with the Git commands.
  """

  import Maintenance, only: [cache_path: 0, is_project: 1, is_job: 1]

  require Logger

  alias Maintenance.DB
  alias Maintenance.Project
  alias Maintenance.Util

  @type branch :: String.t()

  @doc false
  @spec config(Maintenance.project()) ::
          :ok | {:error, {Collectable.t(), exit_status :: non_neg_integer()}}
  def config(project) when is_project(project) do
    author_name = Project.config(project, :author_name) || Maintenance.author_name()
    author_email = Project.config(project, :author_email) || Maintenance.author_email()

    repo_path = path(project)
    :ok = File.mkdir_p!(repo_path)

    with {_, 0} <- System.cmd("git", ~w(config pull.ff only), cd: repo_path),
         _ <-
           System.cmd("git", ~w(config user.name #{author_name}), cd: repo_path),
         _ <-
           System.cmd("git", ~w(config user.email #{author_email}), cd: repo_path),
         _ <- System.cmd("git", ~w(config advice.addIgnoredFile false), cd: repo_path),
         _ <- System.cmd("git", ~w(config fetch.fsckobjects true), cd: repo_path),
         _ <- System.cmd("git", ~w(config transfer.fsckobjects true), cd: repo_path),
         _ <- System.cmd("git", ~w(config receive.fsckobjects true), cd: repo_path) do
      :ok
    else
      error -> {:error, error}
    end
  end

  @doc """
  Returns the last commit of the given cached Git `project` repository.
  """
  @spec get_last_commit_id(Maintenance.project()) :: {:ok, String.t()} | {:error, term}
  def get_last_commit_id(project) when is_project(project) do
    # live: git ls-remote https://github.com/elixir-lang/elixir refs/heads/main

    config = Project.config!(project)

    response =
      System.cmd(
        "git",
        ~w(ls-remote #{Project.get_git_url(config, :origin)} refs/heads/#{config.main_branch})
      )

    case response do
      {response_string, 0} ->
        commit_id =
          response_string
          |> String.split()
          |> List.first()

        {:ok, commit_id}

      {_, _} = error ->
        {:error, error}
    end
  end

  #############################
  # Cache

  @doc """
  Return the path of the cached git `project`·
  """
  @spec path(Maintenance.project()) :: Path.t()
  def path(project) when is_project(project),
    do: Path.join(cache_path(), to_string(project))

  @doc """
  Cache git `project` repository.
  """
  @spec cache_repo(Maintenance.project()) :: {:ok, %{cached?: boolean}}
  def cache_repo(project) when is_project(project) do
    project
    |> path()
    |> File.mkdir_p!()

    last_commit_id =
      case get_last_commit_id(project) do
        {:ok, last_commit_id} -> last_commit_id
        {:error, _} -> nil
      end

    case get_last_cached_commit_id(project) do
      {:ok, ^last_commit_id} ->
        Util.info("Git repository already cached [#{project}]")
        {:ok, %{cached?: true}}

      {:ok, commit_id} when commit_id != nil ->
        Util.info("Updating Git repository [#{project}]")
        # Update repository
        :ok = update_repo(project)
        {:ok, %{cached?: false}}

      {:ok, nil} ->
        Util.info("Creating Git repository [#{project}]")
        :ok = create_repo(project)
        {:ok, %{cached?: false}}

      {:error, _} ->
        Util.info("Creating Git repository [#{project}]")
        :ok = create_repo(project)
        {:ok, %{cached?: false}}
    end
  end

  @doc """
  Writes the Git `project` repository.
  """
  @spec create_repo(Maintenance.project()) :: :ok | {:error, term()}
  def create_repo(project) when is_project(project) do
    config = Project.config!(project)

    git_url_origin = Project.get_git_url(config, :origin)
    git_url_upstream = Project.get_git_url(config, :upstream)

    with {_, 0} <-
           System.cmd(
             "git",
             ~w(clone #{git_url_origin} --branch #{config.main_branch} #{path(project)})
           )
           |> dbg(),
         :ok <- config(project) |> dbg(),
         git_path <- path(project) |> dbg(),
         {_, _} <- System.cmd("git", ~w(remote remove upstream), cd: git_path) |> dbg(),
         {_, 0} <-
           System.cmd(
             "git",
             ~w(remote add upstream #{git_url_upstream}),
             cd: git_path
           )
           |> dbg(),
         _ <-
           System.cmd("git", ~w(remote remove origin), cd: git_path),
         {_, 0} <-
           System.cmd("git", ~w(remote add origin #{git_url_origin}), cd: git_path)
           |> dbg() do
      :ok
    else
      error -> {:error, error}
    end
  end

  @doc """
  Updates the Git `project` repository.
  """
  @spec update_repo(Maintenance.project()) :: :ok | {:error, term()}
  def update_repo(project) when is_project(project) do
    git_path = path(project)
    :ok = File.mkdir_p!(git_path)

    update_repo(project, "origin")
  end

  defp update_repo(project, remote) do
    git_path = path(project)

    with :ok <- config(project),
         # {_, 0} <- System.cmd("git", ~w(pull #{remote} HEAD -f), cd: git_path),
         {_, 0} <- System.cmd("git", ~w(reset --hard HEAD), cd: git_path),
         {_, 0} <- System.cmd("git", ~w(clean -f -d), cd: git_path),
         {_, 0} <- System.cmd("git", ~w(fetch #{remote} HEAD -f), cd: git_path) do
      :ok
    else
      error ->
        {:error, error}
    end
  end

  @doc """
  Returns the last commit of the given cached Git `project` repository.
  """
  @spec get_last_cached_commit_id(Maintenance.project()) ::
          {:ok, String.t() | nil} | {:error, term()}
  def get_last_cached_commit_id(project) when is_project(project) do
    # live: git ls-remote https://github.com/elixir-lang/elixir refs/heads/main
    # cached: git rev-parse refs/heads/main

    config = Project.config!(project)

    if repo?(path(project)) do
      response =
        System.cmd("git", ~w(rev-parse refs/heads/#{config.main_branch}), cd: path(project))

      case response do
        {commit_id, 0} -> {:ok, String.trim(commit_id)}
        {_, _} = error -> {:error, error}
      end
    else
      {:ok, nil}
    end
  end

  @spec repo?(Path.t()) :: boolean()
  def repo?(path) do
    git_dir = Path.join(path, ".git")

    case File.dir?(git_dir) and System.cmd("git", ~w(rev-parse --is-inside-git-dir), cd: git_dir) do
      {string, 0} -> String.trim(string) == "true"
      _other -> false
    end
  end

  @spec commit(Maintenance.project(), String.t()) :: :ok | {:error, term}
  def commit(project, message) when is_project(project) when is_binary(message) do
    with git_path <- path(project),
         {_, 0} <- System.cmd("git", ~w(add -- .), cd: git_path),
         {_, 0} <-
           System.cmd("git", ["-c", "commit.gpgsign=false", "commit", "-m", message],
             cd: git_path
           ) do
      :ok
    else
      error ->
        {:error, error}
    end
  end

  @spec checkout(Maintenance.project(), branch) :: :ok | {:error, term()}
  def checkout(project, branch) when is_project(project) and is_binary(branch) do
    with git_path <- path(project),
         {_, 0} <- System.cmd("git", ["checkout", branch], cd: git_path) do
      :ok
    else
      error -> {:error, error}
    end
  end

  defp checkout_new_branch(project) do
    with {:ok, _value} <- cache_repo(project),
         :ok <- checkout(project, Project.config!(project, :main_branch)),
         {:ok, previous_branch} <- get_branch(project),
         new_branch <- get_new_branch(project),
         :ok <- checkout_new_branch(project, new_branch) do
      {:ok, new_branch, previous_branch}
    end
  end

  defp get_new_branch(project) do
    project
    |> to_string()
    |> Util.unique_branch_name()
  end

  @spec checkout_new_branch(Maintenance.project(), branch) :: :ok | {:error, term()}
  def checkout_new_branch(project, branch) when is_project(project) and is_binary(branch) do
    with git_path <- path(project),
         {_, 0} <- System.cmd("git", ["checkout", "-b", branch], cd: git_path) do
      :ok
    else
      error -> {:error, error}
    end
  end

  @spec get_branch(Maintenance.project()) :: {:ok, branch} | {:error, term()}
  def get_branch(project) when is_project(project) do
    with git_path <- path(project),
         {current_branch, 0} <- System.cmd("git", ~w(branch --show-current), cd: git_path) do
      {:ok, String.trim(current_branch)}
    else
      error -> {:error, error}
    end
  end

  @spec branch_exists?(Maintenance.project(), branch) :: boolean
  def branch_exists?(project, branch) when is_project(project) and is_binary(branch) do
    with git_path <- path(project),
         {_, 0} <-
           System.cmd("git", ["show-ref", "--quiet", "refs/heads/#{branch}"], cd: git_path) do
      true
    else
      _other -> false
    end
  end

  @spec push(Maintenance.project(), String.t()) :: :ok | {:error, term()}
  def push(project, remote_url) when is_project(project) and is_binary(remote_url) do
    auth_url = Maintenance.auth_url(remote_url)

    case System.cmd("git", ["push", auth_url, "HEAD", "-f"], cd: path(project)) do
      {_, 0} -> :ok
      error -> {:error, error}
    end
  end

  @spec add(Maintenance.project(), binary | [binary]) :: :ok | {:error, term()}
  def add(project, file_or_list_of_files)

  def add(project, file) when is_project(project) and is_binary(file),
    do: add(project, [file])

  def add(project, files) when is_project(project) and is_list(files) do
    git_path = path(project)

    case System.cmd("git", List.flatten(["add", files]), cd: git_path) do
      {_, 0} -> :ok
      error -> {:error, error}
    end
  end

  @spec delete_branch(Maintenance.project(), branch) :: :ok | {:error, term()}
  def delete_branch(project, branch) when is_project(project) and is_binary(branch) do
    with git_path <- path(project),
         {_, 0} <- System.cmd("git", ["branch", "-D", branch], cd: git_path) do
      :ok
    else
      error -> {:error, error}
    end
  end

  @spec submit_pr(Maintenance.project(), Maintenance.job(), map) :: :ok | {:error, term()}
  def submit_pr(project, job, data = %{title: title, db_key: db_key, db_value: db_value})
      when is_project(project) and is_atom(job) and is_map(data) do
    config = Project.config!(project)

    remote =
      if Maintenance.env!() == :prod do
        :upstream
      else
        :dev
      end

    owner = Project.get_owner(config, remote)

    push(project, Project.get_git_url(config, remote))

    client = Tentacat.Client.new(%{access_token: Maintenance.github_access_token!()})
    {:ok, branch} = get_branch(project)

    body = %{
      "title" => title,
      "body" =>
        Map.get(data, :body, """
        This is an automated commit generated by the Maintenance project.
        #{Maintenance.git_repo_url()}

        If you find any issue in this PR, please kindly report it to
        #{Maintenance.git_repo_url()}/issues
        """),
      "head" => Map.get(data, :head, owner <> ":" <> branch),
      "base" => Map.get(data, :base, config.main_branch)
    }

    case Tentacat.Pulls.create(client, owner, config.repo, body) do
      {pr_response_status, pr_github_response, _httpoison_response}
      when pr_response_status in 200..299 and is_map(pr_github_response) ->
        {:ok, created_at, _offset} =
          pr_github_response
          |> Map.fetch!("created_at")
          |> DateTime.from_iso8601()

        DB.put(project, db_key, %{
          value: db_value,
          url: Map.fetch!(pr_github_response, "html_url"),
          created_at: created_at
        })

        :ok

      {_pr_response_status, pr_github_response, _httpoison_response} ->
        {:error, pr_github_response}
    end

    # {response_status, github_response, _httpoison_response} =
    #   Tentacat.Pulls.create(client, owner, config.repo, body)

    # if response_status in 200..299 do
    #   {:ok, created_at, _offset} =
    #     Map.fetch!(github_response, "created_at") |> DateTime.from_iso8601()

    #   {response_status, github_response, _httpoison_response} =
    #     Tentacat.Issues.Labels.add(client, owner, config.repo, github_response["id"], ["automerge"])

    #   DB.put(project, db_key, %{
    #     value: db_value,
    #     url: Map.fetch!(github_response, "html_url"),
    #     created_at: created_at
    #   })

    #   :ok
    # else
    #   {:error, github_response}
    # end
  end

  @spec get_ref_date_time(Maintenance.project(), String.t()) ::
          {:ok, DateTime.t()} | {:error, term}
  def get_ref_date_time(project, ref) when is_project(project) when is_binary(ref) do
    with git_path <- path(project),
         {output, 0} <- System.cmd("git", ["show", "-s", "--format=%ct", ref, "--"], cd: git_path) do
      result =
        output
        |> String.trim()
        |> String.split("\n")
        |> List.last()
        |> String.to_integer()
        |> DateTime.from_unix!()

      {:ok, result}
    else
      error ->
        {:error, error}
    end
  end

  @spec get_commit_id(Maintenance.project(), String.t()) :: {:ok, String.t()} | {:error, term}
  def get_commit_id(project, tag) when is_project(project) and is_binary(tag) do
    with git_path <- path(project),
         {output, 0} <- System.cmd("git", ["rev-list", "-n", "1", tag, "--"], cd: git_path) do
      {:ok, String.trim(output)}
    else
      error ->
        {:error, error}
    end
  end

  @spec checkout_new_branch_and_produce_commit!(
          Maintenance.project(),
          Maintenance.job(),
          String.t(),
          map()
        ) :: {:ok, :updated | :no_update_needed}
  def checkout_new_branch_and_produce_commit!(project, job, commit_message, data)
      when is_project(project) and is_job(job) and is_binary(commit_message) and is_map(data) do
    {:ok, _new_branch, previous_branch} = checkout_new_branch(project)

    case produce_commit(project, job, commit_message, data) do
      {:ok, status} ->
        :ok = checkout(project, previous_branch)

        {:ok, status}

      {:error, exception} ->
        :ok = checkout(project, previous_branch)

        raise(exception)
    end
  end

  @spec produce_commit(Maintenance.project(), Maintenance.job(), String.t(), map()) ::
          {:ok, :updated | :no_update_needed} | {:error, Exception.t()}
  def produce_commit(project, job, commit_message, data)
      when is_project(project) and is_job(job) and is_binary(commit_message) and is_map(data) do
    case commit(project, commit_message) do
      :ok ->
        produce_submit_pr(project, job, data)

      {:error, error} ->
        with {msg, 1} <- error,
             "nothing to commit, working tree clean" <-
               msg
               |> String.trim()
               |> String.split("\n")
               |> List.last() do
          Util.info("Project is already up-to-date: " <> inspect(error))

          {:ok, :no_update_needed}
        else
          _other ->
            exception = %RuntimeError{message: "Could not commit: " <> inspect(error)}

            {:error, exception}
        end
    end
  end

  defp produce_submit_pr(project, job, data) do
    case submit_pr(project, job, data) do
      :ok ->
        {:ok, :updated}

      {:error, error} = result ->
        IO.warn("Could not create PR, failed with: " <> inspect(result))

        {:error, error}
    end
  end

  def setup_repo(project) when is_project(project) do
    new_branch = get_new_branch(project)

    setup_repo(project, new_branch)
  end

  def setup_repo(project, new_branch) when is_project(project) and is_binary(new_branch) do
    {:ok, _} = cache_repo(project)

    main_branch = Project.config!(project, :main_branch)

    :ok = checkout(project, main_branch)
    {:ok, previous_branch} = get_branch(project)

    if branch_exists?(project, new_branch) do
      :ok = delete_branch(project, new_branch)
    end

    :ok = checkout_new_branch(project, new_branch)

    {:ok, new_branch, previous_branch}
  end
end
