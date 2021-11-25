defmodule Maintenance.Git do
  @moduledoc """
  Module that deals with the Git commands.
  """

  import Maintenance, only: [is_project: 1, cache_path: 0, info: 1]
  alias Maintenance.{DB, Project}

  @type branch :: String.t()

  @doc false
  def config(project) when is_project(project) do
    repo_path = path(project)
    :ok = File.mkdir_p!(repo_path)

    with {_, 0} <- System.cmd("git", ~w(config pull.ff only), cd: repo_path),
         _ <- System.cmd("git", ~w(config user.name Eksperimental), cd: repo_path),
         _ <- System.cmd("git", ~w(config user.email eksperimental@autistici.org), cd: repo_path),
         _ <- System.cmd("git", ~w(config advice.addIgnoredFile false), cd: repo_path),
         _ <- System.cmd("git", ~w(config fetch.fsckobjects true), cd: repo_path),
         _ <- System.cmd("git", ~w(config transfer.fsckobjects true), cd: repo_path),
         _ <- System.cmd("git", ~w(config receive.fsckobjects true), cd: repo_path) do
      :ok
    else
      _ ->
        :error
    end
  end

  @doc """
  Returns the last commit of the given cached Git `project` repository.
  """
  @spec get_last_commit_id(Maintenance.project()) :: {:ok, String.t()} | :error
  def get_last_commit_id(project) when is_project(project) do
    # live: git ls-remote https://github.com/elixir-lang/elixir refs/heads/main

    config = Project.config(project)

    response =
      System.cmd("git", ~w(ls-remote #{config.git_url_upstream} refs/heads/#{config.main_branch}))

    case response do
      {response_string, 0} ->
        commit_id = String.split(response_string) |> List.first()
        {:ok, commit_id}

      {_, _} ->
        :error
    end
  end

  #############################
  # Cache

  @doc """
  Return the path of the cached git `project`·
  """
  @spec path(Maintenance.project()) :: Path.t()
  def path(project) when is_project(project),
    do: cache_path() |> Path.join(to_string(project))

  @doc """
  Cache git `project` repository.
  """
  @spec cache_repo(Maintenance.project()) :: {:ok, %{cached?: boolean}}
  def cache_repo(project) when is_project(project) do
    File.mkdir_p!(path(project))
    {:ok, last_commit_id} = get_last_commit_id(project)

    case get_last_cached_commit_id(project) do
      {:ok, ^last_commit_id} ->
        info("Git repository already cached [#{project}]")
        {:ok, %{cached?: true}}

      {:ok, commit_id} when commit_id != nil ->
        info("Updating Git repository [#{project}]")
        # Update repository
        :ok = update_repo(project)
        {:ok, %{cached?: false}}

      result when result in [{:ok, nil}, :error] ->
        info("Creating Git repository [#{project}]")
        :ok = create_repo(project)
        {:ok, %{cached?: false}}
    end
  end

  @doc """
  Writes the Git `project` repository.
  """
  @spec create_repo(Maintenance.project()) :: :ok | :error
  def create_repo(project) when is_project(project) do
    config = Project.config(project)

    with {_, 0} <-
           System.cmd(
             "git",
             ~w(clone #{config.git_url_upstream} --depth 1 --branch #{config.main_branch} #{path(project)})
           ),
         :ok <- config(project),
         git_path <- path(project),
         {_, 0} <- System.cmd("git", ~w(remote remove origin), cd: git_path),
         {_, 0} <-
           System.cmd(
             "git",
             ~w(remote add origin #{config.git_url_origin}),
             cd: git_path
           ),
         # _ <-
         #   System.cmd("git", ~w(remote remove upstream), cd: git_path),
         {_, 0} <-
           System.cmd("git", ~w(remote add upstream #{config.git_url_upstream}), cd: git_path) do
      :ok
    else
      _ -> :error
    end
  end

  @doc """
  Updates the Git `project` repository.
  """
  @spec update_repo(Maintenance.project()) :: :ok | :error
  def update_repo(project) when is_project(project) do
    git_path = path(project)
    :ok = File.mkdir_p!(git_path)

    if shallow_repo?(git_path) do
      update_repo_shallow(project, "origin")
    else
      update_repo_regular(project, "upstream")
    end
  end

  def update_repo_regular(project, remote) do
    git_path = path(project)

    with :ok <- config(project),
         {_, 0} <- System.cmd("git", ~w(pull #{remote} HEAD -f), cd: git_path) do
      :ok
    else
      _ ->
        :error
    end
  end

  # https://stackoverflow.com/questions/41075972/how-to-update-a-git-shallow-clone
  defp update_repo_shallow(project, remote) do
    config = Project.config(project)
    git_path = path(project)

    with :ok <- config(project),
         {_, 0} <- System.cmd("git", ~w(fetch --depth 1), cd: git_path),
         {_, 0} <-
           System.cmd("git", ~w(reset --hard #{remote}/#{config.main_branch}), cd: git_path),
         {_, 0} <- System.cmd("git", ~w(clean -dfx), cd: git_path) do
      :ok
    else
      _ ->
        :error
    end
  end

  @doc """
  Returns the last commit of the given cached Git `project` repository.
  """
  @spec get_last_cached_commit_id(Maintenance.project()) :: {:ok, String.t() | nil} | :error
  def get_last_cached_commit_id(project) when is_project(project) do
    # live: git ls-remote https://github.com/elixir-lang/elixir refs/heads/main
    # cached: git rev-parse refs/heads/main

    config = Project.config(project)

    if repo?(path(project)) do
      response =
        System.cmd("git", ~w(rev-parse refs/heads/#{config.main_branch}), cd: path(project))

      case response do
        {commit_id, 0} -> {:ok, String.trim(commit_id)}
        {_, _} -> :error
      end
    else
      {:ok, nil}
    end
  end

  def repo?(path) do
    git_dir = Path.join(path, ".git")

    case File.dir?(git_dir) and System.cmd("git", ~w(rev-parse --is-inside-git-dir), cd: git_dir) do
      {string, 0} -> String.trim(string) == "true"
      _ -> false
    end
  end

  def shallow_repo?(path) do
    with true <- File.dir?(path),
         {string, 0} <- System.cmd("git", ~w(rev-parse --is-shallow-repository), cd: path) do
      String.trim(string) == "true"
    else
      _ -> raise("Given path is not a path: #{path}")
    end
  end

  @spec commit(Maintenance.project(), String.t()) :: :ok | :error
  def commit(project, message) when is_project(project) when is_binary(message) do
    with git_path <- path(project),
         {_, 0} <- System.cmd("git", ~w(add -- .), cd: git_path),
         {_, 0} <-
           System.cmd("git", ["-c", "commit.gpgsign=false", "commit", "-m", message], cd: git_path) do
      :ok
    else
      _ -> :error
    end
  end

  @spec checkout(Maintenance.project(), branch) :: :ok | :error
  def checkout(project, branch) when is_project(project) and is_binary(branch) do
    with git_path <- path(project),
         {_, 0} <- System.cmd("git", ["checkout", branch], cd: git_path) do
      :ok
    else
      _ -> :error
    end
  end

  @spec checkout_new_branch(Maintenance.project(), branch) :: :ok | :error
  def checkout_new_branch(project, branch) when is_project(project) and is_binary(branch) do
    with git_path <- path(project),
         {_, 0} <- System.cmd("git", ["checkout", "-b", branch], cd: git_path) do
      :ok
    else
      _ -> :error
    end
  end

  @spec get_branch(Maintenance.project()) :: {:ok, branch} | :error
  def get_branch(project) when is_project(project) do
    with git_path <- path(project),
         {current_branch, 0} <- System.cmd("git", ~w(branch --show-current), cd: git_path) do
      {:ok, String.trim(current_branch)}
    else
      _ -> :error
    end
  end

  @spec branch_exists?(Maintenance.project(), branch) :: boolean
  def branch_exists?(project, branch) when is_project(project) and is_binary(branch) do
    with git_path <- path(project),
         {_, 0} <-
           System.cmd("git", ["show-ref", "--quiet", "refs/heads/#{branch}"], cd: git_path) do
      true
    else
      _ -> false
    end
  end

  @spec push_repo(Maintenance.project(), map) :: :ok | :error
  def push_repo(project, config) when is_project(project) and is_map(config) do
    git_path = path(project)

    if shallow_repo?(git_path) do
      # push main branch
      :ok =
        push_shallow(
          project,
          "origin",
          config.main_branch,
          config.git_url_origin,
          config.main_branch
        )

      # push upstream
      :ok =
        push_shallow(
          project,
          "upstream",
          config.main_branch,
          config.git_url_upstream,
          config.main_branch
        )
    else
      :ok = push(project, config.git_url_upstream)
    end
  end

  @spec push(Maintenance.project(), String.t()) :: :ok | :error
  def push(project, remote_url) when is_project(project) and is_binary(remote_url) do
    auth_url = Maintenance.auth_url(remote_url)

    case System.cmd("git", ["push", auth_url, "HEAD", "-f"], cd: path(project)) do
      {_, 0} -> :ok
      _ -> :error
    end
  end

  # Extracted from: https://github.com/wtsos/learngit/blob/2baa66d462d454ced5d6aa56e93618f0244d0d45/t/t5538-push-shallow.sh
  @spec push_shallow(Maintenance.project(), String.t(), String.t(), String.t(), String.t()) ::
          :ok | :error
  def push_shallow(project, remote, remote_branch, remote_url, local_branch)
      when is_project(project) and is_binary(remote) and is_binary(remote_branch) and
             is_binary(remote_url) and is_binary(local_branch) do
    with git_path <- path(project),
         {_, 0} <-
           System.cmd(
             "git",
             ~w(push ./.git +#{local_branch}:refs/remotes/#{remote}/#{remote_branch}),
             cd: git_path
           ) do
      :ok
    else
      _ ->
        :error
    end
  end

  @spec add(Maintenance.project(), binary | [binary]) :: :ok | :error
  def add(project, file_or_list_of_files)

  def add(project, file) when is_project(project) and is_binary(file),
    do: add(project, [file])

  def add(project, files) when is_project(project) and is_list(files) do
    git_path = path(project)

    case System.cmd("git", List.flatten(["add", files]), cd: git_path) do
      {_, 0} -> :ok
      _ -> :error
    end
  end

  @spec delete_branch(Maintenance.project(), branch) :: :ok | {:error, map}
  def delete_branch(project, branch) when is_project(project) and is_binary(branch) do
    with git_path <- path(project),
         {_, 0} <- System.cmd("git", ["branch", "-D", branch], cd: git_path) do
      :ok
    else
      _ -> :error
    end
  end

  @spec submit_pr(Maintenance.project(), Maintenance.job(), map) :: :ok | {:error, term()}
  def submit_pr(project, job, data = %{title: title, db_key: db_key, db_value: db_value})
      when is_project(project) and
             is_atom(job) and is_map(data) do
    config = Project.config(project)
    :ok = push_repo(project, config)

    client = Tentacat.Client.new(%{access_token: Maintenance.github_access_token()})
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
      "head" => Map.get(data, :head, config.owner_origin <> ":" <> branch),
      "base" => Map.get(data, :base, config.main_branch)
    }

    # TODO: Uncomment this once uploaded
    # if Maintenance.env!() == :prod do
    #   config.owner_upstream
    # else
    owner = config.owner_origin
    # end

    {response_status, github_response, _httpoison_response} =
      Tentacat.Pulls.create(client, owner, config.repo, body)

    if response_status in 200..299 do
      {:ok, created_at, _offset} =
        Map.fetch!(github_response, "created_at") |> DateTime.from_iso8601()

      DB.put(project, db_key, %{
        value: db_value,
        url: Map.fetch!(github_response, "html_url"),
        created_at: created_at
      })

      :ok
    else
      {:error, github_response}
    end
  end

  ########################
  # Helpers

  # defp calculate_update(project) when is_project(project) do
  #   {:ok, last_commit_id} = get_last_commit_id(project)
  #   {:ok, last_cached_commit_id} = get_last_cached_commit_id(project)

  #   %{
  #     needs_update?: last_commit_id != last_cached_commit_id,
  #     last_commit_id: last_commit_id,
  #     last_cached_commit_id: last_cached_commit_id
  #   }
  # end
end
