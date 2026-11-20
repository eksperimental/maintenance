defmodule Maintenance.GitTest do
  use ExUnit.Case, async: false

  alias Maintenance.{Git, Project}

  @moduletag :tmp_dir

  @project :elixir
  @remote_url Project.get_git_url(@project, :dev)

  setup %{tmp_dir: tmp_dir} do
    local = Git.path(@project)
    File.rm_rf!(local)
    File.mkdir_p!(local)
    on_exit(fn -> File.rm_rf!(local) end)

    git!(local, ~w(init --quiet --initial-branch main))
    stale = commit!(local, "stale")
    main = commit!(local, "main")
    git!(local, ~w(checkout --quiet -b feature))
    feature = commit!(local, "feature")

    fork = Path.join(tmp_dir, "fork.git")
    git!(tmp_dir, ["init", "--quiet", "--bare", fork])

    # Send the fork's URL to the bare repository, and every other URL nowhere.
    auth_url = Maintenance.auth_url(@remote_url)
    git!(local, ["config", "url.file://#{fork}.insteadOf", auth_url])
    git!(local, ["config", "url.file:///nonexistent/.insteadOf", "https://"])

    %{local: local, fork: fork, stale: stale, main: main, feature: feature}
  end

  describe "push/2" do
    test "fast-forwards the fork's main branch along with the current branch", context do
      git!(context.local, ["push", "--quiet", context.fork, "#{context.stale}:refs/heads/main"])

      assert Git.push(@project, @remote_url) == :ok

      assert refs(context.fork) == %{"main" => context.main, "feature" => context.feature}
    end

    test "pushes nothing when the fork's main branch has diverged", context do
      diverged =
        git!(context.local, [
          "commit-tree",
          "#{context.stale}^{tree}",
          "-p",
          context.stale,
          "-m",
          "diverged"
        ])

      git!(context.local, ["push", "--quiet", context.fork, "#{diverged}:refs/heads/main"])

      assert {:error, _reason} = Git.push(@project, @remote_url)

      assert refs(context.fork) == %{"main" => diverged}
    end
  end

  describe "submit_pr/3 with publishing disabled" do
    setup do
      previous = Application.get_env(:maintenance, :publish?)
      Application.put_env(:maintenance, :publish?, false)

      on_exit(fn ->
        Application.put_env(:maintenance, :publish?, previous)
      end)
    end

    test "pushes nothing and opens no pull request", context do
      Req.Test.stub(Maintenance.Github, fn _conn ->
        flunk("a pull request was requested")
      end)

      data = %{title: "Update Unicode", db_key: :unicode, db_value: "18.0.0"}

      assert Git.submit_pr(@project, :unicode, data) == :ok

      assert refs(context.fork) == %{}
    end
  end

  defp commit!(dir, message) do
    File.write!(Path.join(dir, "file.txt"), message)
    git!(dir, ~w(add file.txt))

    git!(dir, [
      "-c",
      "user.name=Test",
      "-c",
      "user.email=test@example.com",
      "-c",
      "commit.gpgsign=false",
      "commit",
      "--quiet",
      "-m",
      message
    ])

    git!(dir, ~w(rev-parse HEAD))
  end

  defp refs(repo) do
    repo
    |> git!(["for-each-ref", "--format=%(refname:short) %(objectname)"])
    |> String.split("\n", trim: true)
    |> Map.new(fn line -> line |> String.split(" ") |> List.to_tuple() end)
  end

  defp git!(dir, args) do
    {output, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
    String.trim(output)
  end
end
