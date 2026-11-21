defmodule Maintenance.GitTest do
  use ExUnit.Case, async: false

  import Maintenance.GitHelpers

  alias Maintenance.{Git, Project}

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
end
