defmodule DSPex.MixProject do
  use Mix.Project

  def project do
    [
      app: :dspex,
      version: "0.2.0",
      elixir: "~> 1.18",
      erlang: "~> 27.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: [
        check: :test,
        "check.ci": :test,
        "test.fast": :test,
        "test.protocol": :test,
        "test.integration": :test,
        "test.all": :test
      ],
      # Hex package configuration
      description: description(),
      package: package(),
      docs: docs(),
      name: "DSPex",
      source_url: "https://github.com/nshkrdotcom/dspex"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto, :eex],
      mod: {DSPex.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Core dependencies
      {:snakepit, "~> 0.4.1"},
      #      {:snakepit,
      #       git: "https://github.com/nshkrdotcom/snakepit.git",
      #       branch: "feature/unified-grpc-bridge-stage2"},
      #      {:snakepit, path: "./snakepit"},
      {:snakepit_grpc_bridge, path: "./snakepit_grpc_bridge"},
      {:sinter, "~> 0.0.1"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:telemetry_poller, "~> 1.0"},

      # LLM adapters
      {:instructor_lite, "~> 1.0"},
      {:gemini_ex, "~> 0.0.3"},
      {:req, "~> 0.5 or ~> 1.0"},

      # Development dependencies
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:meck, "~> 0.9", only: :test}
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit],
      flags: [
        :error_handling,
        :extra_return,
        :missing_return,
        :underspecs,
        :unknown,
        :unmatched_returns
      ],
      ignore_warnings: ".dialyzer_ignore.exs",
      list_unused_filters: true
    ]
  end

  defp aliases do
    [
      check: ["test", "dialyzer"],
      "check.ci": ["deps.unlock --check-unused", "format --check-formatted", "test", "dialyzer"],

      # Test mode aliases for 3-layer testing architecture
      "test.fast": &test_fast/1,
      "test.protocol": &test_protocol/1,
      "test.integration": &test_integration/1,
      "test.all": &test_all_layers/1
    ]
  end

  # Layer 1: Fast unit tests with mock adapter (~70ms)
  defp test_fast(args) do
    System.put_env("TEST_MODE", "mock_adapter")
    Mix.Task.run("test", args)
  end

  # Layer 2: Protocol testing without full Python bridge
  defp test_protocol(args) do
    System.put_env("TEST_MODE", "bridge_mock")
    Mix.Task.run("test", args)
  end

  # Layer 3: Full integration tests with Python bridge
  defp test_integration(args) do
    System.put_env("TEST_MODE", "full_integration")
    Mix.Task.run("test", args)
  end

  # Run all test layers sequentially  
  defp test_all_layers(_) do
    IO.puts("🧪 Running Layer 1 (Fast Unit Tests)...")
    System.put_env("TEST_MODE", "mock_adapter")

    case Mix.Task.run("test", []) do
      :ok -> IO.puts("✅ Layer 1 passed")
      _ -> IO.puts("❌ Layer 1 failed")
    end

    IO.puts("🧪 Running Layer 2 (Protocol Tests)...")
    System.put_env("TEST_MODE", "bridge_mock")

    case Mix.Task.run("test", []) do
      :ok -> IO.puts("✅ Layer 2 passed")
      _ -> IO.puts("❌ Layer 2 failed")
    end

    IO.puts("🧪 Running Layer 3 (Integration Tests)...")
    System.put_env("TEST_MODE", "full_integration")

    case Mix.Task.run("test", []) do
      :ok -> IO.puts("✅ Layer 3 passed")
      _ -> IO.puts("❌ Layer 3 failed")
    end

    IO.puts("✅ All test layers completed!")
  end

  defp description do
    "DSPex: Native Elixir implementation of DSPy with Python integration via Snakepit. Enables gradual migration from Python DSPy to native Elixir implementations while supporting mixed execution pipelines."
  end

  defp package do
    [
      name: "dspex",
      maintainers: ["NSHkr <ZeroTrust@NSHkr.com>"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/nshkrdotcom/dspex",
        "Documentation" => "https://hexdocs.pm/dspex"
      },
      files: ~w(lib priv/python/*.py .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "DSPex",
      assets: %{"assets" => "assets"},
      logo: "assets/dspex-logo.svg",
      extras: [
        "README.md",
        "README_DSPY_INTEGRATION.md",
        "CHANGELOG.md"
      ],
      groups_for_modules: [
        "Core API": [
          DSPex,
          DSPex.Router,
          DSPex.Pipeline
        ],
        "Native Implementations": [
          DSPex.Native.Signature,
          DSPex.Native.Template,
          DSPex.Native.Validator,
          DSPex.Native.Metrics
        ],
        "Python Bridge": [
          DSPex.Python.Bridge
        ]
      ],
      before_closing_head_tag: &docs_before_closing_head_tag/1,
      before_closing_body_tag: &docs_before_closing_body_tag/1
    ]
  end

  defp docs_before_closing_head_tag(:html) do
    """
    <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
    """
  end

  defp docs_before_closing_head_tag(_), do: ""

  defp docs_before_closing_body_tag(:html) do
    """
    <script>
      document.addEventListener("DOMContentLoaded", function () {
        mermaid.initialize({
          startOnLoad: true,
          theme: document.body.className.includes("dark") ? "dark" : "default",
          themeVariables: {
            primaryColor: "#6366f1",
            primaryTextColor: "#fff",
            primaryBorderColor: "#4f46e5",
            lineColor: "#6b7280",
            sectionBkgColor: "#f3f4f6",
            altSectionBkgColor: "#ffffff",
            gridColor: "#e5e7eb",
            secondaryColor: "#e0e7ff",
            tertiaryColor: "#f1f5f9"
          }
        });
      });
    </script>
    """
  end

  defp docs_before_closing_body_tag(_), do: ""
end
