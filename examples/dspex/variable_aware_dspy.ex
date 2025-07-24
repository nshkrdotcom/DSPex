defmodule DSPex.Examples.VariableAwareDSPy do
  @moduledoc """
  Example demonstrating variable-aware DSPy integration.
  
  This shows how DSPex Variables automatically synchronize with
  DSPy module parameters through the VariableAwareMixin.
  """
  
  alias DSPex.{Context, Variables}
  
  @doc """
  Demonstrates automatic variable synchronization with DSPy modules.
  
  The Python DSPy module will automatically use the temperature
  and max_tokens values from the DSPex Variables system.
  """
  def variable_aware_prediction_example do
    # Start a context
    {:ok, ctx} = Context.start_link()
    
    # Define variables that will control the DSPy module
    Variables.defvariable!(ctx, :temperature, :float, 0.7,
      constraints: %{min: 0.0, max: 2.0},
      description: "LLM generation temperature"
    )
    
    Variables.defvariable!(ctx, :max_tokens, :integer, 256,
      constraints: %{min: 1, max: 4096},
      description: "Maximum tokens to generate"
    )
    
    Variables.defvariable!(ctx, :model, :string, "gpt-4",
      constraints: %{enum: ["gpt-4", "gpt-3.5-turbo", "claude-3"]},
      description: "LLM model to use"
    )
    
    # Register a variable-aware DSPy program
    program_id = "qa_assistant"
    
    Context.register_program(ctx, program_id, %{
      type: :dspy,
      module_type: "chain_of_thought",
      signature: %{
        inputs: [%{name: "question", type: "string", description: "User's question"}],
        outputs: [%{name: "answer", type: "string", description: "Generated answer"}]
      },
      variable_aware: true,
      variable_bindings: %{
        # DSPy module attribute -> DSPex variable name
        "temperature" => "temperature",
        "max_tokens" => "max_tokens",
        "model" => "model"
      }
    })
    
    # First execution with default values
    {:ok, result1} = Context.call(ctx, program_id, %{
      question: "What are the key features of DSPy?"
    })
    
    IO.puts("First answer (temp=0.7, max_tokens=256):")
    IO.puts(result1["answer"])
    IO.puts("")
    
    # Update variables - the DSPy module will automatically use new values
    Variables.set(ctx, :temperature, 0.9)
    Variables.set(ctx, :max_tokens, 512)
    
    # Second execution with updated values
    {:ok, result2} = Context.call(ctx, program_id, %{
      question: "Explain the benefits of variable-aware DSPy modules"
    })
    
    IO.puts("Second answer (temp=0.9, max_tokens=512):")
    IO.puts(result2["answer"])
    IO.puts("")
    
    # Show current variable values
    IO.puts("Current variable values:")
    config = Variables.get_many(ctx, [:temperature, :max_tokens, :model])
    IO.inspect(config, label: "Config")
    
    ctx
  end
  
  @doc """
  Demonstrates dynamic module configuration based on task type.
  """
  def adaptive_reasoning_example do
    {:ok, ctx} = Context.start_link()
    
    # Define task-specific temperature profiles
    Variables.defvariable!(ctx, :task_type, :string, "analytical",
      constraints: %{enum: ["analytical", "creative", "balanced"]}
    )
    
    Variables.defvariable!(ctx, :reasoning_temperature, :float, 0.3,
      constraints: %{min: 0.0, max: 1.5}
    )
    
    Variables.defvariable!(ctx, :reasoning_depth, :integer, 3,
      constraints: %{min: 1, max: 10},
      description: "Number of reasoning steps"
    )
    
    # Create reasoning module
    Context.register_program(ctx, "adaptive_reasoner", %{
      type: :dspy,
      module_type: "chain_of_thought",
      signature: %{
        inputs: [%{name: "problem", type: "string"}],
        outputs: [
          %{name: "reasoning", type: "string"},
          %{name: "solution", type: "string"}
        ]
      },
      variable_aware: true,
      variable_bindings: %{
        "temperature" => "reasoning_temperature",
        "max_reasoning_steps" => "reasoning_depth"
      }
    })
    
    # Function to adjust parameters based on task type
    adjust_for_task = fn task_type ->
      case task_type do
        "analytical" ->
          Variables.update_many(ctx, %{
            reasoning_temperature: 0.3,
            reasoning_depth: 5
          })
          
        "creative" ->
          Variables.update_many(ctx, %{
            reasoning_temperature: 0.9,
            reasoning_depth: 3
          })
          
        "balanced" ->
          Variables.update_many(ctx, %{
            reasoning_temperature: 0.6,
            reasoning_depth: 4
          })
      end
    end
    
    # Analytical task
    Variables.set(ctx, :task_type, "analytical")
    adjust_for_task.("analytical")
    
    {:ok, result1} = Context.call(ctx, "adaptive_reasoner", %{
      problem: "Calculate the compound interest on $1000 at 5% for 3 years"
    })
    
    IO.puts("Analytical reasoning (low temp, high depth):")
    IO.puts(result1["reasoning"])
    IO.puts("Solution: #{result1["solution"]}\n")
    
    # Creative task
    Variables.set(ctx, :task_type, "creative")
    adjust_for_task.("creative")
    
    {:ok, result2} = Context.call(ctx, "adaptive_reasoner", %{
      problem: "Design a new type of sustainable transportation"
    })
    
    IO.puts("Creative reasoning (high temp, low depth):")
    IO.puts(result2["reasoning"])
    IO.puts("Solution: #{result2["solution"]}\n")
    
    ctx
  end
  
  @doc """
  Demonstrates session-based variable persistence with DSPy programs.
  """
  def session_persistence_example do
    {:ok, ctx} = Context.start_link()
    
    # Create session variables using SessionStore
    IO.puts("Creating session variables...")
    
    Variables.defvariable!(ctx, :system_prompt, :string, 
      "You are a helpful AI assistant.",
      description: "System prompt for the LLM"
    )
    
    Variables.defvariable!(ctx, :response_style, :string, "concise",
      constraints: %{enum: ["concise", "detailed", "technical", "casual"]}
    )
    
    IO.puts("Variables defined: #{length(Variables.list(ctx))}")
    IO.puts("Session ID: #{Context.get_session_id(ctx)}")
    
    # Register a DSPy program that can access session variables
    IO.puts("\nRegistering DSPy program...")
    
    Context.register_program(ctx, "style_aware_assistant", %{
      type: :dspy,
      module_type: "predict",
      signature: %{
        inputs: [%{name: "query", type: "string"}],
        outputs: [%{name: "response", type: "string"}]
      },
      variable_aware: true,
      variable_bindings: %{
        "system_prompt" => "system_prompt",
        "style" => "response_style"
      }
    })
    
    # Show session variables are preserved
    IO.puts("Variables still available: #{length(Variables.list(ctx))}")
    
    # List current variables
    IO.puts("\nCurrent session variables:")
    for var <- Variables.list(ctx) do
      IO.puts("  #{var.name} = #{inspect(var.value)}")
    end
    
    # Demonstrate variable updates affect program behavior
    for style <- ["concise", "detailed", "technical"] do
      Variables.set(ctx, :response_style, style)
      
      # Note: This would work with Snakepit running
      IO.puts("\nWould call program with #{style} style...")
      # {:ok, result} = Context.call(ctx, "style_aware_assistant", %{
      #   query: "Explain quantum computing"
      # })
    end
    
    ctx
  end
  
  @doc """
  Run all examples.
  """
  def run_all do
    IO.puts("=== Variable-Aware Prediction Example ===\n")
    variable_aware_prediction_example()
    
    IO.puts("\n=== Adaptive Reasoning Example ===\n")
    adaptive_reasoning_example()
    
    IO.puts("\n=== Session Persistence Example ===\n")
    session_persistence_example()
    
    :ok
  end
end