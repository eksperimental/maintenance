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
  Returns the lowercase hexadecimal sha256 of a string.
  """
  @spec hash(String.t()) :: String.t()
  def hash(string) when is_binary(string) do
    encrypted = :crypto.hash(:sha256, string)

    encrypted
    |> Base.encode16()
    |> String.downcase()
  end

  @doc """
  Returns a unique branch name
  """
  @spec unique_branch_name(String.t()) :: String.t()
  def unique_branch_name(base_name) when is_binary(base_name) do
    unix_time =
      "Etc/UTC"
      |> DateTime.now!()
      |> DateTime.to_unix()

    unique_integer = System.unique_integer([:positive, :monotonic])

    base_name <> "_#{unix_time}_#{unique_integer}"
  end

  @doc """
  Logs `message` with info level.
  """
  @spec info(message) :: message when message: String.t()
  def info(message) when is_binary(message) do
    Logger.info(message)

    message
  end

  # Converts they keys of an enumerable to existing atoms.
  @doc false
  @spec convert_keys_to_existing_atoms(any()) :: any()
  def convert_keys_to_existing_atoms(term) when is_list(term) or is_map(term) do
    into = into(term)

    result =
      Enum.reduce(term, into, fn
        {k, v}, acc ->
          into(acc, {String.to_existing_atom(k), convert_keys_to_existing_atoms(v)})

        elem, acc ->
          into(acc, convert_keys_to_existing_atoms(elem))
      end)

    if into == [] do
      :lists.reverse(result)
    else
      result
    end
  end

  def convert_keys_to_existing_atoms(term) do
    term
  end

  @doc false
  @spec into(map()) :: %{}
  @spec into(keyword()) :: []
  @spec into(keyword(), {Keyword.key(), Keyword.value()}) :: keyword()
  def into(term) when is_map(term), do: %{}
  def into(term) when is_list(term), do: []

  @doc false
  @spec into(map(), {Map.key(), Map.value()}) :: map()
  @spec into(keyword(), {Keyword.key(), Keyword.value()}) :: keyword()
  def into(acc, {k, v}) when is_map(acc), do: Map.put(acc, k, v)
  def into(acc, elem) when is_list(acc), do: [elem | acc]

  @spec pmap(Enum.t(), (Enum.element() -> Enum.element())) :: any()
  def pmap(collection, func) do
    collection
    |> Enum.map(&Task.async(fn -> func.(&1) end))
    |> Task.await_many()
  end
end
