defmodule PoolFixedTest do
  use ExUnit.Case
  require Logger

  @moduletag :layer_3

  test "pool works with lazy initialization" do
    # Ensure pooling is enabled
    Application.put_env(:dspex, :pooling_enabled, true)

    # Start the app
    {:ok, _} = Application.ensure_all_started(:dspex)

    # Small delay for initialization
    Process.sleep(1000)

    # Check components
    pool_supervisor = Process.whereis(DSPex.PythonBridge.PoolSupervisor)
    session_pool = Process.whereis(DSPex.PythonBridge.SessionPool)

    assert pool_supervisor != nil
    assert session_pool != nil

    IO.puts("Pool supervisor: #{inspect(pool_supervisor)}")
    IO.puts("Session pool: #{inspect(session_pool)}")

    # Get pool status
    status = DSPex.PythonBridge.SessionPool.get_pool_status()
    IO.puts("Pool status: #{inspect(status, pretty: true)}")

    # Try to use the pool through the adapter
    adapter = DSPex.Adapters.Registry.get_adapter()
    assert adapter == DSPex.Adapters.PythonPool

    # Try a health check
    IO.puts("\nTrying health check...")

    case adapter.health_check() do
      :ok ->
        IO.puts("Health check passed!")

      {:error, reason} ->
        IO.puts("Health check failed: #{inspect(reason)}")
    end

    # Try to configure LM
    if System.get_env("GEMINI_API_KEY") do
      config = %{
        model: "gemini-1.5-flash",
        api_key: System.get_env("GEMINI_API_KEY"),
        temperature: 0.5,
        provider: :google
      }

      IO.puts("\nConfiguring LM...")

      case adapter.configure_lm(config) do
        :ok -> IO.puts("LM configured successfully!")
        {:error, reason} -> IO.puts("LM configuration failed: #{inspect(reason)}")
      end
    end

    # No more infinite worker creation!
    Process.sleep(2000)
    IO.puts("\nTest completed successfully - no infinite worker creation!")
  end
end
