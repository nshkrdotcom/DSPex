defmodule DecomposedMacroDemo do
  @moduledoc """
  Demonstrates the new decomposed macro system for DSPex.
  
  This example shows how to use the composable behaviors to create
  sophisticated wrappers for Python DSPy components.
  """
  
  # Example 1: Simple wrapper - just the basics
  defmodule BasicPredictor do
    use DSPex.Bridge.SimpleWrapper
    
    wrap_dspy "dspy.Predict"
  end
  
  # Example 2: Adding observability
  defmodule ObservablePredictor do
    use DSPex.Bridge.SimpleWrapper
    use DSPex.Bridge.Observable
    
    wrap_dspy "dspy.Predict"
    
    @impl DSPex.Bridge.Observable
    def telemetry_metadata(:call, %{method: "__call__", question: question}) do
      %{
        question_length: String.length(question || ""),
        question_words: length(String.split(question || "", " ")),
        timestamp: System.system_time(:microsecond)
      }
    end
  end
  
  # Example 3: Bidirectional communication
  defmodule EnhancedPredictor do
    use DSPex.Bridge.SimpleWrapper
    use DSPex.Bridge.Bidirectional
    
    wrap_dspy "dspy.Predict"
    
    @impl DSPex.Bridge.Bidirectional
    def elixir_tools do
      [
        {"validate_answer", &validate_answer/1},
        {"fetch_context", &fetch_context/1},
        {"check_cache", &check_cache/1}
      ]
    end
    
    defp validate_answer(%{"answer" => answer}) do
      # Business logic validation
      cond do
        String.length(answer) < 10 ->
          {:error, "Answer too short"}
        String.contains?(answer, ["I don't know", "unclear"]) ->
          {:error, "Answer lacks confidence"}
        true ->
          {:ok, answer}
      end
    end
    
    defp fetch_context(%{"topic" => topic}) do
      # Simulate fetching relevant context from a database
      %{
        "topic" => topic,
        "facts" => [
          "Fact 1 about #{topic}",
          "Fact 2 about #{topic}"
        ],
        "examples" => ["Example 1", "Example 2"]
      }
    end
    
    defp check_cache(%{"question" => question}) do
      # Simulate cache lookup
      cache_key = :crypto.hash(:sha256, question) |> Base.encode16()
      
      case Process.get({:cache, cache_key}) do
        nil -> {:miss, nil}
        answer -> {:hit, answer}
      end
    end
  end
  
  # Example 4: Result transformation
  defmodule TypedPredictor do
    use DSPex.Bridge.SimpleWrapper
    use DSPex.Bridge.ResultTransform
    
    wrap_dspy "dspy.Predict"
    
    defmodule Answer do
      defstruct [:text, :confidence, :metadata, :generated_at]
    end
    
    @impl DSPex.Bridge.ResultTransform
    def transform_result(%{"answer" => text} = result) do
      %Answer{
        text: text,
        confidence: Map.get(result, "confidence", 1.0),
        metadata: Map.drop(result, ["answer", "confidence"]),
        generated_at: DateTime.utc_now()
      }
    end
    
    @impl DSPex.Bridge.ResultTransform
    def transform_input(%{question: q, context: ctx}) do
      %{
        "question" => q,
        "context" => Enum.join(ctx, "\n"),
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    end
  end
  
  # Example 5: Contract-based with full type safety
  defmodule ContractPredictor do
    use DSPex.Bridge.ContractBased
    use DSPex.Bridge.Observable
    
    # This would use a predefined contract
    use_contract DSPex.Contracts.Predict
    
    @impl DSPex.Bridge.Observable
    def telemetry_metadata(:create, %{signature: sig}) do
      %{signature: sig, module: __MODULE__}
    end
  end
  
  # Example 6: Full-featured composition
  defmodule ProductionPredictor do
    use DSPex.Bridge.SimpleWrapper
    use DSPex.Bridge.Bidirectional
    use DSPex.Bridge.Observable
    use DSPex.Bridge.ResultTransform
    
    wrap_dspy "dspy.ChainOfThought"
    
    # Production result type
    defmodule Result do
      defstruct [
        :reasoning_steps,
        :final_answer,
        :confidence,
        :processing_time_ms,
        :metadata
      ]
    end
    
    @impl DSPex.Bridge.Bidirectional
    def elixir_tools do
      [
        {"log_reasoning", &log_reasoning_step/1},
        {"validate_step", &validate_reasoning_step/1},
        {"fetch_examples", &fetch_relevant_examples/1}
      ]
    end
    
    @impl DSPex.Bridge.Bidirectional
    def on_python_callback(tool_name, args, _context) do
      Logger.info("Python called tool: #{tool_name}", args: args)
      :ok
    end
    
    @impl DSPex.Bridge.Observable
    def telemetry_metadata(operation, args) do
      base_metadata = %{
        operation: operation,
        module: __MODULE__,
        timestamp: System.system_time(:microsecond)
      }
      
      case operation do
        :call ->
          Map.merge(base_metadata, %{
            method: Map.get(args, :method),
            has_context: Map.has_key?(args, :context)
          })
        _ ->
          base_metadata
      end
    end
    
    @impl DSPex.Bridge.Observable
    def before_execute(:call, %{method: "__call__"} = args) do
      # Could implement rate limiting here
      :telemetry.execute(
        [:production, :predictor, :request],
        %{count: 1},
        args
      )
      :ok
    end
    
    @impl DSPex.Bridge.ResultTransform
    def transform_result(%{"reasoning" => reasoning, "answer" => answer} = result) do
      %Result{
        reasoning_steps: parse_reasoning(reasoning),
        final_answer: answer,
        confidence: Map.get(result, "confidence", 0.0),
        processing_time_ms: Map.get(result, "processing_time", 0),
        metadata: Map.drop(result, ["reasoning", "answer", "confidence", "processing_time"])
      }
    end
    
    # Helper functions
    defp log_reasoning_step(%{"step" => step, "content" => content}) do
      Logger.info("Reasoning step #{step}: #{content}")
      :ok
    end
    
    defp validate_reasoning_step(%{"content" => content}) do
      String.length(content) > 20
    end
    
    defp fetch_relevant_examples(%{"topic" => topic}) do
      # In production, this would query a vector database
      %{
        "examples" => [
          "Example about #{topic} #1",
          "Example about #{topic} #2"
        ]
      }
    end
    
    defp parse_reasoning(reasoning) when is_binary(reasoning) do
      reasoning
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.with_index(1)
      |> Enum.map(fn {content, idx} -> 
        %{step: idx, content: content}
      end)
    end
    defp parse_reasoning(steps) when is_list(steps), do: steps
  end
  
  # Demonstration functions
  def run_examples do
    IO.puts("\n=== Decomposed Macro System Demo ===\n")
    
    # Example 1: Basic usage
    IO.puts("1. Basic Wrapper:")
    IO.inspect(BasicPredictor.__python_class__())
    IO.inspect(function_exported?(BasicPredictor, :create, 1))
    
    # Example 2: Observable
    IO.puts("\n2. Observable Wrapper:")
    metadata = ObservablePredictor.telemetry_metadata(:call, %{method: "__call__", question: "What is AI?"})
    IO.inspect(metadata)
    
    # Example 3: Bidirectional
    IO.puts("\n3. Bidirectional Tools:")
    tools = EnhancedPredictor.elixir_tools()
    IO.puts("Available tools: #{inspect(Enum.map(tools, fn {name, _} -> name end))}")
    
    # Example 4: Transformation
    IO.puts("\n4. Result Transformation:")
    python_result = %{"answer" => "AI is artificial intelligence", "confidence" => 0.95}
    transformed = TypedPredictor.transform_result(python_result)
    IO.inspect(transformed)
    
    # Example 5: Behaviors
    IO.puts("\n5. Composed Behaviors:")
    behaviors = ProductionPredictor.__dspex_behaviors__()
    IO.puts("Active behaviors: #{inspect(behaviors)}")
    
    IO.puts("\n=== Demo Complete ===")
  end
  
  # Run with: mix run examples/decomposed_macro_demo.exs -e "DecomposedMacroDemo.run_examples()"
end

# Execute the demo
DecomposedMacroDemo.run_examples()