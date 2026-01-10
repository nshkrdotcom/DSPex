defmodule DSPex.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/nshkrdotcom/dspex"

  def project do
    [
      app: :dspex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      python_deps: python_deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      # Add snakebridge compiler for Python introspection and auto-install
      compilers: [:snakebridge] ++ Mix.compilers(),

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],

      # Package info
      name: "DSPex",
      description: "DSPy for Elixir via SnakeBridge - Declarative LLM programming",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # SnakeBridge - Python bridge for DSPy (local path for development)
      {:snakebridge, path: "../snakebridge"},

      # JSON encoding
      {:jason, "~> 1.4"},

      # Dev/test tools
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp python_deps do
    [
      # generate: :all enables full API surface generation
      {:dspy, "2.6.5", generate: :all, submodules: true}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "readme",
      name: "DSPex",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      assets: %{"assets" => "assets"},
      logo: "assets/DSPex.svg",
      extras: [
        "README.md",
        {"examples/README.md", filename: "examples"},
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_modules: [
        "Core API": [DSPex]
      ]
    ]
  end

  defp package do
    [
      name: "dspex",
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE assets examples),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/dspex",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["nshkrdotcom"]
    ]
  end
end
