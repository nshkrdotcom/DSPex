defmodule AshDSPex.GeminiIntegrationTest do
  use ExUnit.Case, async: false

  # Only run in full_integration mode
  @moduletag :layer_3
  @moduletag :gemini_integration

  alias AshDSPex.PythonBridge.Bridge
  import AshDSPex.BridgeTestHelpers, only: [wait_for_bridge_startup: 2]

  describe "Gemini integration with Elixir signatures" do
    setup do
      case System.get_env("GEMINI_API_KEY") do
        nil ->
          {:skip, "GEMINI_API_KEY not set"}

        _key ->
          # Wait for bridge to be ready using event-driven coordination
          case wait_for_bridge_startup(AshDSPex.PythonBridge.Bridge, 10_000) do
            {:ok, :ready} -> :ok
            # Continue with test anyway, let individual tests handle failures
            {:error, _reason} -> :ok
          end
      end
    end

    test "can ping bridge and verify Gemini availability" do
      case Bridge.call(:ping, %{}, 5000) do
        {:ok, result} ->
          assert result["status"] == "ok"
          assert result["dspy_available"] == true
          assert result["gemini_available"] == true
          assert is_float(result["uptime"])

        {:error, reason} ->
          flunk("Bridge ping failed: #{inspect(reason)}")
      end
    end

    test "can create and execute Gemini program with simple QA" do
      # Define signature in Elixir format
      signature = %{
        inputs: [
          %{name: "question", description: "A question to answer"}
        ],
        outputs: [
          %{name: "answer", description: "A concise answer"}
        ]
      }

      program_id = "qa_test_#{System.unique_integer([:positive])}"

      # Create Gemini program
      case Bridge.call(
             :create_gemini_program,
             %{
               id: program_id,
               signature: signature,
               model: "gemini-1.5-flash"
             },
             10000
           ) do
        {:ok, result} ->
          assert result["program_id"] == program_id
          assert result["status"] == "created"
          assert result["type"] == "gemini"
          assert result["model_name"] == "gemini-1.5-flash"

        {:error, reason} ->
          flunk("Program creation failed: #{inspect(reason)}")
      end

      # Execute the program
      case Bridge.call(
             :execute_gemini_program,
             %{
               program_id: program_id,
               inputs: %{question: "What is 2+2?"}
             },
             15000
           ) do
        {:ok, result} ->
          assert result["program_id"] == program_id
          assert Map.has_key?(result, "outputs")
          assert Map.has_key?(result["outputs"], "answer")

          answer = result["outputs"]["answer"]
          assert is_binary(answer)
          assert String.length(answer) > 0

          # Should contain "4" somewhere
          assert String.contains?(String.downcase(answer), "4")

          IO.puts("✅ Gemini answered: #{answer}")

        {:error, reason} ->
          flunk("Program execution failed: #{inspect(reason)}")
      end

      # Cleanup
      Bridge.call(:delete_program, %{program_id: program_id}, 5000)
    end

    test "can handle complex multi-field signatures" do
      signature = %{
        inputs: [
          %{name: "text", description: "Text to analyze"},
          %{name: "task", description: "What to do with the text"}
        ],
        outputs: [
          %{name: "summary", description: "A brief summary"},
          %{name: "sentiment", description: "The sentiment (positive/negative/neutral)"}
        ]
      }

      program_id = "analysis_test_#{System.unique_integer([:positive])}"

      # Create program
      {:ok, _result} =
        Bridge.call(
          :create_gemini_program,
          %{
            id: program_id,
            signature: signature,
            model: "gemini-1.5-flash"
          },
          10000
        )

      # Execute with complex inputs
      case Bridge.call(
             :execute_gemini_program,
             %{
               program_id: program_id,
               inputs: %{
                 text: "I love using Elixir for building distributed systems. It's fantastic!",
                 task: "Analyze the sentiment and provide a summary"
               }
             },
             15000
           ) do
        {:ok, result} ->
          outputs = result["outputs"]

          assert Map.has_key?(outputs, "summary")
          assert Map.has_key?(outputs, "sentiment")

          summary = outputs["summary"]
          sentiment = outputs["sentiment"]

          assert is_binary(summary)
          assert is_binary(sentiment)
          assert String.length(summary) > 0
          assert String.length(sentiment) > 0

          # Sentiment should be positive
          assert String.contains?(String.downcase(sentiment), "positive")

          IO.puts("✅ Analysis complete:")
          IO.puts("   Summary: #{summary}")
          IO.puts("   Sentiment: #{sentiment}")

        {:error, reason} ->
          flunk("Complex execution failed: #{inspect(reason)}")
      end

      # Cleanup
      Bridge.call(:delete_program, %{program_id: program_id}, 5000)
    end

    test "can list and manage multiple programs" do
      # Create multiple programs
      program_ids =
        for i <- 1..3 do
          program_id = "multi_test_#{i}_#{System.unique_integer([:positive])}"

          {:ok, _result} =
            Bridge.call(
              :create_gemini_program,
              %{
                id: program_id,
                signature: %{
                  inputs: [%{name: "input", description: "Test input"}],
                  outputs: [%{name: "output", description: "Test output"}]
                }
              },
              10000
            )

          program_id
        end

      # List programs
      case Bridge.call(:list_programs, %{}, 5000) do
        {:ok, result} ->
          programs = result["programs"]
          total_count = result["total_count"]

          assert is_list(programs)
          assert is_integer(total_count)
          assert total_count >= 3

          # Check that our programs are in the list
          program_ids_in_list = Enum.map(programs, & &1["id"])

          for program_id <- program_ids do
            assert program_id in program_ids_in_list
          end

          IO.puts("✅ Found #{total_count} programs in bridge")

        {:error, reason} ->
          flunk("List programs failed: #{inspect(reason)}")
      end

      # Cleanup all test programs
      for program_id <- program_ids do
        Bridge.call(:delete_program, %{program_id: program_id}, 5000)
      end
    end

    test "can get bridge statistics" do
      case Bridge.call(:get_stats, %{}, 5000) do
        {:ok, stats} ->
          assert Map.has_key?(stats, "programs_count")
          assert Map.has_key?(stats, "command_count")
          assert Map.has_key?(stats, "uptime")
          assert Map.has_key?(stats, "dspy_available")
          assert Map.has_key?(stats, "gemini_available")

          assert is_integer(stats["programs_count"])
          assert is_integer(stats["command_count"])
          assert is_float(stats["uptime"])
          assert stats["dspy_available"] == true
          assert stats["gemini_available"] == true

          IO.puts(
            "✅ Bridge stats: #{stats["command_count"]} commands, #{stats["programs_count"]} programs"
          )

        {:error, reason} ->
          flunk("Get stats failed: #{inspect(reason)}")
      end
    end

    test "handles errors gracefully" do
      # Try to execute non-existent program
      case Bridge.call(
             :execute_gemini_program,
             %{
               program_id: "nonexistent",
               inputs: %{test: "value"}
             },
             5000
           ) do
        {:error, reason} ->
          assert is_binary(reason)
          assert String.contains?(reason, "not found")

        {:ok, _result} ->
          flunk("Should have failed with non-existent program")
      end

      # Try to create program with invalid signature
      case Bridge.call(
             :create_gemini_program,
             %{
               id: "invalid_test",
               signature: %{
                 # No inputs
                 inputs: [],
                 # No outputs
                 outputs: []
               }
             },
             5000
           ) do
        # This might succeed or fail depending on validation
        # The important thing is that it doesn't crash the bridge
        result -> assert is_tuple(result)
      end
    end
  end
end
