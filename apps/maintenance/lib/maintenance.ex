defmodule Maintenance do
  @moduledoc """
  Checks whether the maintenance jobs are due, builds their commits locally, and publishes
  them as pull requests, whichever job it is.

  The three steps are `status/3`, `run/3` and `publish/3`. The `maintenance.status`,
  `maintenance.run` and `maintenance.publish` Mix tasks call them.
  """

  require Application

  alias Maintenance.Git
  alias Maintenance.Github
  alias Maintenance.Project

  @app_name :maintenance
  @git_repo_url Application.compile_env(@app_name, :git_repo_url)
  @data_dir Application.compile_env!(@app_name, :data_dir)

  @type project :: Maintenance.Project.t()
  @type job :: MaintenanceJob.t()
  @type fork :: String.t()

  defguard is_job(term) when is_atom(term)

  defguard is_project(term) when is_atom(term)

  @doc false
  @spec app_name() :: atom()
  def app_name(), do: @app_name

  @doc false
  @spec git_repo_url() :: String.t()
  def git_repo_url(), do: @git_repo_url

  @doc false
  @spec data_dir() :: String.t()
  def data_dir(), do: @data_dir

  @doc false
  @spec cache_path() :: String.t()
  def cache_path() do
    Path.join(data_dir(), "cache")
  end

  @doc """
  Returns the GitHub account in `GITHUB_ACCOUNT`, whose fork is used when no `--fork` is given.
  """
  @spec github_account() :: String.t() | nil
  def github_account() do
    case System.get_env("GITHUB_ACCOUNT") do
      account when account in [nil, ""] -> nil
      account -> account
    end
  end

  # GitHub reads the token and ignores the user name, so any fixed one works.
  @doc false
  @spec auth_url(String.t()) :: String.t()
  def auth_url("https://" <> rest) do
    "https://x-access-token:" <> github_access_token!() <> "@" <> rest
  end

  @doc false
  @spec github_access_token() :: String.t() | nil
  def github_access_token() do
    case System.get_env("GITHUB_ACCESS_TOKEN") do
      token when token in [nil, ""] -> nil
      token -> token
    end
  end

  @doc false
  @spec github_access_token!() :: String.t()
  def github_access_token!() do
    github_access_token() ||
      raise "GITHUB_ACCESS_TOKEN is not set. Put it in .env and run `source .env`."
  end

  @doc """
  List projects
  """
  @spec projects() :: nonempty_list(project)
  def projects(), do: Maintenance.Project.list()

  @doc """
  List jobs for the given `project`.
  """
  @spec jobs(project) :: [job]
  def jobs(project) when is_project(project) do
    {:ok, modules} = :application.get_key(:maintenance, :modules)

    modules
    |> Enum.filter(&job_of_project?(&1, project))
    |> Enum.map(& &1.job())
    |> Enum.sort()
  end

  defp job_of_project?(module, project) do
    MaintenanceJob in list_behaviours(module) and module.implements_project?(project)
  end

  defp list_behaviours(module) do
    attributes = module.module_info(:attributes)

    attributes
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  @doc """
  Returns the module that implements `job`.
  """
  @spec job_module(job) :: module()
  def job_module(job) when is_job(job) do
    Module.safe_concat([MaintenanceJob, Macro.camelize(to_string(job))])
  end

  @doc """
  Returns whether `job` is due for `project`, and, if so, whether `fork` has a pull request
  for it, open or closed. A closed one leaves the job due. Only the network is used.
  """
  @spec status(project, job, fork) ::
          {:up_to_date | :due, MaintenanceJob.info()}
          | {:pr_exists | :pr_closed, MaintenanceJob.info(), url :: String.t()}
          | {:error, term()}
  def status(project, job, fork) when is_project(project) and is_job(job) and is_binary(fork) do
    case job_module(job).status(project) do
      {:due, info} -> due_status(project, info, fork)
      {:up_to_date, _info} = up_to_date -> up_to_date
      {:error, _reason} = error -> error
    end
  end

  defp due_status(project, info, fork) do
    case Github.find_pull_request(fork, Project.config!(project, :repo), info.branch) do
      :none -> {:due, info}
      {:open, url} -> {:pr_exists, info, url}
      {:closed, url} -> {:pr_closed, info, url}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Builds the commit for `job` in the cached checkout of `project`, if it is due and `fork`
  has no open pull request for it. Nothing is pushed.
  """
  @spec run(project, job, fork) ::
          :up_to_date
          | {:pr_exists, url :: String.t()}
          | {:committed, %{branch: String.t(), path: Path.t()}}
          | {:error, :missing_git_identity | term()}
  def run(project, job, fork) when is_project(project) and is_job(job) and is_binary(fork) do
    case status(project, job, fork) do
      {:up_to_date, _info} ->
        :up_to_date

      {:pr_exists, _info, url} ->
        {:pr_exists, url}

      {:error, _reason} = error ->
        error

      {:due, _info} ->
        build(project, job)

      {:pr_closed, _info, _url} ->
        build(project, job)
    end
  end

  defp build(project, job) do
    with :ok <- ensure_git_identity(),
         {:ok, :committed, branch} <- job_module(job).prepare(project) do
      {:committed, %{branch: branch, path: Git.path(project)}}
    end
  end

  @doc """
  Pushes the commit that `run/3` left on the branch of `job`, unchanged, and opens a pull
  request for it inside `fork`. The title is the subject of the commit. Nothing is pushed
  when the job is up to date.
  """
  @spec publish(project, job, fork) ::
          :up_to_date
          | {:opened, url :: String.t()}
          | {:pr_exists, url :: String.t()}
          | {:error, :missing_token | :branch_missing | term()}
  def publish(project, job, fork) when is_project(project) and is_job(job) and is_binary(fork) do
    %{repo: repo, main_branch: main_branch} = Project.config!(project)

    with :ok <- ensure_token(),
         {:due, %{branch: branch}} <- job_module(job).status(project),
         :ok <- ensure_committed(project, branch),
         :ok <- ensure_no_open_pull_request(fork, repo, branch),
         :ok <- push(project, branch, fork),
         {:ok, subject} <- Git.commit_subject(project, branch),
         {:ok, pull_request} <-
           Github.create_pull_request(fork, repo, %{
             "title" => subject,
             "body" => pull_request_body(),
             "head" => fork <> ":" <> branch,
             "base" => main_branch
           }) do
      {:opened, Map.fetch!(pull_request, "html_url")}
    else
      {:up_to_date, _info} -> :up_to_date
      {:pr_exists, _url} = pr_exists -> pr_exists
      {:error, _reason} = error -> error
    end
  end

  defp ensure_no_open_pull_request(fork, repo, branch) do
    case Github.find_pull_request(fork, repo, branch) do
      {:open, url} -> {:pr_exists, url}
      {:error, _reason} = error -> error
      _none_or_closed -> :ok
    end
  end

  defp ensure_token() do
    if github_access_token(), do: :ok, else: {:error, :missing_token}
  end

  defp ensure_git_identity() do
    if Git.identity_set?(), do: :ok, else: {:error, :missing_git_identity}
  end

  defp ensure_committed(project, branch) do
    if Git.branch_ahead?(project, branch), do: :ok, else: {:error, :branch_missing}
  end

  # Git.push/2 pushes HEAD, so the branch has to be checked out while it runs.
  defp push(project, branch, fork) do
    with :ok <- Git.checkout(project, branch) do
      result = Git.push(project, Project.fork_url(project, fork))

      with :ok <- Git.checkout(project, Project.config!(project, :main_branch)), do: result
    end
  end

  defp pull_request_body() do
    """
    This is an automated commit generated by the Maintenance project.
    #{git_repo_url()}

    If you find any issue in this PR, please kindly report it to
    #{git_repo_url()}/issues
    """
  end
end
