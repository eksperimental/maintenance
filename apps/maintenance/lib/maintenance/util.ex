defmodule Maintenance.Util do
  @moduledoc """
  Convenience functions.
  """

  require Logger

  @doc """
  Outputs term including the line number.
  """
  defmacro debug(term, options \\ [print_file?: true]) do
    quote bind_quoted: [
            term: term,
            line: __CALLER__.line,
            file: __CALLER__.file,
            options: options
          ] do
      output =
        if options[:print_file?] do
          {"#{file}:#{line}", term}
        else
          {line, term}
        end

      output
      |> inspect(limit: :infinity, printable_limit: :infinity)
      |> Logger.debug()

      term
    end
  end

  @doc """
  Logs `message` with info level.
  """
  @spec info(message) :: message when message: String.t()
  def info(message) when is_binary(message) do
    Logger.info(message)

    message
  end
end
