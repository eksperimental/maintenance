defmodule MaintenanceTest do
  use ExUnit.Case, async: false

  describe "github_access_token!/0" do
    setup do
      previous = System.get_env("GITHUB_ACCESS_TOKEN")
      on_exit(fn -> System.put_env("GITHUB_ACCESS_TOKEN", previous) end)
    end

    test "returns the token from the environment" do
      System.put_env("GITHUB_ACCESS_TOKEN", "secret")

      assert Maintenance.github_access_token!() == "secret"
    end

    test "tells how to set the token when it is missing" do
      System.delete_env("GITHUB_ACCESS_TOKEN")

      assert_raise RuntimeError, ~r/\.env.*source \.env/, &Maintenance.github_access_token!/0
    end
  end
end
