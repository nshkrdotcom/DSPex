# Prompt: Implement Advanced Variable Types (Choice and Module)

## Objective
Implement choice and module variable types that enable configuration-as-code patterns, dynamic behavior selection, and structured options management in the unified bridge.

## Context
Advanced variable types extend beyond simple primitives to support:
- **Choice**: Enumerated values with validation (e.g., model selection)
- **Module**: Dynamic module/strategy selection (e.g., reasoning strategies)

These types are essential for building adaptive AI systems where behavior can be controlled through variables.

## Requirements

### Choice Type
1. Enumerated string values with validation
2. Support for both string and atom representations
3. Clear error messages for invalid choices
4. Serialization compatibility

### Module Type
1. Module/class name storage with optional validation
2. Support for constrained choices or open selection
3. Integration with DSPy module system
4. Safe string-to-module resolution

## Implementation

### Create Choice Type

```elixir
# File: lib/dspex/bridge/variables/types/choice.ex

defmodule DSPex.Bridge.Variables.Types.Choice do
  @moduledoc """
  Choice type for variables with a fixed set of options.
  
  Choices are string values that must match one of the allowed options.
  This is ideal for configuration values like model names, strategies,
  or any enumerated setting.
  
  ## Examples
  
      # Model selection
      defvariable(ctx, :model, :choice, "gpt-4",
        constraints: %{choices: ["gpt-4", "gpt-3.5-turbo", "claude-3"]}
      )
      
      # Strategy selection  
      defvariable(ctx, :search_strategy, :choice, "bfs",
        constraints: %{choices: ["bfs", "dfs", "a_star"]},
        description: "Graph search algorithm"
      )
  """
  
  @behaviour DSPex.Bridge.Variables.Types
  
  @impl true
  def validate(value) when is_binary(value), do: {:ok, value}
  def validate(value) when is_atom(value), do: {:ok, to_string(value)}
  def validate(value), do: {:error, "must be a string or atom, got #{inspect(value)}"}
  
  @impl true
  def validate_constraints(value, constraints) do
    choices = get_choices(constraints)
    
    cond do
      choices == [] ->
        # No choices specified - any string is valid
        :ok
        
      value in choices ->
        :ok
        
      true ->
        # Provide helpful error with available choices
        choices_str = choices
        |> Enum.map(&inspect/1)
        |> Enum.join(", ")
        
        {:error, "must be one of: #{choices_str}"}
    end
  end
  
  @impl true
  def serialize(value) when is_binary(value) do
    {:ok, %{"type" => "choice", "value" => value}}
  end
  
  @impl true
  def deserialize(%{"type" => "choice", "value" => value}) when is_binary(value) do
    {:ok, value}
  end
  def deserialize(value) when is_binary(value) do
    # Simple string deserialization
    {:ok, value}
  end
  def deserialize(_), do: {:error, "invalid choice data"}
  
  @impl true
  def default_value(constraints) do
    case get_choices(constraints) do
      [first | _] -> first
      [] -> ""
    end
  end
  
  @impl true
  def type_info do
    %{
      name: :choice,
      description: "Enumerated string value from a fixed set of choices",
      example: "gpt-4",
      constraints: %{
        choices: "List of allowed values (optional)"
      }
    }
  end
  
  ## Private functions
  
  defp get_choices(constraints) do
    case Map.get(constraints, :choices, []) do
      choices when is_list(choices) ->
        Enum.map(choices, &to_string/1)
      _ ->
        []
    end
  end
end
```

### Create Module Type

```elixir
# File: lib/dspex/bridge/variables/types/module.ex

defmodule DSPex.Bridge.Variables.Types.Module do
  @moduledoc """
  Module type for dynamic module/class selection.
  
  Module variables store module or class names as strings, enabling
  dynamic behavior selection. This is particularly useful for:
  - DSPy module selection (Predict, ChainOfThought, ReAct)
  - Strategy pattern implementation
  - Plugin/adapter selection
  
  ## Examples
  
      # DSPy module selection
      defvariable(ctx, :reasoning_module, :module, "ChainOfThought",
        constraints: %{
          choices: ["Predict", "ChainOfThought", "ReAct", "ProgramOfThought"],
          namespace: "dspy.modules"
        }
      )
      
      # Open module selection
      defvariable(ctx, :custom_processor, :module, "MyApp.Processors.Default",
        constraints: %{pattern: "^MyApp\\.Processors\\."}
      )
  """
  
  @behaviour DSPex.Bridge.Variables.Types
  
  @impl true
  def validate(value) when is_binary(value) do
    # Basic validation - must look like a module name
    if valid_module_name?(value) do
      {:ok, value}
    else
      {:error, "must be a valid module name (e.g., 'Module.SubModule')"}
    end
  end
  
  def validate(value) when is_atom(value) do
    validate(to_string(value))
  end
  
  def validate(_), do: {:error, "must be a module name string"}
  
  @impl true
  def validate_constraints(value, constraints) do
    cond do
      # Check choices if specified
      choices = get_choices(constraints) ->
        if value in choices do
          :ok
        else
          choices_str = Enum.join(choices, ", ")
          {:error, "must be one of: #{choices_str}"}
        end
        
      # Check pattern if specified
      pattern = Map.get(constraints, :pattern) ->
        if Regex.match?(~r/#{pattern}/, value) do
          :ok
        else
          {:error, "must match pattern: #{pattern}"}
        end
        
      # Check namespace if specified
      namespace = Map.get(constraints, :namespace) ->
        if String.starts_with?(value, namespace <> ".") or value == namespace do
          :ok
        else
          {:error, "must be in namespace: #{namespace}"}
        end
        
      # No constraints
      true ->
        :ok
    end
  end
  
  @impl true
  def serialize(value) when is_binary(value) do
    {:ok, %{
      "type" => "module",
      "value" => value,
      "language" => detect_language(value)
    }}
  end
  
  @impl true
  def deserialize(%{"type" => "module", "value" => value}) when is_binary(value) do
    {:ok, value}
  end
  def deserialize(value) when is_binary(value) do
    {:ok, value}
  end
  def deserialize(_), do: {:error, "invalid module data"}
  
  @impl true
  def default_value(constraints) do
    cond do
      choices = get_choices(constraints) -> hd(choices)
      namespace = Map.get(constraints, :namespace) -> namespace
      true -> "Module"
    end
  end
  
  @impl true
  def type_info do
    %{
      name: :module,
      description: "Module or class name for dynamic behavior selection",
      example: "ChainOfThought",
      constraints: %{
        choices: "List of allowed modules (optional)",
        pattern: "Regex pattern to match (optional)",
        namespace: "Required namespace prefix (optional)"
      }
    }
  end
  
  @doc """
  Resolve a module variable to an actual module (Elixir only).
  
  This is a helper for using module variables in Elixir code.
  Returns {:ok, module} or {:error, reason}.
  
  ## Examples
  
      iex> resolve_module("Enum")
      {:ok, Enum}
      
      iex> resolve_module("NonExistent")
      {:error, :not_found}
  """
  def resolve_module(module_string) when is_binary(module_string) do
    try do
      module = String.to_existing_atom("Elixir." <> module_string)
      if Code.ensure_loaded?(module) do
        {:ok, module}
      else
        {:error, :not_loaded}
      end
    rescue
      ArgumentError -> {:error, :not_found}
    end
  end
  
  ## Private functions
  
  defp valid_module_name?(string) do
    # Must start with capital letter and contain only valid characters
    Regex.match?(~r/^[A-Z][A-Za-z0-9_.]*$/, string)
  end
  
  defp get_choices(constraints) do
    case Map.get(constraints, :choices) do
      choices when is_list(choices) and choices != [] ->
        Enum.map(choices, &to_string/1)
      _ ->
        nil
    end
  end
  
  defp detect_language(module_name) do
    cond do
      # Common Python patterns
      String.contains?(module_name, ".") and not String.starts_with?(module_name, "Elixir.") ->
        "python"
        
      # Elixir modules
      String.match?(module_name, ~r/^[A-Z]/) ->
        "elixir"
        
      true ->
        "unknown"
    end
  end
end
```

### Update Type Registry

```elixir
# File: lib/dspex/bridge/variables/types.ex

defmodule DSPex.Bridge.Variables.Types do
  # ... existing code ...
  
  @type_modules %{
    float: DSPex.Bridge.Variables.Types.Float,
    integer: DSPex.Bridge.Variables.Types.Integer,
    string: DSPex.Bridge.Variables.Types.String,
    boolean: DSPex.Bridge.Variables.Types.Boolean,
    choice: DSPex.Bridge.Variables.Types.Choice,    # Add choice
    module: DSPex.Bridge.Variables.Types.Module     # Add module
  }
  
  @doc """
  Get list of available types with their info.
  """
  def available_types do
    Enum.map(@type_modules, fn {name, module} ->
      {name, module.type_info()}
    end)
    |> Enum.into(%{})
  end
end
```

### Python Support for Advanced Types

```python
# File: snakepit/priv/python/snakepit_bridge/types.py

"""
Advanced type support for the bridge.
"""

from typing import List, Optional, Dict, Any, Union
from dataclasses import dataclass
import re


@dataclass
class ChoiceType:
    """
    Choice type validator and helper.
    """
    choices: Optional[List[str]] = None
    
    def validate(self, value: Any) -> str:
        """Validate and normalize a choice value."""
        if not isinstance(value, (str, int, float, bool)):
            raise ValueError(f"Choice must be string-like, got {type(value)}")
            
        str_value = str(value)
        
        if self.choices and str_value not in self.choices:
            raise ValueError(
                f"Invalid choice '{str_value}'. "
                f"Must be one of: {', '.join(self.choices)}"
            )
            
        return str_value
    
    def __contains__(self, value: str) -> bool:
        """Check if value is a valid choice."""
        if not self.choices:
            return True
        return value in self.choices


@dataclass
class ModuleType:
    """
    Module type validator and helper.
    """
    choices: Optional[List[str]] = None
    pattern: Optional[str] = None
    namespace: Optional[str] = None
    
    def validate(self, value: Any) -> str:
        """Validate and normalize a module value."""
        if not isinstance(value, str):
            raise ValueError(f"Module must be string, got {type(value)}")
            
        # Check basic format
        if not self._is_valid_module_name(value):
            raise ValueError(
                f"Invalid module name '{value}'. "
                "Must be a valid Python/Elixir module name"
            )
        
        # Check constraints
        if self.choices and value not in self.choices:
            raise ValueError(
                f"Module '{value}' not in allowed choices: "
                f"{', '.join(self.choices)}"
            )
            
        if self.pattern and not re.match(self.pattern, value):
            raise ValueError(
                f"Module '{value}' doesn't match pattern: {self.pattern}"
            )
            
        if self.namespace:
            if not (value.startswith(self.namespace + ".") or value == self.namespace):
                raise ValueError(
                    f"Module '{value}' not in namespace: {self.namespace}"
                )
                
        return value
    
    def _is_valid_module_name(self, name: str) -> bool:
        """Check if string is a valid module name."""
        # Python style: package.module.Class
        if "." in name:
            parts = name.split(".")
            return all(self._is_valid_identifier(p) for p in parts)
        # Single name
        return self._is_valid_identifier(name)
    
    def _is_valid_identifier(self, name: str) -> bool:
        """Check if string is a valid Python identifier."""
        return name.isidentifier() or (name and name[0].isupper() and name[1:].replace("_", "").isalnum())
    
    def resolve_python_module(self, module_path: str) -> Any:
        """
        Resolve module string to actual Python module/class.
        
        Args:
            module_path: Module path like 'dspy.Predict' or 'my_module.MyClass'
            
        Returns:
            The resolved module or class
            
        Raises:
            ImportError: If module cannot be imported
            AttributeError: If attribute not found in module
        """
        parts = module_path.split('.')
        
        # Try progressive imports
        for i in range(len(parts), 0, -1):
            module_name = '.'.join(parts[:i])
            try:
                module = __import__(module_name, fromlist=[''])
                
                # Get remaining attributes
                result = module
                for attr in parts[i:]:
                    result = getattr(result, attr)
                    
                return result
                
            except ImportError:
                if i == 1:
                    raise
                continue
                
        raise ImportError(f"Cannot import '{module_path}'")


class VariableTypeRegistry:
    """
    Registry of variable types with validation.
    """
    
    def __init__(self):
        self.types = {
            'float': float,
            'integer': int,
            'string': str,
            'boolean': bool,
            'choice': ChoiceType,
            'module': ModuleType,
        }
    
    def validate(self, value: Any, var_type: str, constraints: Optional[Dict] = None) -> Any:
        """
        Validate a value against its type and constraints.
        """
        if var_type not in self.types:
            raise ValueError(f"Unknown type: {var_type}")
            
        type_class = self.types[var_type]
        
        # Handle advanced types
        if var_type == 'choice':
            validator = ChoiceType(choices=constraints.get('choices') if constraints else None)
            return validator.validate(value)
            
        elif var_type == 'module':
            validator = ModuleType(
                choices=constraints.get('choices') if constraints else None,
                pattern=constraints.get('pattern') if constraints else None,
                namespace=constraints.get('namespace') if constraints else None
            )
            return validator.validate(value)
            
        # Simple types
        else:
            try:
                return type_class(value)
            except (ValueError, TypeError) as e:
                raise ValueError(f"Invalid {var_type}: {e}")
```

### Integration Examples

```elixir
# File: lib/dspex/examples/advanced_types_example.ex

defmodule DSPex.Examples.AdvancedTypesExample do
  @moduledoc """
  Examples of using choice and module variable types.
  """
  
  alias DSPex.{Context, Variables}
  alias DSPex.Bridge.Variables.Types.Module
  
  def model_selection_example do
    {:ok, ctx} = Context.start_link()
    
    # Define model choice variable
    Variables.defvariable!(ctx, :llm_model, :choice, "gpt-4",
      constraints: %{
        choices: ["gpt-4", "gpt-3.5-turbo", "claude-3", "gemini-pro", "llama-2"]
      },
      description: "LLM model selection"
    )
    
    # Watch for model changes
    {:ok, _ref} = Variables.watch(ctx, [:llm_model], fn _name, old, new, _meta ->
      IO.puts("Model changed from #{old} to #{new}")
      
      # Adjust other parameters based on model
      case new do
        "gpt-4" ->
          Variables.set(ctx, :max_tokens, 4096)
          Variables.set(ctx, :temperature, 0.7)
          
        "claude-3" ->
          Variables.set(ctx, :max_tokens, 8192)
          Variables.set(ctx, :temperature, 0.8)
          
        "llama-2" ->
          Variables.set(ctx, :max_tokens, 2048)
          Variables.set(ctx, :temperature, 0.6)
          
        _ ->
          :ok
      end
    end)
    
    # Try different models
    for model <- ["claude-3", "gpt-3.5-turbo", "llama-2"] do
      case Variables.set(ctx, :llm_model, model) do
        :ok ->
          IO.puts("Successfully switched to #{model}")
        {:error, reason} ->
          IO.puts("Failed to switch to #{model}: #{inspect(reason)}")
      end
      
      Process.sleep(100)
    end
    
    # Try invalid model
    case Variables.set(ctx, :llm_model, "invalid-model") do
      {:error, msg} ->
        IO.puts("Expected error: #{msg}")
    end
  end
  
  def strategy_module_example do
    {:ok, ctx} = Context.start_link()
    
    # Define strategy module variable
    Variables.defvariable!(ctx, :search_strategy, :module, "DSPex.Strategies.BFS",
      constraints: %{
        namespace: "DSPex.Strategies",
        choices: ["BFS", "DFS", "AStar", "Dijkstra"]
      },
      description: "Graph search algorithm module"
    )
    
    # Define DSPy reasoning module
    Variables.defvariable!(ctx, :reasoning_module, :module, "Predict",
      constraints: %{
        choices: ["Predict", "ChainOfThought", "ReAct", "ProgramOfThought"]
      },
      metadata: %{"language" => "python", "framework" => "dspy"}
    )
    
    # Use module variable
    case Variables.get(ctx, :search_strategy) do
      "DSPex.Strategies." <> strategy_name = full_name ->
        IO.puts("Using #{strategy_name} strategy")
        
        # Resolve to actual module
        case Module.resolve_module(full_name) do
          {:ok, module} ->
            # Use the module
            result = module.search(graph, start, goal)
            IO.puts("Search result: #{inspect(result)}")
            
          {:error, :not_found} ->
            IO.puts("Module not found: #{full_name}")
        end
    end
    
    # Watch for reasoning module changes
    Variables.watch_one(ctx, :reasoning_module, fn _name, old, new, _meta ->
      IO.puts("Switching reasoning from #{old} to #{new}")
      
      # This would trigger Python-side module swap
      # via the bridge when integrated with DSPy
    end)
  end
  
  def dynamic_pipeline_example do
    {:ok, ctx} = Context.start_link()
    
    # Define pipeline components as module variables
    components = [
      {:preprocessor, "TextCleaner", ["TextCleaner", "HTMLStripper", "Normalizer"]},
      {:embedder, "SentenceTransformer", ["SentenceTransformer", "Word2Vec", "BERT"]},
      {:retriever, "DenseRetriever", ["DenseRetriever", "SparseRetriever", "Hybrid"]},
      {:reranker, "CrossEncoder", ["CrossEncoder", "MonoT5", "ColBERT"]}
    ]
    
    for {name, default, choices} <- components do
      Variables.defvariable!(ctx, name, :module, default,
        constraints: %{choices: choices},
        metadata: %{"pipeline_stage" => to_string(name)}
      )
    end
    
    # Create reactive pipeline that rebuilds on component change
    Variables.watch(ctx, Keyword.keys(components), fn name, old, new, _meta ->
      IO.puts("Pipeline component #{name} changed: #{old} -> #{new}")
      rebuild_pipeline(ctx)
    end)
    
    # Experiment with different configurations
    configurations = [
      %{embedder: "BERT", retriever: "DenseRetriever"},
      %{embedder: "SentenceTransformer", retriever: "Hybrid"},
      %{preprocessor: "HTMLStripper", reranker: "MonoT5"}
    ]
    
    for config <- configurations do
      IO.puts("\nTrying configuration: #{inspect(config)}")
      Variables.update_many(ctx, config)
      Process.sleep(500)
    end
  end
  
  defp rebuild_pipeline(ctx) do
    # Get all pipeline components
    components = Variables.get_many(ctx, [:preprocessor, :embedder, :retriever, :reranker])
    
    IO.puts("Rebuilding pipeline with:")
    for {stage, module} <- components do
      IO.puts("  #{stage}: #{module}")
    end
    
    # In real implementation, this would instantiate
    # the actual pipeline with selected modules
  end
end
```

### Python Usage Examples

```python
# File: snakepit/priv/python/examples/advanced_types_example.py

import asyncio
from snakepit_bridge import SessionContext
from snakepit_bridge.types import ChoiceType, ModuleType


async def model_selection_example(session: SessionContext):
    """Example of using choice type for model selection."""
    print("\n=== Model Selection ===")
    
    # Define model choice variable
    await session.defvariable(
        'llm_model', 'choice', 'gpt-4',
        constraints={'choices': ['gpt-4', 'gpt-3.5-turbo', 'claude-3', 'gemini-pro']}
    )
    
    # Watch for changes
    async for update in session.watch_variables(['llm_model']):
        print(f"Model changed to: {update.value}")
        
        # Adjust parameters based on model
        if update.value == 'gpt-4':
            await session.update_variables({
                'temperature': 0.7,
                'max_tokens': 4096
            })
        elif update.value == 'claude-3':
            await session.update_variables({
                'temperature': 0.8,
                'max_tokens': 8192
            })


async def dspy_module_example(session: SessionContext):
    """Example of using module type with DSPy."""
    print("\n=== DSPy Module Selection ===")
    
    import dspy
    from snakepit_bridge.types import ModuleType
    
    # Define DSPy module variable
    await session.defvariable(
        'reasoning_module', 'module', 'dspy.Predict',
        constraints={
            'choices': ['dspy.Predict', 'dspy.ChainOfThought', 'dspy.ReAct'],
            'namespace': 'dspy'
        }
    )
    
    # Create module resolver
    module_type = ModuleType(namespace='dspy')
    
    # Watch and dynamically load modules
    async for update in session.watch_variables(['reasoning_module']):
        try:
            # Resolve module string to class
            module_class = module_type.resolve_python_module(update.value)
            print(f"Loaded module: {module_class.__name__}")
            
            # Create instance with signature
            if hasattr(module_class, '__init__'):
                reasoning = module_class("question -> answer")
                print(f"Created {update.value} instance")
                
                # Use the module
                result = reasoning(question="What is the capital of France?")
                print(f"Result: {result.answer}")
                
        except ImportError as e:
            print(f"Failed to load module: {e}")


async def dynamic_pipeline_example(session: SessionContext):
    """Example of dynamic pipeline with module variables."""
    print("\n=== Dynamic Pipeline ===")
    
    # Define pipeline stages
    stages = {
        'retriever': {
            'default': 'retrievers.DenseRetriever',
            'choices': [
                'retrievers.DenseRetriever',
                'retrievers.SparseRetriever', 
                'retrievers.HybridRetriever'
            ]
        },
        'reranker': {
            'default': 'rerankers.CrossEncoder',
            'choices': [
                'rerankers.CrossEncoder',
                'rerankers.MonoT5',
                'rerankers.ColBERT'
            ]
        }
    }
    
    # Create module variables for each stage
    for stage, config in stages.items():
        await session.defvariable(
            stage, 'module', config['default'],
            constraints={'choices': config['choices']}
        )
    
    # Build pipeline from current configuration
    async def build_pipeline():
        modules = await session.get_variables(list(stages.keys()))
        
        print("Pipeline configuration:")
        for stage, module_name in modules.items():
            print(f"  {stage}: {module_name}")
            
        # In real implementation, instantiate modules here
        return modules
    
    # Watch for configuration changes
    async def pipeline_watcher():
        async for update in session.watch_variables(list(stages.keys())):
            print(f"\nPipeline updated - {update.variable_name}: {update.value}")
            await build_pipeline()
    
    # Start watching
    watch_task = asyncio.create_task(pipeline_watcher())
    
    # Try different configurations
    configs = [
        {'retriever': 'retrievers.SparseRetriever'},
        {'reranker': 'rerankers.MonoT5'},
        {'retriever': 'retrievers.HybridRetriever', 'reranker': 'rerankers.ColBERT'}
    ]
    
    for config in configs:
        print(f"\nApplying config: {config}")
        await session.update_variables(config)
        await asyncio.sleep(0.5)
    
    watch_task.cancel()


async def validation_example(session: SessionContext):
    """Example of type validation."""
    print("\n=== Type Validation ===")
    
    # Choice with validation
    await session.defvariable(
        'environment', 'choice', 'development',
        constraints={'choices': ['development', 'staging', 'production']}
    )
    
    # Valid update
    try:
        await session.set_variable('environment', 'staging')
        print("✓ Set environment to staging")
    except Exception as e:
        print(f"✗ Failed: {e}")
    
    # Invalid update
    try:
        await session.set_variable('environment', 'testing')
        print("✓ Set environment to testing (shouldn't work!)")
    except Exception as e:
        print(f"✗ Expected error: {e}")
    
    # Module with pattern validation
    await session.defvariable(
        'handler', 'module', 'handlers.DefaultHandler',
        constraints={'pattern': r'^handlers\.[A-Z][a-zA-Z]*Handler$'}
    )
    
    # Valid module name
    try:
        await session.set_variable('handler', 'handlers.CustomHandler')
        print("✓ Set handler to CustomHandler")
    except Exception as e:
        print(f"✗ Failed: {e}")
    
    # Invalid module name
    try:
        await session.set_variable('handler', 'invalid.module.name')
        print("✓ Set invalid handler (shouldn't work!)")
    except Exception as e:
        print(f"✗ Expected error: {e}")


async def main():
    """Run all examples."""
    async with SessionContext.connect('localhost:50051', 'advanced_types_demo') as session:
        await model_selection_example(session)
        await dspy_module_example(session)
        await dynamic_pipeline_example(session)
        await validation_example(session)


if __name__ == '__main__':
    asyncio.run(main())
```

## Testing

```elixir
defmodule DSPex.Bridge.Variables.Types.ChoiceTest do
  use ExUnit.Case
  
  alias DSPex.Bridge.Variables.Types.Choice
  
  describe "validation" do
    test "accepts strings" do
      assert {:ok, "option1"} = Choice.validate("option1")
    end
    
    test "accepts atoms and converts to strings" do
      assert {:ok, "option1"} = Choice.validate(:option1)
    end
    
    test "rejects non-string values" do
      assert {:error, _} = Choice.validate(123)
      assert {:error, _} = Choice.validate([])
    end
  end
  
  describe "constraint validation" do
    test "allows any value when no choices specified" do
      assert :ok = Choice.validate_constraints("anything", %{})
    end
    
    test "enforces choices when specified" do
      constraints = %{choices: ["red", "green", "blue"]}
      
      assert :ok = Choice.validate_constraints("red", constraints)
      assert :ok = Choice.validate_constraints("blue", constraints)
      
      assert {:error, msg} = Choice.validate_constraints("yellow", constraints)
      assert msg =~ "must be one of"
      assert msg =~ "red"
    end
    
    test "handles atom choices" do
      constraints = %{choices: [:red, :green, :blue]}
      
      assert :ok = Choice.validate_constraints("red", constraints)
    end
  end
end

defmodule DSPex.Bridge.Variables.Types.ModuleTest do
  use ExUnit.Case
  
  alias DSPex.Bridge.Variables.Types.Module
  
  describe "validation" do
    test "accepts valid module names" do
      assert {:ok, "MyModule"} = Module.validate("MyModule")
      assert {:ok, "My.Nested.Module"} = Module.validate("My.Nested.Module")
      assert {:ok, "Dspy.ChainOfThought"} = Module.validate("Dspy.ChainOfThought")
    end
    
    test "rejects invalid module names" do
      assert {:error, _} = Module.validate("123Module")
      assert {:error, _} = Module.validate("my-module")
      assert {:error, _} = Module.validate("")
    end
  end
  
  describe "constraint validation" do
    test "enforces namespace" do
      constraints = %{namespace: "MyApp.Modules"}
      
      assert :ok = Module.validate_constraints("MyApp.Modules.Handler", constraints)
      assert :ok = Module.validate_constraints("MyApp.Modules", constraints)
      
      assert {:error, _} = Module.validate_constraints("OtherApp.Handler", constraints)
    end
    
    test "enforces pattern" do
      constraints = %{pattern: ".*Handler$"}
      
      assert :ok = Module.validate_constraints("MyHandler", constraints)
      assert :ok = Module.validate_constraints("App.CustomHandler", constraints)
      
      assert {:error, _} = Module.validate_constraints("MyProcessor", constraints)
    end
  end
  
  describe "module resolution" do
    test "resolves existing Elixir modules" do
      assert {:ok, Enum} = Module.resolve_module("Enum")
      assert {:ok, String} = Module.resolve_module("String")
    end
    
    test "returns error for non-existent modules" do
      assert {:error, :not_found} = Module.resolve_module("NonExistentModule")
    end
  end
end
```

## Next Steps
After implementing advanced types:
1. Create comprehensive integration tests
2. Add more type examples (embedding, tensor)
3. Build adaptive system examples
4. Document type migration patterns
5. Create type conversion utilities