defmodule Maintenance.GitTest do
  use ExUnit.Case, async: false

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
      upstream = Path.join(context.tmp_dir, "upstream.git")
      git!(context.tmp_dir, ["init", "--quiet", "--bare", upstream])
      git!(context.local, ["push", "--quiet", upstream, "main"])
      redirect_url(Project.git_url(@project), "file://" <> upstream)

      tracked = Path.join(context.local, "file.txt")
      untracked = Path.join(context.local, "stray.txt")
      File.write!(tracked, "changed")
      File.write!(untracked, "left behind")

      assert Git.cache_repo(@project) == {:ok, %{cached?: true}}

      assert git!(context.local, ~w(status --porcelain)) == ""
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

  # Makes every git command in the test send `url` to `replacement`.
  defp redirect_url(url, replacement) do
    variables = %{
      "GIT_CONFIG_COUNT" => "1",
      "GIT_CONFIG_KEY_0" => "url.#{replacement}.insteadOf",
      "GIT_CONFIG_VALUE_0" => url
    }

    for {name, value} <- variables do
      previous = System.get_env(name)
      on_exit(fn -> restore_env(name, previous) end)
      System.put_env(name, value)
    end
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
