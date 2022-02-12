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

  @req_options [receive_timeout: 60_000 * 5]

  def get!(url = "https://api.github.com/" <> _) do
    request_headers = [
      {"Accept", "application/vnd.github.v3+json"},
      {"Authorization", "token " <> Maintenance.github_access_token!()}
    ]

    response = Req.get!(url, [headers: request_headers] ++ @req_options)

    case response do
      %{status: 200} ->
        get_link(response)

      _ ->
        :error
    end
  end

  defp get_link(response = %{headers: headers}) do
    case List.keyfind(headers, "link", 0) do
      {"link", link} ->
        # <https://api.github.com/repositories/374927/releases?per_page=100&page=2>; rel="next", <https://api.github.com/repositories/374927/releases?per_page=100&page=2>; rel="last"
        case Regex.run(~r/<([^>]+)>; rel="next"/, link, capture: :all_but_first) do
          nil ->
            body = Map.fetch!(response, :body)
            {:ok, body}

          [next_url] ->
            {:ok, next_json} = get!(next_url)
            body = Map.fetch!(response, :body)
            {:ok, List.wrap(body) ++ next_json}
        end
    end
  end
end
