defmodule Maintenance.DB do
  @moduledoc """
  Module that deals with the local Database.

  Currently we use CubDB.
  """

  use GenServer

  import Maintenance, only: [is_project: 1]

  @type state :: %{project => pid()}
  @type key :: term
  @type value :: term
  @type project :: Maintenance.project()
  @type order :: :asc | :desc

  # defguardp is_order(term) when term in [:asc, :desc]

  @spec start_link(term) :: GenServer.on_start()
  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @spec get(project, key, value) :: value
  def get(project, key, default \\ nil) when is_project(project) do
    GenServer.call(__MODULE__, {:get, project, key, default})
  end

  @spec select(project, keyword) :: value
  def select(project, options \\ []) when is_project(project) do
    GenServer.call(__MODULE__, {:select, project, options})
  end

  @spec fetch(project, key) :: {:ok, value} | :error
  def fetch(project, key) when is_project(project) do
    GenServer.call(__MODULE__, {:fetch, project, key})
  end

  @spec put(project, key, value) :: value
  def put(project, key, value) when is_project(project) do
    GenServer.call(__MODULE__, {:put, project, key, value})
  end

  @spec delete(project, key) :: :ok
  def delete(project, key) when is_project(project) do
    GenServer.call(__MODULE__, {:delete, project, key})
  end

  # @spec sort(map, order) :: :ok
  # def sort(map, order) when is_map(map) and is_order(order) do
  #   Enum.sort_by(map, &(&1.__sort__), order)
  # end

  ## Callbacks

  @impl GenServer
  @spec init(term) :: {:ok, state()} | {:stop, reason :: any()}
  def init(_options) do
    projects = Maintenance.projects()

    result =
      Enum.reduce_while(projects, %{}, fn project, acc ->
        case CubDB.start_link(data_dir: Maintenance.db_path(project)) do
          {:ok, db} ->
            {:cont, Map.put(acc, project, db)}

          {:error, reason} ->
            {:halt, {:stop, reason}}
        end
      end)

    case result do
      {:stop, reason} ->
        {:stop, reason}

      _other ->
        {:ok, result}
    end
  end

  @impl GenServer
  @spec handle_call(term, GenServer.from(), state) :: {:reply, term(), state}
  def handle_call({:get, project, key, default}, _from, state) do
    value =
      state
      |> Map.get(project)
      |> CubDB.get(key, default)

    {:reply, value, state}
  end

  def handle_call({:select, project, options}, _from, state) do
    value =
      state
      |> Map.get(project)
      |> CubDB.select(options)

    {:reply, value, state}
  end

  def handle_call({:fetch, project, key}, _from, state) do
    reply =
      state
      |> Map.get(project)
      |> CubDB.fetch(key)

    {:reply, reply, state}
  end

  def handle_call({:put, project, key, value}, _from, state) do
    reply =
      state
      |> Map.get(project)
      |> CubDB.put(key, value)

    {:reply, reply, state}
  end

  def handle_call({:delete, project, key}, _from, state) do
    reply =
      state
      |> Map.get(project)
      |> CubDB.delete(key)

    {:reply, reply, state}
  end

  # @impl GenServer
  # def handle_cast({:push, head}, tail) do
  #   {:noreply, [head | tail]}
  # end
end
