# Source: https://gist.github.com/sushant12/38c8e01ab7a3673ca45abe82d1ffe3c0
# The bash command `history | grep abc` is a neat tool. I abuse it alot. 
# So, I wrote a module that would list or search through iex history.

# I prefer to put this module in my .iex.exs file and then import the .iex.exs file into my project.

defmodule History do
  def search(term) do
    load_history()
    |> Stream.filter(&String.match?(&1, ~r/#{term}/))
    |> Enum.reverse()
    |> Stream.with_index(1)
    |> Enum.each(fn {value, index} ->
      IO.write("#{index}  ")
      IO.write(String.replace(value, term, "#{IO.ANSI.red()}#{term}#{IO.ANSI.default_color()}"))
    end)
  end

  def search do
    load_history()
    |> Enum.reverse()
    |> Stream.with_index(1)
    |> Enum.each(fn {value, index} ->
      IO.write("#{index}  #{value}")
    end)
  end

  defp load_history, do: :group_history.load() |> Stream.map(&List.to_string/1)
end
