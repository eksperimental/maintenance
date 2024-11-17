defmodule Maintenance.Umbrella.MixProject do
  use Mix.Project

  # @app :maintenance
  @name "Maintenance"
  @repo_url "https://github.com/eksperimental/maintenance"
  @description """
  Maintenance BEAM project is an app which aims to automatize tasks in codebases of the Elixir,
  Erlang, or any other project using a Git repository (only GitHub is initially supported).
  """

  def project do
    [
      apps_path: "apps",
      version: version(),
      start_permanent: Mix.env() == :prod,
      description: @description,
      deps: deps(),
      aliases: aliases(),
      releases: releases(),

      # Docs
      name: @name,
      source_url: @repo_url,
      homepage_url: @repo_url,
      docs: docs()
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
    ]
  end

  defp aliases do
    [
      validate: [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "compile",
        "compile --warnings-as-errors",
        "dialyzer",
        "docs",
        "credo --ignore Credo.Check.Design.TagTODO"
      ],
      prepare: [
        "format",
        "deps.clean --unused --unlock",
        "deps.unlock --unsued"
      ],
      setup: [
        "deps.get",
        "deps.update --all"
      ],
      all: [
        "setup",
        "prepare",
        "validate",
        test_isolated()
      ]
    ]
  end

  defp test_isolated() do
    fn _args ->
      env = %{"MIX_ENV" => "test"}

      with {:"test setup", {_, 0}} <- {:"test setup", System.cmd("mix", ~w[setup], env: env)},
           {:test, {_, 0}} <- {:test, System.cmd("mix", ~w[test], env: env)} do
        true
      else
        {type, {output, _}} ->
          IO.puts(output)
          raise("#{type} failed.")
      end
    end
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

  defp docs do
    [
      # The main page in the docs
      main: @name,
      ignore_apps: [:maintenance_web],
      authors: ["Eksperimental"],
      extras: [
        "README.md": [filename: "readme", title: "Readme"],
        NOTICE: [filename: "notice", title: "Notice"],
        "LICENSES/LICENSE.CC0-1.0.txt": [
          filename: "license_CC0-1.0",
          title: "Creative Commons Zero Universal version 1.0 License"
        ],
        "LICENSES/LICENSE.MIT-0.txt": [
          filename: "license_MIT-0",
          title: "MIT No Attribution License"
        ],
        "LICENSES/LICENSE.0BSD.txt": [
          filename: "license_0BSD",
          title: "BSD Zero Clause License"
        ]
      ],
      groups_for_extras: [
        Licenses: ~r{LICENSES/}
      ],
      source_ref: revision()
    ]
  end

  # Originally taken from: https://github.com/elixir-lang/elixir/blob/2b0abcebbe9acee4a103c9d02c6bae707f0e9e73/lib/elixir/lib/system.ex#L1019
  # Tries to run "git rev-parse --short=7 HEAD". In the case of success returns
  # the short revision hash. If that fails, returns an empty string.
  defp revision do
    null =
      case :os.type() do
        {:win32, _} -> ~c'NUL'
        _ -> ~c'/dev/null'
      end

    ~c'git rev-parse --short=7 HEAD 2> '
    |> Kernel.++(null)
    |> :os.cmd()
    |> strip
  end

  defp strip(iodata) do
    :re.replace(iodata, "^[\s\r\n\t]+|[\s\r\n\t]+$", "", [:global, return: :binary])
  end

  defp version() do
    "./VERSION"
    |> File.read!()
    |> String.trim()
  end
end
