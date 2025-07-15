#!/usr/bin/env elixir

# Test script to debug signature functionality
Application.put_env(:dspex, :pooling_enabled, true)

Mix.install([
  {:dspex, path: "../.."}
])

require Logger

defmodule SignatureDebugTest do
  def run do
    Logger.info("🔧 Testing signature system functionality...")
    
    # Test 1: Can we create a simple signature?
    test_signature_creation()
    
    # Test 2: Can we compile signatures?
    test_signature_compilation()
    
    # Test 3: Can we get an adapter?
    test_adapter_access()
    
    # Test 4: Can we check if pool is running?
    test_pool_status()
  end

  defp test_signature_creation do
    Logger.info("\n🔍 Test 1: Creating a basic signature...")
    
    signature = %{
      name: "TestSignature",
      description: "A test signature",
      inputs: [
        %{name: "text", type: "string", description: "Input text"}
      ],
      outputs: [
        %{name: "result", type: "string", description: "Output result"}
      ]
    }
    
    Logger.info("✅ Signature created: #{inspect(signature, pretty: true)}")
  end
  
  defp test_signature_compilation do
    Logger.info("\n🔍 Test 2: Testing signature compilation...")
    
    signature = %{
      name: "TestSignature",
      inputs: [%{name: "text", type: "string"}],
      outputs: [%{name: "result", type: "string"}]
    }
    
    try do
      # Try to use the signature compiler
      case DSPex.Signature.Compiler.compile(signature, []) do
        {:ok, result} ->
          Logger.info("✅ Signature compilation succeeded: #{inspect(result)}")
        {:error, reason} ->
          Logger.warning("⚠️ Signature compilation failed: #{inspect(reason)}")
      end
    rescue
      error ->
        Logger.warning("⚠️ Signature compilation error: #{inspect(error)}")
    end
  end
  
  defp test_adapter_access do
    Logger.info("\n🔍 Test 3: Testing adapter access...")
    
    try do
      adapter = DSPex.Adapters.Registry.get_adapter(:python_port)
      Logger.info("✅ Got adapter: #{inspect(adapter)}")
      
      # Try health check
      case adapter.health_check() do
        :ok ->
          Logger.info("✅ Adapter health check passed")
        {:error, reason} ->
          Logger.warning("⚠️ Adapter health check failed: #{inspect(reason)}")
      end
    rescue
      error ->
        Logger.warning("⚠️ Adapter access error: #{inspect(error)}")
    end
  end
  
  defp test_pool_status do
    Logger.info("\n🔍 Test 4: Testing pool status...")
    
    try do
      case DSPex.PythonBridge.SessionPoolV2.get_pool_status() do
        {:ok, status} ->
          Logger.info("✅ Pool status: #{inspect(status)}")
        {:error, reason} ->
          Logger.warning("⚠️ Pool status error: #{inspect(reason)}")
      end
    rescue
      error ->
        Logger.warning("⚠️ Pool status exception: #{inspect(error)}")
    end
  end
end

# Start the application
Application.ensure_all_started(:dspex)

# Run the test
SignatureDebugTest.run()

Logger.info("\n🎉 Signature debug test complete!")