defmodule DSPex.VariablesIntegrationTest do
  use ExUnit.Case, async: true

  alias DSPex.{Context, Variables}

  describe "real-world usage patterns" do
    test "LLM configuration scenario" do
      {:ok, ctx} = Context.start_link()

      # Define LLM parameters
      Variables.defvariable!(ctx, :temperature, :float, 0.7,
        constraints: %{min: 0.0, max: 2.0},
        description: "Controls randomness in generation"
      )

      Variables.defvariable!(ctx, :max_tokens, :integer, 256,
        constraints: %{min: 1, max: 4096},
        description: "Maximum tokens to generate"
      )

      Variables.defvariable!(ctx, :model, :string, "gpt-4",
        constraints: %{
          enum: ["gpt-4", "gpt-3.5-turbo", "claude-3", "gemini-pro"]
        },
        description: "LLM model to use"
      )

      # Use batch operations to get config
      config = Variables.get_many(ctx, [:temperature, :max_tokens, :model])

      assert config == %{
               temperature: 0.7,
               max_tokens: 256,
               model: "gpt-4"
             }

      # Update multiple settings at once
      assert :ok =
               Variables.update_many(ctx, %{
                 temperature: 0.9,
                 max_tokens: 512
               })

      # Verify updates
      assert Variables.get(ctx, :temperature) == 0.9
      assert Variables.get(ctx, :max_tokens) == 512
    end

    test "training hyperparameters with validation" do
      {:ok, ctx} = Context.start_link()

      # Define hyperparameters with constraints
      Variables.defvariable!(ctx, :learning_rate, :float, 0.001,
        constraints: %{min: 0.0, max: 1.0}
      )

      Variables.defvariable!(ctx, :batch_size, :integer, 32, constraints: %{min: 1, max: 1024})

      # Test constraint validation
      assert {:error, _} = Variables.set(ctx, :learning_rate, 1.5)
      # Unchanged
      assert Variables.get(ctx, :learning_rate) == 0.001

      # Valid update
      assert :ok = Variables.set(ctx, :learning_rate, 0.0001)
      assert Variables.get(ctx, :learning_rate) == 0.0001

      # Functional update with validation
      assert :ok = Variables.update(ctx, :batch_size, &(&1 * 2))
      assert Variables.get(ctx, :batch_size) == 64

      # This would exceed constraint (64 * 20 = 1280 > 1024)
      assert {:error, _} = Variables.update(ctx, :batch_size, &(&1 * 20))
      # Unchanged
      assert Variables.get(ctx, :batch_size) == 64
    end

    test "session-based variable persistence" do
      {:ok, ctx} = Context.start_link()

      # Create variables using SessionStore
      Variables.defvariable!(ctx, :prompt_template, :string, "Answer: {answer}")
      Variables.defvariable!(ctx, :cache_size, :integer, 100)

      values = Variables.get_many(ctx, [:prompt_template, :cache_size])
      
      assert values == %{
        prompt_template: "Answer: {answer}",
        cache_size: 100
      }

      # Can update variables
      assert :ok = Variables.set(ctx, :cache_size, 200)
      assert Variables.get(ctx, :cache_size) == 200
    end

    test "introspection and metadata" do
      {:ok, ctx} = Context.start_link()

      # Create variables with metadata
      Variables.defvariable!(ctx, :api_key, :string, "sk-...",
        metadata: %{"sensitive" => true, "provider" => "openai"}
      )

      Variables.defvariable!(ctx, :retry_count, :integer, 3,
        constraints: %{min: 0, max: 10},
        metadata: %{"category" => "reliability"}
      )

      # List all variables
      vars = Variables.list(ctx)
      assert length(vars) == 2

      # Check metadata
      api_meta = Variables.get_metadata(ctx, :api_key)
      assert api_meta["sensitive"] == true
      assert api_meta["provider"] == "openai"

      # Check type and constraints
      assert Variables.get_type(ctx, :retry_count) == :integer
      assert Variables.get_constraints(ctx, :retry_count) == %{min: 0, max: 10}

      # Check existence
      assert Variables.exists?(ctx, :api_key) == true
      assert Variables.exists?(ctx, :missing) == false
    end
  end
end
