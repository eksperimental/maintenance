defmodule Maintenance.DB do
  @moduledoc """
  Module that deals with the local Database.

  Currently we use CubDB.
  """

  use GenServer

  @type state :: %{db: pid()}
  @type key :: term
  @type value :: term

  @spec start_link(term) :: GenServer.on_start()
  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @spec get(key, value) :: value
  def get(key, default \\ nil) do
    GenServer.call(__MODULE__, {:get, key, default})
  end

  @spec select(key) :: value
  def select(key) do
    GenServer.call(__MODULE__, {:select, key})
  end

  @spec fetch(key) :: {:ok, value} | :error
  def fetch(key) do
    GenServer.call(__MODULE__, {:fetch, key})
  end

  @spec put(key, value) :: value
  def put(key, value) do
    GenServer.call(__MODULE__, {:put, key, value})
  end

  @spec delete(key) :: :ok
  def delete(key) do
    GenServer.call(__MODULE__, {:delete, key})
  end

  ## Callbacks

  @impl true
  @spec init(term) :: {:ok, state()} | {:stop, reason :: any()}
  def init(_) do
    case CubDB.start_link(data_dir: Maintenance.db_path()) do
      {:ok, db} ->
        {:ok, %{db: db}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  @spec handle_call(term, GenServer.from(), state) :: {:reply, term(), state}
  def handle_call({:get, key, default}, _from, state) do
    value = CubDB.get(state.db, key, default)

    {:reply, value, state}
  end

  def handle_call({:select, options}, _from, state) do
    value = CubDB.select(state.db, options)

    {:reply, value, state}
  end

  @impl true
  def handle_call({:fetch, key}, _from, state) do
    reply = CubDB.fetch(state.db, key)

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    reply = CubDB.put(state.db, key, value)

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    reply = CubDB.delete(state.db, key)

    {:reply, reply, state}
  end

  # @impl true
  # def handle_cast({:push, head}, tail) do
  #   {:noreply, [head | tail]}
  # end  
end
