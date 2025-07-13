defmodule AshDSPex.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_dspex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      aliases: aliases(),
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
      extra_applications: [:logger],
      mod: {AshDSPex.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

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
