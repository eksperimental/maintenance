defmodule Maintenance.GitHelpers do
  @moduledoc false

  @identity ~w(-c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false)

  @spec commit!(Path.t(), String.t()) :: String.t()
  def commit!(dir, message) do
    file = Path.join(dir, "file.txt")
    File.write!(file, message)
    git!(dir, ~w(add file.txt))
    git!(dir, @identity ++ ["commit", "--quiet", "-m", message])
    git!(dir, ~w(rev-parse HEAD))
  end

  @spec refs(Path.t()) :: %{String.t() => String.t()}
  def refs(repo) do
    repo
    |> git!(["for-each-ref", "--format=%(refname:short) %(objectname)"])
    |> String.split("\n", trim: true)
    |> Map.new(fn line ->
      [name, sha] = String.split(line, " ")
      {name, sha}
    end)
  end

  @spec git!(Path.t(), [String.t()]) :: String.t()
  def git!(dir, args) do
    {output, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
    String.trim(output)
  end
end
