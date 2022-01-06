defmodule Maintenance.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      name: "Maintenance.Umbrella project",
      apps_path: "apps",
      version: "0.1.2",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases()
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options.
  #
  # Dependencies listed here are available only for this project
  # and cannot be accessed from applications inside the apps/ folder.
  defp deps do
    [
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  #
  # Aliases listed here are available only for this project
  # and cannot be accessed from applications inside the apps/ folder.
  defp aliases do
    [
      # run `mix setup` in all child apps
      setup: ["cmd mix setup"],
      validate: [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "compile",
        "compile --warnings-as-errors",
        "dialyzer",
        "docs",
        "credo"
      ]
    ]
  end

  defp releases do
    [
      maintenance: [
        applications: [
          maintenance: :permanent,
          maintenance_web: :permanent
        ]
      ]
    ]
  end
end
