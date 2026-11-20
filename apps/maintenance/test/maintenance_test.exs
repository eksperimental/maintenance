defmodule MaintenanceTest do
  use ExUnit.Case, async: false

  import Maintenance.GitHelpers

  alias Maintenance.Git
  alias Maintenance.Github

  @moduletag :tmp_dir

  @project :elixir
  @job :fake_job
  @fork "maintenance-beam-app"
  @other_fork "maintenance-beam"
  @branch "fake_job_1"
  @pull_request_url "https://github.com/#{@fork}/elixir/pull/3"

  describe "github_access_token!/0" do
    setup do
      previous = System.get_env("GITHUB_ACCESS_TOKEN")
      on_exit(fn -> System.put_env("GITHUB_ACCESS_TOKEN", previous) end)
    end

    test "returns the token from the environment" do
      System.put_env("GITHUB_ACCESS_TOKEN", "secret")

      assert Maintenance.github_access_token!() == "secret"
    end

    test "tells how to set the token when it is missing" do
      System.delete_env("GITHUB_ACCESS_TOKEN")

      assert_raise RuntimeError, ~r/\.env.*source \.env/, &Maintenance.github_access_token!/0
    end
  end

  describe "run/2" do
    setup :set_job_status

    test "builds the commit when the job is due and no fork has a pull request" do
      stub_pull_requests(%{})

      assert Maintenance.run(@project, @job) ==
               {:committed, %{branch: @branch, path: Git.path(@project)}}

      assert_received {:prepare, @project}
    end

    test "does not build anything when a fork already has a pull request" do
      stub_pull_requests(%{@other_fork => @pull_request_url})

      assert Maintenance.run(@project, @job) == {:pr_exists, @pull_request_url}

      refute_received {:prepare, _project}
    end

    test "does not ask GitHub or build anything when the job is up to date" do
      Req.Test.stub(Github, fn _conn -> flunk("GitHub was asked") end)
      set_status({:up_to_date, info()})

      assert Maintenance.run(@project, @job) == :up_to_date

      refute_received {:prepare, _project}
    end
  end

  describe "publish/3" do
    setup :set_job_status

    setup %{tmp_dir: tmp_dir} do
      local = Git.path(@project)
      File.rm_rf!(local)
      File.mkdir_p!(local)
      on_exit(fn -> File.rm_rf!(local) end)

      git!(local, ~w(init --quiet --initial-branch main))
      main = commit!(local, "main")
      git!(local, ~w(checkout --quiet -b #{@branch}))
      tip = commit!(local, "Update Fake to version 1\n\nWhy it changed.")
      git!(local, ~w(checkout --quiet main))

      fork = Path.join(tmp_dir, "fork.git")
      git!(tmp_dir, ["init", "--quiet", "--bare", fork])

      # Send the fork's URL to the bare repository, and every other URL nowhere.
      fork_url = Maintenance.Project.fork_url(@project, @fork)
      auth_url = Maintenance.auth_url(fork_url)
      git!(local, ["config", "url.file://#{fork}.insteadOf", auth_url])
      git!(local, ["config", "url.file:///nonexistent/.insteadOf", "https://"])

      %{local: local, fork: fork, main: main, tip: tip}
    end

    test "pushes the existing commit unchanged and opens a pull request titled with its subject",
         context do
      test_pid = self()

      Req.Test.stub(Github, fn
        %{method: "GET"} = conn ->
          Req.Test.json(conn, [])

        %{method: "POST", request_path: path} = conn ->
          {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
          send(test_pid, {:pull_request, path, Jason.decode!(raw_body)})

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"html_url" => @pull_request_url})
      end)

      assert Maintenance.publish(@project, @job, @fork) == {:opened, @pull_request_url}

      assert refs(context.fork) == %{@branch => context.tip, "main" => context.main}

      assert_received {:pull_request, "/repos/#{@fork}/elixir/pulls", body}
      assert body["title"] == "Update Fake to version 1"
      assert body["head"] == "#{@fork}:#{@branch}"
      assert body["base"] == "main"

      assert git!(context.local, ~w(branch --show-current)) == "main"
    end

    test "pushes nothing when a pull request already exists", context do
      Req.Test.stub(Github, fn
        %{method: "GET"} = conn -> Req.Test.json(conn, [%{"html_url" => @pull_request_url}])
        %{method: "POST"} -> flunk("a pull request was opened")
      end)

      assert Maintenance.publish(@project, @job, @fork) == {:pr_exists, @pull_request_url}

      assert refs(context.fork) == %{}
    end

    test "tells that the branch is missing when run has not built it", context do
      Req.Test.stub(Github, fn _conn -> flunk("GitHub was asked") end)
      set_status({:due, info("unicode_0.0.0")})

      assert Maintenance.publish(@project, @job, @fork) == {:error, :branch_missing}

      assert refs(context.fork) == %{}
    end

    test "tells that the branch is missing when it has no commits of its own", context do
      Req.Test.stub(Github, fn _conn -> flunk("GitHub was asked") end)
      git!(context.local, ~w(branch empty main))
      set_status({:due, info("empty")})

      assert Maintenance.publish(@project, @job, @fork) == {:error, :branch_missing}

      assert refs(context.fork) == %{}
    end

    test "tells that the branch is missing when there is no checkout at all", context do
      Req.Test.stub(Github, fn _conn -> flunk("GitHub was asked") end)
      File.rm_rf!(context.local)

      assert Maintenance.publish(@project, @job, @fork) == {:error, :branch_missing}
    end
  end

  defp set_job_status(_context) do
    previous = Application.get_env(:maintenance, MaintenanceJob.FakeJob)
    on_exit(fn -> Application.put_env(:maintenance, MaintenanceJob.FakeJob, previous) end)
    set_status({:due, info()})
  end

  defp set_status(status) do
    Application.put_env(:maintenance, MaintenanceJob.FakeJob, status: status, notify: self())
  end

  defp info(branch \\ @branch) do
    %{current: Version.parse!("0.0.1"), latest: Version.parse!("1.0.0"), branch: branch}
  end

  # Answers the pull request lookups: `pull_requests` maps a fork to the URL of its pull request.
  defp stub_pull_requests(pull_requests) do
    Req.Test.stub(Github, fn conn ->
      ["", "repos", fork, "elixir", "pulls"] = String.split(conn.request_path, "/")

      case Map.fetch(pull_requests, fork) do
        {:ok, url} -> Req.Test.json(conn, [%{"html_url" => url}])
        :error -> Req.Test.json(conn, [])
      end
    end)
  end
end
