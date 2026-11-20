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

  @spec fetch(String.t()) :: {:ok, list()} | {:error, Exception.t()}
  def fetch(url = "https://api.github.com/" <> _rest) do
    request_headers = [
      {"Accept", "application/vnd.github.v3+json"},
      {"Authorization", "token " <> Maintenance.github_access_token!()}
    ]

    result = Req.get(url, [headers: request_headers] ++ @req_options)

    case result do
      {:ok, %{status: 200} = response} ->
        fetch_link(response)

      {:error, exception} ->
        {:error, exception}
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

  defp fetch_link(response = %{headers: headers}) do
    case Map.fetch(headers, "link") do
      {:ok, link} ->
        # <https://api.github.com/repositories/374927/releases?per_page=100&page=2>; rel="next", <https://api.github.com/repositories/374927/releases?per_page=100&page=2>; rel="last"
        case Regex.run(~r/<([^>]+)>; rel="next"/, link, capture: :all_but_first) do
          nil ->
            body = Map.fetch!(response, :body)

            {:ok, body}

          [next_url] ->
            {:ok, next_json} = fetch(next_url)
            body = Map.fetch!(response, :body)

            {:ok, List.wrap(body) ++ next_json}
        end

      :error ->
        exception =
          ArgumentError.exception(
            "link not found in headers, got: #{inspect(headers, limit: :infinity)}"
          )

        {:error, exception}
    end
  end
end
