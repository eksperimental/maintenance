defmodule Maintenance.Entries do
  @moduledoc """
  The Entries context.
  """

  import Ecto.Query, warn: false
  alias Maintenance.Repo

  alias Maintenance.Entries.Entry

  @doc """
  Returns the list of entries.

  ## Examples

      iex> list_entries()
      [%Entry{}, ...]

  """
  def list_entries do
    result =
      Entry
      |> order_by(desc: :date_time, desc: :id)
      |> Repo.all()
      |> Repo.preload(:client)

    # IO.inspect(result)
    result
  end

  @doc """
  Gets a single entry.

  Raises `Ecto.NoResultsError` if the Entry does not exist.

  ## Examples

      iex> get_entry!(123)
      %Entry{}

      iex> get_entry!(456)
      ** (Ecto.NoResultsError)

  """
  def get_entry!(id) do
    # query =
    #   from e in Entry,
    #     join: c in Client,
    #     as: :clients,
    #     on: e.client_id == c.id,
    #     # where:([c], e.id = ^id),
    #     select: {e.id, e.date_time, e.uptime, e.remote_ip, c.name}

    # # result = Repo.get!(query, id)
    # result = Repo.all(query, id)

    # entry = Repo.get!(Entry, id)

    # data =
    #   Entry
    #   |> join(:left, [e], c in Client, as: :clients, on: e.client_id == c.id)
    #   |> where([e], e.id == ^id)
    #   # |> select([e, clients: c], %{
    #   #   id: e.id,
    #   #   date_time: e.date_time,
    #   #   uptime: e.uptime,
    #   #   remote_ip: e.remote_ip,
    #   #   client_name: c.name
    #   # })
    #   # |> select([e, clients: c], c.name)
    #   # |> Repo.all()
    #   # |> Repo.get!(id)
    #   |> Repo.one()

    # IO.inspect(data)
    # # |> Repo.preload(:client)

    # %{entry: entry, data: data}

    Entry
    |> Repo.get!(id)
    |> Repo.preload(:client)
  end

  @doc """
  Creates a entry.

  ## Examples

      iex> create_entry(%{field: value})
      {:ok, %Entry{}}

      iex> create_entry(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_entry(attrs \\ %{}) do
    x =
      %Entry{}
      |> Entry.changeset(attrs)

    IO.inspect(x)

    x
    |> Repo.insert()
  end

  @doc """
  Updates a entry.

  ## Examples

      iex> update_entry(entry, %{field: new_value})
      {:ok, %Entry{}}

      iex> update_entry(entry, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_entry(%Entry{} = entry, attrs) do
    entry
    |> Entry.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a entry.

  ## Examples

      iex> delete_entry(entry)
      {:ok, %Entry{}}

      iex> delete_entry(entry)
      {:error, %Ecto.Changeset{}}

  """
  def delete_entry(%Entry{} = entry) do
    Repo.delete(entry)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking entry changes.

  ## Examples

      iex> change_entry(entry)
      %Ecto.Changeset{data: %Entry{}}

  """
  def change_entry(%Entry{} = entry, attrs \\ %{}) do
    Entry.changeset(entry, attrs)
  end
end
