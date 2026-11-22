defmodule Maintenance.GitTest do
  use ExUnit.Case, async: false

  import Maintenance.EnvHelpers
  import Maintenance.GitHelpers

  alias Maintenance.Git
  alias Maintenance.Project

  @moduletag :tmp_dir

  @project :elixir
  @remote_url Project.fork_url(@project, "some-account")

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

  describe "config/1" do
    test "removes the identity that older versions wrote into the checkout", context do
      git!(context.local, ~w(config --local user.name Maintenance))
      git!(context.local, ~w(config --local --add user.name Maintenance))
      git!(context.local, ~w(config --local user.email old@example.com))

      assert Git.config(@project) == :ok

      for key <- ~w(user.name user.email) do
        assert {_output, 1} =
                 System.cmd("git", ["config", "--local", "--get-all", key], cd: context.local)
      end
    end

    test "succeeds when the checkout has no identity of its own" do
      assert Git.config(@project) == :ok
    end
  end

  describe "cache_repo/1" do
    test "discards leftover changes when the checkout already has the upstream main branch",
         context do
      upstream!(context)

      tracked = Path.join(context.local, "file.txt")
      untracked = Path.join(context.local, "stray.txt")
      File.write!(tracked, "changed")
      File.write!(untracked, "left behind")

      assert Git.cache_repo(@project) == {:ok, %{cached?: true}}

      assert git!(context.local, ~w(status --porcelain)) == ""
    end
  end

  describe "get_last_commit_id/1" do
    setup context do
      %{upstream: upstream!(context)}
    end

    test "reads the commit of the main branch when Git also writes to stderr", context do
      put_env("GIT_TRACE", "1")

      assert Git.get_last_commit_id(@project) == {:ok, context.main}
    end

    test "skips other branches whose names end in the main branch", context do
      git!(context.local, [
        "push",
        "--quiet",
        context.upstream,
        "#{context.stale}:refs/heads/a/refs/heads/main"
      ])

      assert Git.get_last_commit_id(@project) == {:ok, context.main}
    end

    test "returns an error when the upstream has no main branch", context do
      git!(context.upstream, ~w(update-ref -d refs/heads/main))

      assert Git.get_last_commit_id(@project) == {:error, {:ref_not_found, "refs/heads/main"}}
    end
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

      assert Git.push(@project, @remote_url) == {:error, :fork_main_diverged}

      assert refs(context.fork) == %{"main" => diverged}
    end
  end

  describe "a cache that is inside another repository" do
    test "keeps Git from changing that repository when the checkout is missing" do
      outer = Maintenance.cache_path()

      on_exit(fn ->
        Enum.each(~w(.git file.txt untracked.txt), &File.rm_rf!(Path.join(outer, &1)))
      end)

      git!(outer, ~w(init --quiet --initial-branch main))
      commit!(outer, "committed")
      file = Path.join(outer, "file.txt")
      untracked = Path.join(outer, "untracked.txt")
      File.write!(file, "edited")
      File.write!(untracked, "untracked")

      checkout = Git.path(:otp)
      File.rm_rf!(checkout)
      File.mkdir_p!(checkout)
      on_exit(fn -> File.rm_rf!(checkout) end)

      assert {:error, _reason} = Git.discard_changes(:otp)

      assert File.read!(file) == "edited"
      assert File.read!(untracked) == "untracked"
    end
  end

  # Makes every git command in the test send `url` to `replacement`.
  defp redirect_url(url, replacement) do
    variables = %{
      "GIT_CONFIG_COUNT" => "1",
      "GIT_CONFIG_KEY_0" => "url.#{replacement}.insteadOf",
      "GIT_CONFIG_VALUE_0" => url
    }

    Enum.each(variables, fn {name, value} -> put_env(name, value) end)
  end

  # A bare repository with the checkout's main branch, which stands in for the upstream.
  defp upstream!(context) do
    upstream = Path.join(context.tmp_dir, "upstream.git")
    git!(context.tmp_dir, ["init", "--quiet", "--bare", upstream])
    git!(context.local, ["push", "--quiet", upstream, "main"])
    redirect_url(Project.git_url(@project), "file://" <> upstream)
    upstream
  end
end
