defmodule Maintenance.EnvHelpers do
  @moduledoc false

  @doc """
  Sets the variable `name` to `value`, or deletes it for nil, until the test ends.
  """
  @spec put_env(String.t(), String.t() | nil) :: :ok
  def put_env(name, value) do
    previous = System.get_env(name)
    ExUnit.Callbacks.on_exit(fn -> restore_env(name, previous) end)
    restore_env(name, value)
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
