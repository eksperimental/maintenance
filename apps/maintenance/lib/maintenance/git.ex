defmodule Maintenance.Git do
  @moduledoc """
  Module that deals with the Git commands.
  """

  import Maintenance, only: [cache_path: 0, is_project: 1]

  alias Maintenance.Project
  alias Maintenance.Util

  @type branch :: String.t()

  @doc false
  @spec config(Maintenance.project()) ::
          :ok | {:error, {Collectable.t(), exit_status :: non_neg_integer()}}
  def config(project) when is_project(project) do
    repo_path = path(project)
    :ok = File.mkdir_p!(repo_path)

    with {_response_string, 0} <- System.cmd("git", ~w(config pull.ff only), cd: repo_path),
         :ok <- unset_local(repo_path, "user.name"),
         :ok <- unset_local(repo_path, "user.email"),
         _response_string <-
           System.cmd("git", ~w(config advice.addIgnoredFile false), cd: repo_path),
         _response_string <- System.cmd("git", ~w(config fetch.fsckobjects true), cd: repo_path),
         _response_string <-
           System.cmd("git", ~w(config transfer.fsckobjects true), cd: repo_path),
         _response_string <- System.cmd("git", ~w(config receive.fsckobjects true), cd: repo_path) do
      :ok
    else
      error -> {:error, error}
    end
  end

  # Older versions wrote an identity into the checkout. Commits use the runner's own one.
  defp unset_local(repo_path, key) do
    case System.cmd("git", ["config", "--local", "--unset-all", key], cd: repo_path) do
      {_response_string, status} when status in [0, 5] -> :ok
      error -> {:error, error}
    end
  end

  @doc """
  Returns whether Git knows who the runner is, from its config or the `GIT_AUTHOR_*` and
  `GIT_COMMITTER_*` variables. Git is not allowed to make one up from the user and host names.
  """
  @spec identity_set?() :: boolean()
  def identity_set?() do
    Enum.all?(~w(GIT_AUTHOR_IDENT GIT_COMMITTER_IDENT), fn variable ->
      {_output, status} =
        System.cmd("git", ["-c", "user.useConfigOnly=true", "var", variable],
          cd: System.tmp_dir!(),
          stderr_to_stdout: true
        )

      status == 0
    end)
  end

  @doc """
  Returns the author of the last commit of `branch`, as `Name <email>`.
  """
  @spec commit_author(Maintenance.project(), branch) :: {:ok, String.t()} | {:error, term()}
  def commit_author(project, branch) when is_project(project) and is_binary(branch) do
    case System.cmd("git", ["log", "-1", "--format=%an <%ae>", branch, "--"], cd: path(project)) do
      {author, 0} -> {:ok, String.trim(author)}
      error -> {:error, error}
    end
  end

  @doc """
  Returns the last commit of the given cached Git `project` repository.
  """
  @spec get_last_commit_id(Maintenance.project()) :: {:ok, String.t()} | {:error, term}
  def get_last_commit_id(project) when is_project(project) do
    # live: git ls-remote https://github.com/elixir-lang/elixir refs/heads/main

    response =
      System.cmd(
        "git",
        ~w(ls-remote #{Project.git_url(project)} refs/heads/#{Project.config!(project, :main_branch)}),
        stderr_to_stdout: true
      )

    case response do
      {response_string, 0} ->
        commit_id =
          response_string
          |> String.split()
          |> List.first()

        {:ok, commit_id}

      {_response_string, _exit_status} = error ->
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
  Cache git `project` repository. Changes left in the checkout by an earlier run are
  discarded, so they cannot end up in the next commit.
  """
  @spec cache_repo(Maintenance.project()) :: {:ok, %{cached?: boolean}} | {:error, term()}
  def cache_repo(project) when is_project(project) do
    project
    |> path()
    |> File.mkdir_p!()

    last_commit_id =
      case get_last_commit_id(project) do
        {:ok, last_commit_id} -> last_commit_id
        {:error, _error} -> nil
      end

    case get_last_cached_commit_id(project) do
      {:ok, ^last_commit_id} when last_commit_id != nil ->
        Util.info("Git repository already cached [#{project}]")
        with :ok <- discard_changes(project), do: {:ok, %{cached?: true}}

      {:ok, commit_id} when commit_id != nil ->
        Util.info("Updating Git repository [#{project}]")
        with :ok <- update_repo(project), do: {:ok, %{cached?: false}}

      _no_checkout ->
        Util.info("Creating Git repository [#{project}]")
        with :ok <- create_repo(project), do: {:ok, %{cached?: false}}
    end
  end

  @doc """
  Writes the Git `project` repository.
  """
  @spec create_repo(Maintenance.project()) :: :ok | {:error, term()}
  def create_repo(project) when is_project(project) do
    main_branch = Project.config!(project, :main_branch)
    args = ~w(clone --quiet #{Project.git_url(project)} --branch #{main_branch} #{path(project)})

    with :ok <- git(args, path(project)) do
      config(project)
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
    main_branch = Project.config!(project, :main_branch)

    with :ok <- config(project),
         :ok <- git(~w(reset --hard HEAD), git_path),
         :ok <- git(~w(clean -f -d), git_path),
         :ok <- git(~w(fetch --quiet #{remote} #{main_branch} -f), git_path),
         :ok <- git(~w(checkout --quiet -f #{main_branch}), git_path) do
      git(~w(reset --quiet --hard FETCH_HEAD), git_path)
    end
  end

  # Runs Git in `dir`. A failure names the command and the first line of what Git said.
  defp git(args, dir) do
    case System.cmd("git", args, cd: dir, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, _status} ->
        [first_line | _rest] =
          output
          |> String.trim()
          |> String.split("\n")

        {:error, {:git_failed, Enum.join(["git" | args], " "), first_line}}
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
        {_response_string, _exit_status} = error -> {:error, error}
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
         {_response_string, 0} <- System.cmd("git", ~w(add -- .), cd: git_path),
         {_response_string, 0} <-
           System.cmd(
             "git",
             [
               "-c",
               "commit.gpgsign=false",
               "-c",
               "user.useConfigOnly=true",
               "commit",
               "-m",
               message
             ],
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
         {_response_string, 0} <- System.cmd("git", ["checkout", branch], cd: git_path) do
      :ok
    else
      error -> {:error, error}
    end
  end

  @spec checkout_new_branch(Maintenance.project(), branch) :: :ok | {:error, term()}
  def checkout_new_branch(project, branch) when is_project(project) and is_binary(branch) do
    with git_path <- path(project),
         {_response_string, 0} <- System.cmd("git", ["checkout", "-b", branch], cd: git_path) do
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
         {_response_string, 0} <-
           System.cmd("git", ["show-ref", "--quiet", "refs/heads/#{branch}"], cd: git_path) do
      true
    else
      _other -> false
    end
  end

  @doc """
  Returns whether the cached checkout has `branch` with commits the main branch does not have.
  """
  @spec branch_ahead?(Maintenance.project(), branch) :: boolean
  def branch_ahead?(project, branch) when is_project(project) and is_binary(branch) do
    main_branch = Project.config!(project, :main_branch)
    checkout = path(project)

    with true <- File.dir?(checkout),
         {count, 0} <-
           System.cmd("git", ["rev-list", "--count", "#{main_branch}..#{branch}", "--"],
             cd: checkout,
             stderr_to_stdout: true
           ) do
      String.trim(count) != "0"
    else
      _other -> false
    end
  end

  @doc """
  Returns the summary of what `branch` changes compared to the main branch.
  """
  @spec diff_stat(Maintenance.project(), branch) :: {:ok, String.t()} | {:error, term()}
  def diff_stat(project, branch) when is_project(project) and is_binary(branch) do
    main_branch = Project.config!(project, :main_branch)

    case System.cmd("git", ["diff", "--stat", "#{main_branch}...#{branch}", "--"],
           cd: path(project)
         ) do
      {stat, 0} -> {:ok, String.trim_trailing(stat)}
      error -> {:error, error}
    end
  end

  @doc """
  Returns the subject, the first line of the message, of the last commit of `branch`.
  """
  @spec commit_subject(Maintenance.project(), branch) :: {:ok, String.t()} | {:error, term()}
  def commit_subject(project, branch) when is_project(project) and is_binary(branch) do
    case System.cmd("git", ["log", "-1", "--format=%s", branch, "--"], cd: path(project)) do
      {subject, 0} -> {:ok, String.trim(subject)}
      error -> {:error, error}
    end
  end

  @doc """
  Pushes the current branch to `remote_url`, together with the main branch.

  The main branch is pushed so the pull request base on the fork is up to date
  and the pull request only shows the new commits. It is only fast-forwarded,
  and the push is atomic, so nothing is pushed if the fork's main branch has
  commits of its own. That error is `:fork_main_diverged`.
  """
  @spec push(Maintenance.project(), String.t()) :: :ok | {:error, :fork_main_diverged | term()}
  def push(project, remote_url) when is_project(project) and is_binary(remote_url) do
    auth_url = Maintenance.auth_url(remote_url)
    main_branch = Project.config!(project, :main_branch)
    refspecs = ["+HEAD", "refs/heads/#{main_branch}:refs/heads/#{main_branch}"]

    case System.cmd("git", ["push", "--porcelain", "--atomic", auth_url | refspecs],
           cd: path(project),
           stderr_to_stdout: true
         ) do
      {_response_string, 0} ->
        :ok

      {response_string, _status} = error ->
        main_rejected = "!\trefs/heads/#{main_branch}:refs/heads/#{main_branch}\t[rejected]"

        if String.contains?(response_string, main_rejected),
          do: {:error, :fork_main_diverged},
          else: {:error, error}
    end
  end

  @doc """
  Discards every uncommitted change in the working tree, including untracked files.
  """
  @spec discard_changes(Maintenance.project()) :: :ok | {:error, term()}
  def discard_changes(project) when is_project(project) do
    with git_path <- path(project),
         {_response_string, 0} <- System.cmd("git", ~w(reset --hard HEAD), cd: git_path),
         {_response_string, 0} <- System.cmd("git", ~w(clean -f -d), cd: git_path) do
      :ok
    else
      error -> {:error, error}
    end
  end

  @spec delete_branch(Maintenance.project(), branch) :: :ok | {:error, term()}
  def delete_branch(project, branch) when is_project(project) and is_binary(branch) do
    with git_path <- path(project),
         {_response_string, 0} <- System.cmd("git", ["branch", "-D", branch], cd: git_path) do
      :ok
    else
      error -> {:error, error}
    end
  end

  @spec setup_repo(Maintenance.project(), branch()) ::
          {:ok, branch(), branch()} | {:error, term()}
  def setup_repo(project, new_branch) when is_project(project) and is_binary(new_branch) do
    main_branch = Project.config!(project, :main_branch)

    with {:ok, _map} <- cache_repo(project),
         :ok <- checkout(project, main_branch),
         {:ok, previous_branch} <- get_branch(project),
         :ok <- delete_branch_if_exists(project, new_branch),
         :ok <- checkout_new_branch(project, new_branch) do
      {:ok, new_branch, previous_branch}
    end
  end

  defp delete_branch_if_exists(project, branch) do
    if branch_exists?(project, branch), do: delete_branch(project, branch), else: :ok
  end
end
