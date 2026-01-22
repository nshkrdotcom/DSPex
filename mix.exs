defmodule DSPex.MixProject do
  use Mix.Project

  @version "0.7.0"
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
      # SnakeBridge - Python bridge
      {:snakebridge, "~> 0.13.0"},

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
      {:dspy, "3.1.2", generate: :all, submodules: true}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    dspy_groups = snakebridge_groups()
    dspy_nests = snakebridge_nests()

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
        {"guides/flagship_multi_pool_gepa.md", filename: "flagship-multi-pool-gepa"},
        {"guides/flagship_multi_pool_rlm.md", filename: "flagship-multi-pool-rlm"},
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_modules: [{"Core API", [DSPex]}] ++ dspy_groups,
      nest_modules_by_prefix: dspy_nests
    ]
  end

  defp snakebridge_groups do
    if Code.ensure_loaded?(SnakeBridge.Docs) and
         function_exported?(SnakeBridge.Docs, :groups_for_modules, 1) do
      SnakeBridge.Docs.groups_for_modules(libraries: ["dspy"])
    else
      []
    end
  end

  defp snakebridge_nests do
    if Code.ensure_loaded?(SnakeBridge.Docs) and
         function_exported?(SnakeBridge.Docs, :nest_modules_by_prefix, 1) do
      SnakeBridge.Docs.nest_modules_by_prefix(libraries: ["dspy"])
    else
      []
    end
  end

  defp package do
    [
      name: "dspex",
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["nshkrdotcom"]
    ]
  end
end
