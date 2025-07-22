defmodule DSPex.Examples.VariablesUsage do
  @moduledoc """
  Examples of DSPex.Variables usage patterns.
  """

  alias DSPex.{Context, Variables}

  def basic_usage do
    {:ok, ctx} = Context.start_link()

    # Define typed variables
    _ =
      Variables.defvariable!(ctx, :temperature, :float, 0.7,
        constraints: %{min: 0.0, max: 2.0},
        description: "Controls randomness in generation"
      )

    _ = Variables.defvariable!(ctx, :max_tokens, :integer, 256, constraints: %{min: 1, max: 4096})

    _ =
      Variables.defvariable!(ctx, :model, :string, "gpt-4",
        constraints: %{
          enum: ["gpt-4", "gpt-3.5-turbo", "claude-3", "gemini-pro"]
        }
      )

    # Use variables
    temp = Variables.get(ctx, :temperature)
    IO.puts("Current temperature: #{temp}")

    # Update with validation
    case Variables.set(ctx, :temperature, 1.5) do
      :ok -> IO.puts("Temperature updated")
      {:error, reason} -> IO.puts("Update failed: #{inspect(reason)}")
    end

    # Functional updates
    _ = Variables.update(ctx, :max_tokens, &min(&1 * 2, 4096))

    ctx
  end

  def batch_operations do
    {:ok, ctx} = Context.start_link()

    # Define multiple variables
    for {name, type, value} <- [
          {:learning_rate, :float, 0.001},
          {:batch_size, :integer, 32},
          {:optimizer, :string, "adam"},
          {:use_cuda, :boolean, true}
        ] do
      _ = Variables.defvariable!(ctx, name, type, value)
    end

    # Get all at once
    config = Variables.get_many(ctx, [:learning_rate, :batch_size, :optimizer, :use_cuda])
    IO.inspect(config, label: "Training config")

    # Update multiple
    _ =
      Variables.update_many(ctx, %{
        learning_rate: 0.0001,
        batch_size: 64
      })

    ctx
  end

  def error_handling do
    {:ok, ctx} = Context.start_link()

    # Safe operations with defaults
    value = Variables.get(ctx, :missing, "default")
    # "default"
    IO.puts("Got: #{value}")

    # Explicit error handling
    try do
      Variables.get!(ctx, :missing)
    rescue
      e in DSPex.Variables.VariableNotFoundError ->
        IO.puts("Variable #{e.identifier} not found")
    end

    # Validation errors
    _ = Variables.defvariable!(ctx, :percentage, :float, 0.5, constraints: %{min: 0.0, max: 1.0})

    case Variables.set(ctx, :percentage, 1.5) do
      :ok ->
        :ok

      {:error, reason} ->
        IO.puts("Validation failed: #{inspect(reason)}")
    end

    ctx
  end

  def introspection do
    {:ok, ctx} = Context.start_link()

    # Define some variables
    _ = Variables.defvariable!(ctx, :api_key, :string, "sk-...", metadata: %{"sensitive" => true})

    _ =
      Variables.defvariable!(ctx, :timeout, :integer, 30,
        constraints: %{min: 1, max: 300},
        description: "Request timeout in seconds"
      )

    # List all variables
    IO.puts("\nAll variables:")

    for var <- Variables.list(ctx) do
      IO.puts("  #{var.name} (#{var.type}): #{inspect(var.value)}")
    end

    # Get specific information
    IO.puts("\ntimeout type: #{Variables.get_type(ctx, :timeout)}")
    IO.puts("timeout constraints: #{inspect(Variables.get_constraints(ctx, :timeout))}")
    IO.puts("api_key metadata: #{inspect(Variables.get_metadata(ctx, :api_key))}")

    # Check existence
    IO.puts("\nExists? timeout: #{Variables.exists?(ctx, :timeout)}")
    IO.puts("Exists? missing: #{Variables.exists?(ctx, :missing)}")

    ctx
  end
end
