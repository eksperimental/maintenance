defmodule Maintenance.Github do
  # COPYRIGHT NOTICE:
  # Some functions in the this module have been adapted and ported from Erlang into Elixir by the author,
  # taken from the source code of the erlang.org website:
  # https://github.com/erlang/erlang-org
  # See the /NOTICE file for more information about the copyright holders and the license.
  # The files where the code has been taken are:
  # https://github.com/erlang/erlang-org/blob/39521fb11b3545d69bc26e4a5a9b02995a0f4e49/_scripts/src/create-releases.erl
  # https://github.com/erlang/erlang-org/blob/39521fb11b3545d69bc26e4a5a9b02995a0f4e49/_scripts/src/gh.erl

  @moduledoc """
  Module interacts with GitHub API.
  """

  @req_options [receive_timeout: 60_000 * 5] ++
                 Application.compile_env(:maintenance, :github_req_options, [])

  @doc """
  Finds the pull request whose head is `branch` on `owner/repo`.

  An open pull request wins. Otherwise the newest closed one is returned, so the caller can
  tell that an earlier attempt was closed.

  The pull requests are opened inside a fork, so the head's owner is the repository's owner.
  No token is sent, so an expired `GITHUB_ACCESS_TOKEN` cannot break `status` and `run`.
  When GitHub has no `owner/repo`, such as a fork that was never made, the error is
  `{:not_found, "owner/repo"}`. When the rate limit for requests without a token is used
  up, the error is `{:rate_limited, reset_at}`.
  """
  @spec find_pull_request(String.t(), String.t(), String.t()) ::
          {:open | :closed, url :: String.t()}
          | :none
          | {:error, {:not_found, String.t()} | {:rate_limited, DateTime.t()} | term()}
  def find_pull_request(owner, repo, branch) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/pulls"

    options =
      [
        params: [head: owner <> ":" <> branch, state: "all"],
        headers: [{"Accept", "application/vnd.github+json"}]
      ] ++ @req_options

    case Req.get(url, options) do
      {:ok, %{status: 200, body: []}} -> :none
      {:ok, %{status: 200, body: [_first | _rest] = pull_requests}} -> pick(pull_requests)
      {:ok, %{status: 404}} -> {:error, {:not_found, owner <> "/" <> repo}}
      {:ok, %{status: status} = response} when status in [403, 429] -> rejected(response)
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp rejected(%{headers: %{"x-ratelimit-remaining" => ["0"], "x-ratelimit-reset" => [reset]}}) do
    reset_at =
      reset
      |> String.to_integer()
      |> DateTime.from_unix!()

    {:error, {:rate_limited, reset_at}}
  end

  defp rejected(%{status: status, body: body}), do: {:error, {status, body}}

  # GitHub lists the newest pull request first.
  defp pick(pull_requests) do
    case Enum.find(pull_requests, &(&1["state"] == "open")) do
      %{"html_url" => url} -> {:open, url}
      nil -> {:closed, hd(pull_requests)["html_url"]}
    end
  end

  @spec create_pull_request(String.t(), String.t(), map) :: {:ok, map} | {:error, term()}
  def create_pull_request(owner, repo, body) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/pulls"

    request_headers = [
      {"Accept", "application/vnd.github+json"},
      {"Authorization", "token " <> Maintenance.github_access_token!()}
    ]

    case Req.post(url, [json: body, headers: request_headers] ++ @req_options) do
      {:ok, %{status: status, body: pull_request}}
      when status in 200..299 and is_map(pull_request) ->
        {:ok, pull_request}

      {:ok, %{body: response_body}} ->
        {:error, response_body}

      {:error, exception} ->
        {:error, exception}
    end
  end
end
