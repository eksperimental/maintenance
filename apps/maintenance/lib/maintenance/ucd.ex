defmodule Maintenance.UCD do
  @moduledoc """
  Module that deals with the Unicode Character Database.
  """

  import Maintenance, only: [default: 2, is_project: 1]

  @type version :: %Version{}
  @type response :: %Finch.Response{}
  @type response_status :: pos_integer()
  @type contents :: %{required(file_name :: String.t()) => file_contents :: String.t()}

  defguard is_version(term) when is_struct(term, Version)

  @doc """
  Converts `string` to `%Version{}` struct.
  """
  @spec to_version(String.t()) :: version
  def to_version(string) when is_binary(string) do
    Version.parse!(string)
  end

  @doc """
  Converts `string` to `%Version{}` struct.
  """
  @spec to_tuple(version) :: {Version.major(), Version.minor(), Version.patch()}
  def to_tuple(%Version{major: major, minor: minor, patch: patch}) do
    {major, minor, patch}
  end

  @doc """
  Returns the latest Unicode version available.
  """
  @spec get_latest_unicode_version() :: {:ok, %Version{}} | :error
  def get_latest_unicode_version() do
    result =
      "https://www.unicode.org/Public/UCD/latest/ReadMe.txt"
      |> Req.get!()
      |> then(
        &Regex.named_captures(
          ~r{https://www.unicode.org/Public/zipped/(?<version>\d+\.\d+.\d+)/},
          &1.body
        )
      )

    case result do
      nil -> :error
      %{"version" => version} -> {:ok, to_version(version)}
    end
  end

  @doc """
  Get the UCD zipped file.

  If it has been previously retrieved, it will be obtained from the cache.
  """
  @spec get_ucd(version) :: {:ok, contents} | {:error, Mint.Types.status()}
  def get_ucd(version) when is_version(version) do
    response = Req.get!("https://www.unicode.org/Public/zipped/#{version}/UCD.zip")

    case response.status do
      200 ->
        body = Map.new(response.body, fn {k, v} -> {List.to_string(k), v} end)

        Task.Supervisor.start_child(Maintenance.TaskSupervisor, fn ->
          write(version, body)
        end)

        {:ok, body}

      _ ->
        {:error, response.status}
    end
  end

  @doc """
  Gets the latest UCD zipped file.
  """
  @spec get_latest_ucd() ::
          {:ok, contents}
          | {:error, response_status}
  def get_latest_ucd() do
    {:ok, latest_version} = get_latest_unicode_version()

    case read(latest_version) do
      {:ok, contents} ->
        {:ok, contents}

      {:error, _} ->
        case get_ucd(latest_version) do
          {:ok, contents} ->
            {:ok, contents}

          {:error, error_status} ->
            {:error, error_status}
        end
    end
  end

  @doc """
  Gets the current Unicode version for the given `project`.
  """
  @spec get_current_unicode_version(Maintenance.project()) :: {:ok, version} | :error
  def get_current_unicode_version(:elixir) do
    result =
      "https://raw.githubusercontent.com/elixir-lang/elixir/master/lib/elixir/unicode/unicode.ex"
      |> Req.get!()
      |> then(&Regex.named_captures(~r/def version, do: {(?<version>\d+, \d+, \d+)}/, &1.body))

    case result do
      %{"version" => version_string} ->
        version =
          String.split(version_string, ",")
          |> Enum.map(&String.trim/1)
          |> Enum.join(".")
          |> to_version()

        # {:ok, to_version("13.0.0")}
        {:ok, version}

      nil ->
        :error
    end
  end

  def get_current_unicode_version(:otp) do
    result =
      Req.get!(
        "https://raw.githubusercontent.com/erlang/otp/master/lib/stdlib/uc_spec/gen_unicode_mod.escript"
      )
      |> then(&Regex.named_captures(default(:otp, :regex_gen_unicode_version), &1.body))

    case result do
      %{"major" => major, "minor" => minor, "patch" => ""} ->
        version = Enum.join([major, minor, 0], ".") |> to_version()
        {:ok, version}

      %{"major" => major, "minor" => minor, "patch" => patch} ->
        version = Enum.join([major, minor, patch], ".") |> to_version()
        {:ok, version}

      nil ->
        :error
    end
  end

  #############################
  # Cache

  @doc """
  Return the path of the UCD file for the given `version`·
  """
  @spec ucd_path(version()) :: Path.t()
  def ucd_path(version) when is_version(version) do
    Path.join(ucd_path(), to_string(version))
  end

  defp ucd_path() do
    Maintenance.cache_path() |> Path.join("UCD")
  end

  @doc """
  Writes the UCD file in Erlang terms contents.
  """
  @spec write(version(), contents()) :: :ok
  def write(version, contents) when is_version(version) do
    dir = ucd_path(version)
    tmp_dir = Path.join([dir, Integer.to_string(System.monotonic_time(:nanosecond))])
    File.mkdir_p!(tmp_dir)

    tmp_path = Path.join([tmp_dir, "UCD.bin"])
    File.write!(tmp_path, :erlang.term_to_binary(contents))

    path = Path.join([dir, "UCD.bin"])
    File.rename!(tmp_path, path)
    File.rmdir(tmp_dir)
  end

  @doc """
  Reads the UCD file cached by the give `version`.
  """
  @spec read(version()) :: {:ok, contents()} | {:error, File.posix()}
  def read(version) when is_version(version) do
    dir = ucd_path(version)

    case File.read(Path.join(dir, "UCD.bin")) do
      {:ok, binary} ->
        {:ok, :erlang.binary_to_term(binary)}

      {:error, _} = error ->
        error
    end
  end

  @spec calculate_update(Maintenance.project()) :: %{
          needs_update?: boolean,
          current_unicode_version: version,
          latest_unicode_version: version
        }
  def calculate_update(project) when is_project(project) do
    {:ok, current_unicode_version} = get_current_unicode_version(project)
    {:ok, latest_unicode_version} = get_latest_unicode_version()

    %{
      needs_update?: Version.compare(latest_unicode_version, current_unicode_version) == :gt,
      current_unicode_version: current_unicode_version,
      latest_unicode_version: latest_unicode_version
    }
  end
end
