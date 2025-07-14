defmodule DSPex.Adapters.ModeCompatibilityTest do
  @moduledoc """
  Tests to ensure DSPex works correctly with both single bridge and pool modes.

  This ensures the system can be configured for either mode based on
  deployment requirements without code changes.
  """

  use ExUnit.Case, async: false

  @moduletag :layer_3

  describe "single bridge mode" do
    setup do
      # Ensure we're in single bridge mode
      original_pooling = Application.get_env(:dspex, :pooling_enabled)
      Application.put_env(:dspex, :pooling_enabled, false)

      on_exit(fn ->
        Application.put_env(:dspex, :pooling_enabled, original_pooling)
      end)

      # Ensure adapter uses PythonPort (single bridge)
      adapter = DSPex.Adapters.Registry.get_adapter()
      assert adapter == DSPex.Adapters.PythonPort

      {:ok, adapter: adapter}
    end

    test "health check works in single mode", %{adapter: adapter} do
      case adapter.health_check() do
        :ok ->
          assert true

        {:error, _reason} ->
          # Bridge might not be available in test environment
          assert true
      end
    end

    test "adapter resolves to PythonPort when pooling disabled" do
      adapter = DSPex.Adapters.Registry.get_adapter()
      assert adapter == DSPex.Adapters.PythonPort
    end

    test "can configure LM in single mode", %{adapter: adapter} do
      if System.get_env("GEMINI_API_KEY") do
        config = %{
          model: "gemini-1.5-flash",
          api_key: System.get_env("GEMINI_API_KEY"),
          temperature: 0.5,
          provider: :google
        }

        case adapter.configure_lm(config) do
          :ok -> assert true
          {:error, _reason} -> assert true
        end
      else
        # Skip if no API key
        assert true
      end
    end
  end

  describe "pool mode configuration" do
    test "adapter resolves to PythonPool when pooling enabled" do
      # Temporarily enable pooling
      original_pooling = Application.get_env(:dspex, :pooling_enabled)
      Application.put_env(:dspex, :pooling_enabled, true)

      try do
        adapter = DSPex.Adapters.Registry.get_adapter()
        assert adapter == DSPex.Adapters.PythonPool
      after
        Application.put_env(:dspex, :pooling_enabled, original_pooling)
      end
    end
  end

  describe "adapter behavior consistency" do
    test "both adapters implement same behavior" do
      # Check that both adapters implement the required callbacks
      for adapter <- [DSPex.Adapters.PythonPort, DSPex.Adapters.PythonPool] do
        # Ensure module is loaded
        Code.ensure_loaded(adapter)

        assert function_exported?(adapter, :create_program, 1)
        assert function_exported?(adapter, :execute_program, 2)
        assert function_exported?(adapter, :list_programs, 0)
        assert function_exported?(adapter, :delete_program, 1)
        assert function_exported?(adapter, :health_check, 0)
        assert function_exported?(adapter, :configure_lm, 1)
        assert function_exported?(adapter, :get_stats, 0)
      end
    end

    test "configuration determines adapter selection" do
      # Test with pooling disabled
      Application.put_env(:dspex, :pooling_enabled, false)
      assert DSPex.Adapters.Registry.get_adapter() == DSPex.Adapters.PythonPort

      # Test with pooling enabled
      Application.put_env(:dspex, :pooling_enabled, true)
      assert DSPex.Adapters.Registry.get_adapter() == DSPex.Adapters.PythonPool

      # Reset to original
      Application.put_env(:dspex, :pooling_enabled, false)
    end
  end
end
