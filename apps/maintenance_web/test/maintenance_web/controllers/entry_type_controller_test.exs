defmodule MaintenanceWeb.JobControllerTest do
  use MaintenanceWeb.ConnCase

  import Maintenance.EntriesFixtures

  @create_attrs %{}
  @update_attrs %{}
  @invalid_attrs %{}

  describe "index" do
    test "lists all entry_type", %{conn: conn} do
      conn = get(conn, Routes.entry_type_path(conn, :index))
      assert html_response(conn, 200) =~ "Listing Job"
    end
  end

  describe "new entry_type" do
    test "renders form", %{conn: conn} do
      conn = get(conn, Routes.entry_type_path(conn, :new))
      assert html_response(conn, 200) =~ "New Job"
    end
  end

  describe "create entry_type" do
    test "redirects to show when data is valid", %{conn: conn} do
      conn = post(conn, Routes.entry_type_path(conn, :create), entry_type: @create_attrs)

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == Routes.entry_type_path(conn, :show, id)

      conn = get(conn, Routes.entry_type_path(conn, :show, id))
      assert html_response(conn, 200) =~ "Show Job"
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, Routes.entry_type_path(conn, :create), entry_type: @invalid_attrs)
      assert html_response(conn, 200) =~ "New Job"
    end
  end

  describe "edit entry_type" do
    setup [:create_entry_type]

    test "renders form for editing chosen entry_type", %{conn: conn, entry_type: entry_type} do
      conn = get(conn, Routes.entry_type_path(conn, :edit, entry_type))
      assert html_response(conn, 200) =~ "Edit Job"
    end
  end

  describe "update entry_type" do
    setup [:create_entry_type]

    test "redirects when data is valid", %{conn: conn, entry_type: entry_type} do
      conn = put(conn, Routes.entry_type_path(conn, :update, entry_type), entry_type: @update_attrs)
      assert redirected_to(conn) == Routes.entry_type_path(conn, :show, entry_type)

      conn = get(conn, Routes.entry_type_path(conn, :show, entry_type))
      assert html_response(conn, 200)
    end

    test "renders errors when data is invalid", %{conn: conn, entry_type: entry_type} do
      conn = put(conn, Routes.entry_type_path(conn, :update, entry_type), entry_type: @invalid_attrs)
      assert html_response(conn, 200) =~ "Edit Job"
    end
  end

  describe "delete entry_type" do
    setup [:create_entry_type]

    test "deletes chosen entry_type", %{conn: conn, entry_type: entry_type} do
      conn = delete(conn, Routes.entry_type_path(conn, :delete, entry_type))
      assert redirected_to(conn) == Routes.entry_type_path(conn, :index)

      assert_error_sent 404, fn ->
        get(conn, Routes.entry_type_path(conn, :show, entry_type))
      end
    end
  end

  defp create_entry_type(_) do
    entry_type = entry_type_fixture()
    %{entry_type: entry_type}
  end
end
