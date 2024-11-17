defmodule Maintenance.MixProject do
  use Mix.Project

  def project do
    [
      app: :maintenance,
      version: version(),
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Maintenance.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix_pubsub, "~> 2.0"},
      {:swoosh, "~> 1.3"},
      {:req, "~> 0.5.0"},
      {:tentacat, "~> 2.0"},
      {:cubdb, "~> 1.1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:quantum, "~> 3.0"},
      {:beam_langs_meta_data,
       git: "https://github.com/eksperimental/beam_langs_meta_data/", branch: "main"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end

  defp version() do
    "../../VERSION"
    |> File.read!()
    |> String.trim()
  end
end
