defmodule Maintenance.GithubTest do
  use ExUnit.Case, async: true

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
end
