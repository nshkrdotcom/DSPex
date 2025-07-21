#!/usr/bin/env elixir

defmodule SessionAffinityTest do
  def main do
    IO.puts "🧪 Testing Session Affinity Fix"
    IO.puts String.duplicate("=", 50)
    
    # Start everything
    Application.stop(:dspex)
    Application.put_env(:dspex, :pooling_enabled, true)
    Application.put_env(:dspex, :adapter, :python_pool)
    Application.ensure_all_started(:dspex)
    
    api_key = System.get_env("GEMINI_API_KEY")
    DSPex.set_lm("gemini-1.5-flash", api_key: api_key)
    
    IO.puts "✅ DSPex started with pooling"
    
    # Wait for pool initialization
    Process.sleep(2000)
    
    # Test session affinity
    test_session_affinity()
  end
  
  def test_session_affinity do
    IO.puts "\n🔍 Testing session affinity..."
    
    session_id = "test_session_#{System.unique_integer([:positive])}"
    
    signature = %{
      name: "QA",
      inputs: [%{name: "question", type: "string"}],
      outputs: [%{name: "answer", type: "string"}]
    }
    
    IO.puts "1. Creating program in session #{session_id}..."
    {:ok, program_id} = DSPex.create_program(%{
      signature: signature, 
      id: "test_prog",
      session_id: session_id
    })
    IO.puts "   ✅ Program created: #{program_id}"
    
    IO.puts "2. Executing program in same session..."
    result = DSPex.execute_program(program_id, %{question: "What is 2+2?"}, session_id: session_id)
    
    case result do
      {:ok, answer} ->
        IO.puts "   ✅ SUCCESS: #{inspect(answer)}"
        IO.puts "   🎉 Session affinity working!"
      {:error, error} ->
        IO.puts "   ❌ FAILED: #{inspect(error)}"
        if String.contains?(inspect(error), "Program not found") do
          IO.puts "   🚨 Session affinity NOT working - different workers used"
        end
    end
  end
end

if System.argv() |> List.first() != "--no-run" do
  SessionAffinityTest.main()
end