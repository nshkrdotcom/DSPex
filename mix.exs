defmodule DSPex.MixProject do
  use Mix.Project

  def project do
    [
      app: :dspex,
      version: "0.1.0",
      elixir: "~> 1.18",
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
      ]
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
      {:snakepit, github: "nshkrdotcom/snakepit"},
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
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
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
end
