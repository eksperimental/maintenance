defmodule MaintenanceJob.UnicodeTest do
  use ExUnit.Case, async: false

  alias MaintenanceJob.Unicode

  describe "get!/2" do
    setup do
      on_exit(fn -> await_cache_writes() end)
    end

    test "unzips the downloaded Unicode data into a map of file contents" do
      version = Version.parse!("0.0.1")

      {:ok, {_name, zip}} =
        :zip.create(
          ~c"uts39-data-0.0.1.zip",
          [
            {~c"confusables.txt", "confusables\n"},
            {~c"IdentifierType.txt", "identifier types\n"}
          ],
          [:memory]
        )

      Req.Test.stub(Unicode, fn conn ->
        assert conn.host == "www.unicode.org"
        assert conn.request_path == "/Public/0.0.1/security/uts39-data-0.0.1.zip"

        conn
        |> Plug.Conn.put_resp_content_type("application/zip", nil)
        |> Plug.Conn.send_resp(200, zip)
      end)

      assert Unicode.get!(:UTS39, version) ==
               {:ok,
                %{
                  "confusables.txt" => "confusables\n",
                  "IdentifierType.txt" => "identifier types\n"
                }}
    end
  end

  describe "update_vendor_info/2" do
    test "points the OTP vendor info at the new Unicode version" do
      vendor_info = """
      [
        {
          "ID": "stdlib-unicode",
          "downloadLocation": "https://www.unicode.org/Public/16.0.0/ucd/",
          "homepage": "https://www.unicode.org/",
          "versionInfo": "16.0.0",
          "path": ["./lib/stdlib/uc_spec/CaseFolding.txt"]
        }
      ]
      """

      assert Unicode.update_vendor_info(vendor_info, Version.parse!("17.0.0")) == """
             [
               {
                 "ID": "stdlib-unicode",
                 "downloadLocation": "https://www.unicode.org/Public/17.0.0/ucd/",
                 "homepage": "https://www.unicode.org/",
                 "versionInfo": "17.0.0",
                 "path": ["./lib/stdlib/uc_spec/CaseFolding.txt"]
               }
             ]
             """
    end
  end

  # get!/2 writes the download to the cache in a background task.
  defp await_cache_writes() do
    for pid <- Task.Supervisor.children(Maintenance.TaskSupervisor) do
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      end
    end

    [Maintenance.cache_path(), "UTS39", "0.0.1"]
    |> Path.join()
    |> File.rm_rf!()
  end
end
