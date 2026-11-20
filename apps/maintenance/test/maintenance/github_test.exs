defmodule Maintenance.GithubTest do
  use ExUnit.Case, async: false

  alias Maintenance.Github

  @body %{"title" => "Update Unicode", "head" => "owner:branch", "base" => "main"}

  describe "create_pull_request/3" do
    test "posts the body to the repository's pulls endpoint and returns the pull request" do
      Req.Test.stub(Github, fn conn ->
        assert conn.method == "POST"
        assert conn.host == "api.github.com"
        assert conn.request_path == "/repos/owner/repo/pulls"
        assert Plug.Conn.get_req_header(conn, "accept") == ["application/vnd.github+json"]
        assert ["token " <> _] = Plug.Conn.get_req_header(conn, "authorization")

        {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(raw_body) == @body

        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{"html_url" => "https://github.com/owner/repo/pull/1"})
      end)

      assert Github.create_pull_request("owner", "repo", @body) ==
               {:ok, %{"html_url" => "https://github.com/owner/repo/pull/1"}}
    end

    test "returns the response body as the error when GitHub rejects the request" do
      Req.Test.stub(Github, fn conn ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{"message" => "Validation Failed"})
      end)

      assert Github.create_pull_request("owner", "repo", @body) ==
               {:error, %{"message" => "Validation Failed"}}
    end

    test "returns the exception when the request cannot be sent" do
      Req.Test.stub(Github, &Req.Test.transport_error(&1, :econnrefused))

      assert Github.create_pull_request("owner", "repo", @body) ==
               {:error, %Req.TransportError{reason: :econnrefused}}
    end
  end

  describe "find_pull_request/3" do
    setup do
      previous = System.get_env("GITHUB_ACCESS_TOKEN")
      System.delete_env("GITHUB_ACCESS_TOKEN")

      on_exit(fn ->
        if previous, do: System.put_env("GITHUB_ACCESS_TOKEN", previous)
      end)
    end

    test "returns the URL of the pull request opened from the branch, in any state" do
      Req.Test.stub(Github, fn conn ->
        assert conn.method == "GET"
        assert conn.host == "api.github.com"
        assert conn.request_path == "/repos/owner/repo/pulls"

        assert %{"head" => "owner:unicode_17.0.0", "state" => "all"} =
                 Plug.Conn.fetch_query_params(conn).query_params

        Req.Test.json(conn, [%{"html_url" => "https://github.com/owner/repo/pull/7"}])
      end)

      assert Github.find_pull_request("owner", "repo", "unicode_17.0.0") ==
               {:ok, "https://github.com/owner/repo/pull/7"}
    end

    test "returns :none when no pull request has that head" do
      Req.Test.stub(Github, &Req.Test.json(&1, []))

      assert Github.find_pull_request("owner", "repo", "unicode_17.0.0") == :none
    end

    test "returns the status and body as the error when GitHub rejects the request" do
      Req.Test.stub(Github, fn conn ->
        conn
        |> Plug.Conn.put_status(403)
        |> Req.Test.json(%{"message" => "API rate limit exceeded"})
      end)

      assert Github.find_pull_request("owner", "repo", "unicode_17.0.0") ==
               {:error, {403, %{"message" => "API rate limit exceeded"}}}
    end

    test "returns the exception when the request cannot be sent" do
      Req.Test.stub(Github, &Req.Test.transport_error(&1, :econnrefused))

      assert Github.find_pull_request("owner", "repo", "unicode_17.0.0") ==
               {:error, %Req.TransportError{reason: :econnrefused}}
    end

    test "sends no token when GITHUB_ACCESS_TOKEN is unset" do
      Req.Test.stub(Github, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == []
        Req.Test.json(conn, [])
      end)

      assert Github.find_pull_request("owner", "repo", "unicode_17.0.0") == :none
    end

    test "sends the token when GITHUB_ACCESS_TOKEN is set" do
      System.put_env("GITHUB_ACCESS_TOKEN", "secret")

      Req.Test.stub(Github, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["token secret"]
        Req.Test.json(conn, [])
      end)

      assert Github.find_pull_request("owner", "repo", "unicode_17.0.0") == :none
    end
  end
end
