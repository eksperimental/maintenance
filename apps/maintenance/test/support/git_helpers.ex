defmodule Maintenance.GitHelpers do
  @moduledoc false

  @identity ~w(-c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false)

  @spec commit!(Path.t(), String.t()) :: String.t()
  def commit!(dir, message) do
    file = Path.join(dir, "file.txt")
    File.write!(file, message)
    git!(dir, ~w(add file.txt))
    git!(dir, @identity ++ ["commit", "--quiet", "-m", message])
    git!(dir, ~w(rev-parse HEAD))
  end

  @doc """
  Builds the checkout of `project` with `branch` one commit ahead of main, and a bare
  repository that stands in for the fork of `owner`.
  """
  @spec fork_checkout!(Path.t(), Maintenance.project(), String.t(), String.t()) :: map()
  def fork_checkout!(tmp_dir, project, owner, branch) do
    local = Maintenance.Git.path(project)
    File.rm_rf!(local)
    File.mkdir_p!(local)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(local) end)

    git!(local, ~w(init --quiet --initial-branch main))
    main = commit!(local, "main")
    git!(local, ~w(checkout --quiet -b #{branch}))
    tip = commit!(local, "Update Fake to version 1\n\nWhy it changed.")
    git!(local, ~w(checkout --quiet main))

    fork = Path.join(tmp_dir, "fork.git")
    git!(tmp_dir, ["init", "--quiet", "--bare", fork])

    # Send the fork's URL to the bare repository, and every other URL nowhere.
    fork_url = Maintenance.Project.fork_url(project, owner)
    auth_url = Maintenance.auth_url(fork_url)
    git!(local, ["config", "url.file://#{fork}.insteadOf", auth_url])
    git!(local, ["config", "url.file:///nonexistent/.insteadOf", "https://"])

    %{local: local, fork: fork, main: main, tip: tip}
  end

  @spec refs(Path.t()) :: %{String.t() => String.t()}
  def refs(repo) do
    repo
    |> git!(["for-each-ref", "--format=%(refname:short) %(objectname)"])
    |> String.split("\n", trim: true)
    |> Map.new(fn line ->
      [name, sha] = String.split(line, " ")
      {name, sha}
    end)
  end

  @spec git!(Path.t(), [String.t()]) :: String.t()
  def git!(dir, args) do
    {output, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
    String.trim(output)
  end
end
