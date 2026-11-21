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
        assert ["token " <> _token] = Plug.Conn.get_req_header(conn, "authorization")

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

    test "returns the open pull request opened from the branch" do
      Req.Test.stub(Github, fn conn ->
        assert conn.method == "GET"
        assert conn.host == "api.github.com"
        assert conn.request_path == "/repos/owner/repo/pulls"

        assert %{"head" => "owner:unicode_17.0.0", "state" => "all"} =
                 Plug.Conn.fetch_query_params(conn).query_params

        Req.Test.json(conn, [pull_request(7, "open")])
      end)

      assert Github.find_pull_request("owner", "repo", "unicode_17.0.0") ==
               {:open, "https://github.com/owner/repo/pull/7"}
    end

    test "returns the open pull request even when a newer one was closed" do
      Req.Test.stub(
        Github,
        &Req.Test.json(&1, [pull_request(8, "closed"), pull_request(7, "open")])
      )

      assert Github.find_pull_request("owner", "repo", "unicode_17.0.0") ==
               {:open, "https://github.com/owner/repo/pull/7"}
    end

    test "returns the newest closed pull request when none is open" do
      Req.Test.stub(
        Github,
        &Req.Test.json(&1, [pull_request(8, "closed"), pull_request(7, "closed")])
      )

      assert Github.find_pull_request("owner", "repo", "unicode_17.0.0") ==
               {:closed, "https://github.com/owner/repo/pull/8"}
    end

    test "returns :none when no pull request has that head" do
      Req.Test.stub(Github, &Req.Test.json(&1, []))

      assert Github.find_pull_request("owner", "repo", "unicode_17.0.0") == :none
    end

    test "names the repository when GitHub does not have it" do
      Req.Test.stub(Github, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"message" => "Not Found"})
      end)

      assert Github.find_pull_request("owner", "repo", "unicode_17.0.0") ==
               {:error, {:not_found, "owner/repo"}}
    end

    test "returns the status and body as the error when GitHub rejects the request" do
      Req.Test.stub(Github, fn conn ->
        conn
        |> Plug.Conn.put_status(403)
        |> Req.Test.json(%{"message" => "Repository access blocked"})
      end)

      assert Github.find_pull_request("owner", "repo", "unicode_17.0.0") ==
               {:error, {403, %{"message" => "Repository access blocked"}}}
    end

    test "returns when the rate limit resets when GitHub answers 429 with none left" do
      Req.Test.stub(Github, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-ratelimit-remaining", "0")
        |> Plug.Conn.put_resp_header("x-ratelimit-reset", "1795300860")
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"message" => "API rate limit exceeded"})
      end)

      assert Github.find_pull_request("owner", "repo", "unicode_17.0.0") ==
               {:error, {:rate_limited, ~U[2026-11-21 22:41:00Z]}}
    end

    test "returns the exception when the request cannot be sent" do
      Req.Test.stub(Github, &Req.Test.transport_error(&1, :econnrefused))

      assert Github.find_pull_request("owner", "repo", "unicode_17.0.0") ==
               {:error, %Req.TransportError{reason: :econnrefused}}
    end

    test "sends no token, even when GITHUB_ACCESS_TOKEN is set" do
      System.put_env("GITHUB_ACCESS_TOKEN", "secret")

      Req.Test.stub(Github, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == []
        Req.Test.json(conn, [])
      end)

      assert Github.find_pull_request("owner", "repo", "unicode_17.0.0") == :none
    end
  end

  defp pull_request(number, state) do
    %{"html_url" => "https://github.com/owner/repo/pull/#{number}", "state" => state}
  end
end
