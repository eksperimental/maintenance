defmodule Mix.Tasks.MaintenanceTest do
  use ExUnit.Case, async: false

  import Maintenance.GitHelpers

  alias Maintenance.Git
  alias Maintenance.Github
  alias MaintenanceJob.Unicode
  alias Mix.Tasks.Maintenance.Publish
  alias Mix.Tasks.Maintenance.Run
  alias Mix.Tasks.Maintenance.Status

  @moduletag :tmp_dir

  @branch "fake_job_1"
  @pull_request_url "https://github.com/some-account/elixir/pull/3"

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)

    previous = Application.get_env(:maintenance, MaintenanceJob.FakeJob)
    on_exit(fn -> Application.put_env(:maintenance, MaintenanceJob.FakeJob, previous) end)
    set_status({:due, info()})

    Req.Test.stub(Github, fn conn -> Req.Test.json(conn, []) end)
    :ok
  end

  describe "mix maintenance" do
    test "lists the commands, the projects with their jobs, and the default fork" do
      Mix.Tasks.Maintenance.run([])

      output = printed()
      assert output =~ "mix maintenance.status [PROJECT [JOB]]"
      assert output =~ "mix maintenance.run PROJECT JOB"
      assert output =~ "mix maintenance.publish PROJECT JOB"
      assert output =~ ~r/^  elixir  .*unicode/m
      assert output =~ ~r/^  otp    .*unicode/m
      assert output =~ "Pull requests are opened inside the fork of some-account (GITHUB_ACCOUNT)"
      assert output =~ "--fork OWNER"
    end
  end

  describe "mix maintenance.status" do
    test "prints one line for a due job" do
      Status.run(["elixir", "fake_job"])

      assert printed() == "elixir  fake_job  0.0.1 -> 1.0.0  due\n"
    end

    test "prints the URL of the pull request open on the fork of GITHUB_ACCOUNT" do
      stub_pull_request("some-account")

      Status.run(["elixir", "fake_job"])

      assert printed() == "elixir  fake_job  0.0.1 -> 1.0.0  PR open: #{@pull_request_url}\n"
    end

    test "looks for the pull request on the fork given as --fork" do
      stub_pull_request("someone")

      Status.run(["elixir", "fake_job", "--fork", "someone"])

      assert printed() == "elixir  fake_job  0.0.1 -> 1.0.0  PR open: #{@pull_request_url}\n"
    end

    test "prints the URL of a closed pull request and leaves the job due" do
      stub_pull_request("some-account", "closed")

      Status.run(["elixir", "fake_job"])

      assert printed() ==
               "elixir  fake_job  0.0.1 -> 1.0.0  due (closed PR: #{@pull_request_url})\n"
    end

    test "prints the current version of a job that is up to date" do
      set_status({:up_to_date, info()})

      Status.run(["elixir", "fake_job"])

      assert printed() == "elixir  fake_job  0.0.1  up to date\n"
    end

    test "prints every job, names the repository missing from the fork, then fails" do
      stub_unicode_versions()

      Req.Test.stub(Github, fn conn ->
        case conn.request_path do
          "/repos/some-account/otp/pulls" ->
            conn
            |> Plug.Conn.put_status(404)
            |> Req.Test.json(%{"message" => "Not Found"})

          _other ->
            Req.Test.json(conn, [])
        end
      end)

      error = assert_raise Mix.Error, fn -> Status.run([]) end

      assert printed() == """
             elixir  fake_job  0.0.1 -> 1.0.0    due
             elixir  unicode   16.0.0 -> 17.0.0  due
             otp     unicode                     error: some-account/otp not found on GitHub
             """

      assert error.message == "Could not check otp unicode"
    end

    test "asks for --fork or GITHUB_ACCOUNT when neither is given" do
      put_env("GITHUB_ACCOUNT", nil)

      error = assert_raise Mix.Error, fn -> Status.run(["elixir", "fake_job"]) end

      assert error.message =~ "Pass --fork OWNER, or add `export GITHUB_ACCOUNT="
    end

    test "rejects an unknown project and lists the projects" do
      error = assert_raise Mix.Error, fn -> Status.run(["erlang"]) end

      assert error.message == ~s(Unknown project "erlang". Valid projects: elixir, otp)
    end

    test "rejects an unknown job and lists the jobs of the project" do
      error = assert_raise Mix.Error, fn -> Status.run(["elixir", "nope"]) end

      assert error.message =~ ~s(Unknown job for elixir "nope". Valid jobs for elixir: )
      assert error.message =~ "fake_job"
      assert error.message =~ "unicode"
    end

    test "rejects more arguments than a project and a job" do
      error = assert_raise Mix.Error, fn -> Status.run(["elixir", "fake_job", "extra"]) end

      assert error.message =~ "Usage: mix maintenance.status [PROJECT [JOB]]"
    end
  end

  describe "mix maintenance.run" do
    test "rejects an unknown project and an unknown job" do
      assert_raise Mix.Error, ~r/Unknown project "nope"/, fn -> Run.run(["nope", "unicode"]) end
      assert_raise Mix.Error, ~r/Unknown job for otp "nope"/, fn -> Run.run(["otp", "nope"]) end
    end

    test "tells the usage when the job is missing" do
      assert_raise Mix.Error, ~r/Usage: mix maintenance.run PROJECT JOB/, fn ->
        Run.run(["elixir"])
      end
    end

    test "stops before building when Git does not know who the runner is" do
      for name <-
            ~w(GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL EMAIL),
          do: put_env(name, nil)

      put_env("GIT_CONFIG_GLOBAL", "/dev/null")
      put_env("GIT_CONFIG_NOSYSTEM", "1")

      error = assert_raise Mix.Error, fn -> Run.run(["elixir", "fake_job"]) end

      assert error.message =~ "Git does not know who you are"
      assert error.message =~ ~s(git config --global user.email "you@example.com")
      refute_received {:prepare, _project}
    end

    test "says there is nothing to do when the job is up to date" do
      set_status({:up_to_date, info()})

      Run.run(["elixir", "fake_job"])

      assert printed() == "elixir fake_job is up to date. Nothing to do.\n"
    end

    test "shows where the commit is and what to run next", %{tmp_dir: _tmp_dir} do
      local = Git.path(:elixir)
      File.rm_rf!(local)
      File.mkdir_p!(local)
      on_exit(fn -> File.rm_rf!(local) end)

      git!(local, ~w(init --quiet --initial-branch main))
      commit!(local, "main")
      git!(local, ~w(checkout --quiet -b #{@branch}))
      commit!(local, "Update Fake to version 1")
      git!(local, ~w(checkout --quiet main))

      Run.run(["elixir", "fake_job"])

      output = printed()
      assert output =~ ~r/1 file changed/
      assert output =~ "git -C #{local} show --stat #{@branch}"
      assert output =~ "Committed #{@branch} as Test <test@example.com> in #{local}"
      assert output =~ "open the pull request in the fork of some-account:"
      assert output =~ ~r/^  mix maintenance\.publish elixir fake_job$/m
    end
  end

  describe "mix maintenance.publish" do
    test "rejects an empty --fork" do
      assert_raise Mix.Error, ~r/--fork needs the GitHub account/, fn ->
        Publish.run(["elixir", "fake_job", "--fork", ""])
      end
    end

    test "rejects an unknown project and an unknown job" do
      assert_raise Mix.Error, ~r/Unknown project "nope"/, fn ->
        Publish.run(["nope", "unicode"])
      end

      assert_raise Mix.Error, ~r/Unknown job for elixir "nope"/, fn ->
        Publish.run(["elixir", "nope"])
      end
    end

    test "rejects an option it does not know" do
      assert_raise OptionParser.ParseError, fn ->
        Publish.run(["elixir", "fake_job", "--force"])
      end
    end

    test "tells to run maintenance.run first when there is no commit" do
      checkout = Git.path(:elixir)
      File.rm_rf!(checkout)

      error =
        assert_raise Mix.Error, fn ->
          Publish.run(["elixir", "fake_job"])
        end

      assert error.message ==
               "There is no commit to publish for elixir fake_job. " <>
                 "Run `mix maintenance.run elixir fake_job` first."
    end

    test "says there is nothing to do when the job is up to date" do
      set_status({:up_to_date, info()})

      Publish.run(["elixir", "fake_job"])

      assert printed() == "elixir fake_job is up to date. Nothing to do.\n"
    end

    test "explains how to sync the fork when its main branch has commits upstream lacks",
         %{tmp_dir: tmp_dir} do
      context = fork_checkout!(tmp_dir, :elixir, "some-account", @branch)

      ahead =
        git!(context.local, [
          "commit-tree",
          "#{context.main}^{tree}",
          "-p",
          context.main,
          "-m",
          "ahead"
        ])

      git!(context.local, ["push", "--quiet", context.fork, "#{ahead}:refs/heads/main"])

      Req.Test.stub(Github, fn
        %{method: "GET"} = conn -> Req.Test.json(conn, [])
        %{method: "POST"} -> flunk("a pull request was opened")
      end)

      error = assert_raise Mix.Error, fn -> Publish.run(["elixir", "fake_job"]) end

      assert error.message =~
               "some-account/elixir has commits that elixir-lang/elixir does not have"

      assert error.message =~ "Sync fork"
      assert error.message =~ "Discard commits"
      assert error.message =~ "mix maintenance.publish elixir fake_job"
      assert refs(context.fork) == %{"main" => ahead}
    end

    test "tells how to set the token when it is missing" do
      previous = System.get_env("GITHUB_ACCESS_TOKEN")
      on_exit(fn -> System.put_env("GITHUB_ACCESS_TOKEN", previous) end)
      System.delete_env("GITHUB_ACCESS_TOKEN")

      error =
        assert_raise Mix.Error, fn ->
          Publish.run(["elixir", "fake_job"])
        end

      assert error.message =~ "GITHUB_ACCESS_TOKEN is not set"
    end
  end

  defp printed(output \\ "") do
    receive do
      {:mix_shell, :info, [line]} -> printed(output <> line <> "\n")
    after
      0 -> output
    end
  end

  # Sets the variable, or deletes it for nil, until the test ends.
  defp put_env(name, value) do
    previous = System.get_env(name)
    on_exit(fn -> restore_env(name, previous) end)
    restore_env(name, value)
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  defp stub_pull_request(fork, state \\ "open") do
    Req.Test.stub(Github, fn conn ->
      case String.split(conn.request_path, "/") do
        ["", "repos", ^fork, "elixir", "pulls"] ->
          Req.Test.json(conn, [%{"html_url" => @pull_request_url, "state" => state}])

        _other ->
          Req.Test.json(conn, [])
      end
    end)
  end

  defp stub_unicode_versions() do
    Req.Test.stub(Unicode, fn conn ->
      case conn.request_path do
        "/versions/latest/" ->
          conn
          |> Plug.Conn.put_resp_header(
            "location",
            "https://www.unicode.org/versions/Unicode17.0.0/"
          )
          |> Plug.Conn.send_resp(302, "")

        "/elixir-lang/elixir/main/lib/elixir/unicode/unicode.ex" ->
          Plug.Conn.send_resp(conn, 200, "  def version, do: {16, 0, 0}\n")

        "/erlang/otp/master/lib/stdlib/uc_spec/gen_unicode_mod.escript" ->
          Plug.Conn.send_resp(conn, 200, ~S|io:put_chars(Fd, "spec_version() -> {16,0}.\n"),|)
      end
    end)
  end

  defp set_status(status) do
    Application.put_env(:maintenance, MaintenanceJob.FakeJob, status: status, notify: self())
  end

  defp info() do
    %{current: Version.parse!("0.0.1"), latest: Version.parse!("1.0.0"), branch: @branch}
  end
end
