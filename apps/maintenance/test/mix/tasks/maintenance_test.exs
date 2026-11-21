defmodule Mix.Tasks.MaintenanceTest do
  use ExUnit.Case, async: false

  import Maintenance.GitHelpers

  alias Maintenance.Git
  alias Maintenance.Github
  alias Mix.Tasks.Maintenance.Publish
  alias Mix.Tasks.Maintenance.Run
  alias Mix.Tasks.Maintenance.Status

  @moduletag :tmp_dir

  @branch "fake_job_1"
  @pull_request_url "https://github.com/maintenance-beam/elixir/pull/3"

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
    test "lists the commands, the projects with their jobs, and the forks" do
      Mix.Tasks.Maintenance.run([])

      output = printed()
      assert output =~ "mix maintenance.status [PROJECT [JOB]]"
      assert output =~ "mix maintenance.run PROJECT JOB"
      assert output =~ "mix maintenance.publish PROJECT JOB --fork FORK"
      assert output =~ ~r/^  elixir  .*unicode/m
      assert output =~ ~r/^  otp    .*unicode/m
      assert output =~ ~r/^  maintenance-beam      For real pull requests\./m
      assert output =~ ~r/^  maintenance-beam-app  For trial runs\./m
    end
  end

  describe "mix maintenance.status" do
    test "prints one line for a due job" do
      Status.run(["elixir", "fake_job"])

      assert printed() == "elixir  fake_job  0.0.1 -> 1.0.0  due\n"
    end

    test "prints the URL of the pull request that is open" do
      Req.Test.stub(Github, fn conn ->
        Req.Test.json(conn, [%{"html_url" => @pull_request_url}])
      end)

      Status.run(["elixir", "fake_job"])

      assert printed() == "elixir  fake_job  0.0.1 -> 1.0.0  PR open: #{@pull_request_url}\n"
    end

    test "prints the current version of a job that is up to date" do
      set_status({:up_to_date, info()})

      Status.run(["elixir", "fake_job"])

      assert printed() == "elixir  fake_job  0.0.1  up to date\n"
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
      assert output =~ "Committed #{@branch} in #{local}"
      assert output =~ ~r/1 file changed/
      assert output =~ "git -C #{local} show --stat #{@branch}"
      assert output =~ "mix maintenance.publish elixir fake_job --fork FORK"
      assert output =~ "Forks for --fork."
    end
  end

  describe "mix maintenance.publish" do
    test "requires --fork and lists the forks" do
      error = assert_raise Mix.Error, fn -> Publish.run(["elixir", "fake_job"]) end

      assert error.message =~ ~r/\AMissing --fork\.\n\nForks for --fork\./
      assert error.message =~ ~r/^  maintenance-beam      For real pull requests\./m
      assert error.message =~ ~r/^  maintenance-beam-app  For trial runs\./m
    end

    test "rejects a fork that is not configured" do
      error =
        assert_raise Mix.Error, fn -> Publish.run(["elixir", "fake_job", "--fork", "someone"]) end

      assert error.message =~ ~r/\AUnknown fork "someone"\.\n\nForks for --fork\./
      assert error.message =~ ~r/^  maintenance-beam-app  For trial runs\./m
    end

    test "rejects an unknown project and an unknown job before the fork" do
      assert_raise Mix.Error, ~r/Unknown project "nope"/, fn ->
        Publish.run(["nope", "unicode", "--fork", "maintenance-beam"])
      end

      assert_raise Mix.Error, ~r/Unknown job for elixir "nope"/, fn ->
        Publish.run(["elixir", "nope", "--fork", "maintenance-beam"])
      end
    end

    test "rejects an option it does not know" do
      assert_raise OptionParser.ParseError, fn ->
        Publish.run(["elixir", "fake_job", "--fork", "maintenance-beam", "--force"])
      end
    end

    test "tells to run maintenance.run first when there is no commit" do
      checkout = Git.path(:elixir)
      File.rm_rf!(checkout)

      error =
        assert_raise Mix.Error, fn ->
          Publish.run(["elixir", "fake_job", "--fork", "maintenance-beam"])
        end

      assert error.message ==
               "There is no commit to publish for elixir fake_job. " <>
                 "Run `mix maintenance.run elixir fake_job` first."
    end

    test "tells how to set the token when it is missing" do
      previous = System.get_env("GITHUB_ACCESS_TOKEN")
      on_exit(fn -> System.put_env("GITHUB_ACCESS_TOKEN", previous) end)
      System.delete_env("GITHUB_ACCESS_TOKEN")

      error =
        assert_raise Mix.Error, fn ->
          Publish.run(["elixir", "fake_job", "--fork", "maintenance-beam"])
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

  defp set_status(status) do
    Application.put_env(:maintenance, MaintenanceJob.FakeJob, status: status, notify: self())
  end

  defp info() do
    %{current: Version.parse!("0.0.1"), latest: Version.parse!("1.0.0"), branch: @branch}
  end
end
