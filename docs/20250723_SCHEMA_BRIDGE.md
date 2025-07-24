# Schema-Driven Dynamic DSPy Bridge

**Date**: July 23, 2025  
**Status**: Design Proposal  
**Author**: Claude Code  

## Overview

This document outlines a **Schema-Driven Dynamic Bridge** architecture for DSPex that provides automatic, robust, and maintainable integration with DSPy without requiring manual wrapper creation for every DSPy class and method.

## Problem Statement

Current DSPy integration challenges:
- **Manual Wrapper Creation**: Every DSPy class requires explicit tool definitions
- **Brittle String Execution**: Direct Python code execution is error-prone
- **Maintenance Overhead**: DSPy updates require manual bridge updates  
- **Limited Discoverability**: No automatic way to explore available DSPy functionality
- **Inconsistent Error Handling**: Different failure modes across tools

## Proposed Architecture

### Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Elixir Application Layer                 │
│  DSPex.Modules.Predict, DSPex.Optimizers.MIPRO, etc.      │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│              Elixir Metaprogramming Bridge Layer           │
│  - Schema Discovery & Caching                              │
│  - Dynamic Module Generation                               │
│  - Configuration-Driven API Mapping                       │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                Python Generic Bridge Layer                 │
│  - Universal call_dspy Tool                                │
│  - Runtime Introspection & Validation                     │
│  - Structured Error Handling                              │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                      DSPy Library                          │
│  dspy.Predict, dspy.ChainOfThought, dspy.MIPRO, etc.      │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Details

### 1. Python Generic Bridge Layer

#### Core Tools

**`call_dspy/4` - Universal DSPy Function Caller**

```python
@tool(description="Generic DSPy function caller with introspection")
def call_dspy(self, module_path: str, function_name: str, args: List = None, kwargs: Dict = None) -> Dict[str, Any]:
    """
    Universal DSPy caller that can invoke any DSPy class or method.
    
    Examples:
    - Constructor: call_dspy("dspy.Predict", "__init__", [], {"signature": "question -> answer"})  
    - Method: call_dspy("stored.predict_123", "__call__", [], {"question": "What is DSPy?"})
    - Function: call_dspy("dspy.settings", "configure", [], {"lm": lm_instance})
    
    Returns:
    - Constructor: {"success": True, "instance_id": "predict_abc123", "type": "constructor"}
    - Method: {"success": True, "result": {...}, "type": "method"}
    - Error: {"success": False, "error": "...", "traceback": "..."}
    """
```

**`discover_dspy_schema/1` - Schema Discovery**

```python  
@tool(description="Discover DSPy module schema with introspection")
def discover_dspy_schema(self, module_path: str = "dspy") -> Dict[str, Any]:
    """
    Auto-discover available classes, methods, and signatures in DSPy modules.
    
    Returns complete schema including:
    - Class definitions and docstrings
    - Method signatures and parameter types  
    - Constructor requirements
    - Inheritance hierarchies
    
    Example output:
    {
      "success": True,
      "schema": {
        "Predict": {
          "type": "class",
          "docstring": "Basic predictor module...",
          "methods": {
            "__init__": {
              "signature": "(self, signature, **kwargs)",
              "parameters": ["signature"],
              "docstring": "Initialize predictor with signature"
            },
            "__call__": {
              "signature": "(self, **kwargs)",
              "parameters": [],
              "docstring": "Execute prediction"
            }
          }
        }
      }
    }
    """
```

**`validate_call/3` - Pre-flight Validation**

```python
@tool(description="Validate DSPy call before execution")  
def validate_call(self, module_path: str, function_name: str, kwargs: Dict) -> Dict[str, Any]:
    """
    Validate a DSPy call without executing it.
    Checks parameter types, required arguments, and method existence.
    """
```

#### Implementation Features

```python
class DSPyGRPCHandler(BaseAdapter):
    def __init__(self):
        super().__init__()
        self._schema_cache = {}  # Cache discovered schemas
        self._type_validators = {}  # Runtime type checking
        
    def _validate_call_signature(self, signature, args, kwargs):
        """Validate function call against Python signature"""
        try:
            signature.bind(*args, **kwargs)
            return True
        except TypeError as e:
            raise ValueError(f"Invalid arguments: {e}")
            
    def _serialize_result(self, result):
        """Convert Python objects to JSON-serializable format"""
        if hasattr(result, 'toDict'):
            return result.toDict()
        elif hasattr(result, '__dict__'):
            return {k: v for k, v in result.__dict__.items() if not k.startswith('_')}
        else:
            return str(result)
            
    def _resolve_stored_reference(self, module_path):
        """Resolve stored.instance_id references to actual objects"""
        if module_path.startswith("stored."):
            instance_id = module_path[7:]  # Remove "stored." prefix
            return _MODULE_STORAGE.get(instance_id)
        return None
```

### 2. Elixir Metaprogramming Bridge Layer

#### Schema Management

```elixir
defmodule DSPex.Schema do
  @moduledoc "DSPy schema discovery and caching"
  
  use GenServer
  
  @schema_cache_file "priv/cache/dspy_schema.json"
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def discover_schema(module_path \\ "dspy", opts \\ []) do
    case opts[:force_refresh] do
      true -> 
        fresh_discovery(module_path)
      _ -> 
        cached_or_discover(module_path)
    end
  end
  
  defp cached_or_discover(module_path) do
    case File.read(@schema_cache_file) do
      {:ok, cached_json} ->
        cached_data = Jason.decode!(cached_json)
        if fresh_enough?(cached_data["timestamp"]) do
          {:ok, cached_data["schema"]}
        else
          fresh_discovery(module_path)
        end
      {:error, _} ->
        fresh_discovery(module_path)
    end
  end
  
  defp fresh_discovery(module_path) do
    case Snakepit.execute_in_session("schema_discovery", "discover_dspy_schema", %{
      "module_path" => module_path
    }) do
      {:ok, %{"success" => true, "schema" => schema}} ->
        cache_schema(schema)
        {:ok, schema}
      error -> error
    end
  end
  
  defp cache_schema(schema) do
    cache_data = %{
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "schema" => schema
    }
    File.mkdir_p!(Path.dirname(@schema_cache_file))
    File.write!(@schema_cache_file, Jason.encode!(cache_data, pretty: true))
  end
  
  defp fresh_enough?(timestamp_str) do
    {:ok, cached_time, _} = DateTime.from_iso8601(timestamp_str)
    DateTime.diff(DateTime.utc_now(), cached_time, :hour) < 24  # 24 hour cache
  end
end
```

#### Dynamic Module Generation

```elixir
defmodule DSPex.Bridge do
  @moduledoc "Dynamic DSPy bridge with metaprogramming"
  
  defmacro defdsyp(module_name, class_path, config \\ %{}) do
    quote bind_quoted: [
      module_name: module_name,
      class_path: class_path, 
      config: config
    ] do
      defmodule module_name do
        @class_path class_path
        @config config
        
        def create(args \\ %{}, opts \\ []) do
          session_id = opts[:session_id] || DSPex.Utils.ID.generate("session")
          
          call_result = Snakepit.execute_in_session(session_id, "call_dspy", %{
            "module_path" => @class_path,
            "function_name" => "__init__",
            "args" => [],
            "kwargs" => args
          })
          
          case call_result do
            {:ok, %{"success" => true, "instance_id" => instance_id}} ->
              {:ok, {session_id, instance_id}}
            {:ok, %{"success" => false, "error" => error, "traceback" => traceback}} ->
              {:error, "#{@class_path} creation failed: #{error}\n#{traceback}"}
            {:ok, %{"success" => false, "error" => error}} ->
              {:error, "#{@class_path} creation failed: #{error}"}
            error -> error
          end
        end
        
        def execute({session_id, instance_id}, args \\ %{}, opts \\ []) do
          method_name = @config[:execute_method] || "__call__"
          
          call_result = Snakepit.execute_in_session(session_id, "call_dspy", %{
            "module_path" => "stored.#{instance_id}",
            "function_name" => method_name,
            "args" => [],
            "kwargs" => args
          })
          
          case call_result do
            {:ok, %{"success" => true, "result" => result}} ->
              {:ok, result}
            {:ok, %{"success" => false, "error" => error, "traceback" => traceback}} ->
              {:error, "#{@class_path}.#{method_name} failed: #{error}\n#{traceback}"}
            {:ok, %{"success" => false, "error" => error}} ->
              {:error, "#{@class_path}.#{method_name} failed: #{error}"}
            error -> error
          end
        end
        
        # Generate additional methods based on config
        unquote(
          for {method_name, elixir_name} <- (config[:methods] || %{}) do
            quote do
              def unquote(String.to_atom(elixir_name))({session_id, instance_id}, args \\ %{}) do
                call_result = Snakepit.execute_in_session(session_id, "call_dspy", %{
                  "module_path" => "stored.#{instance_id}",
                  "function_name" => unquote(method_name),
                  "args" => [],
                  "kwargs" => args
                })
                
                case call_result do
                  {:ok, %{"success" => true, "result" => result}} -> {:ok, result}
                  {:ok, %{"success" => false, "error" => error}} -> {:error, error}
                  error -> error
                end
              end
            end
          end
        )
      end
    end
  end
  
  def generate_modules_from_schema(schema, target_module \\ DSPex.Auto) do
    """
    Generate Elixir modules dynamically from discovered schema.
    This would be called at compile time or application startup.
    """
    for {class_name, class_info} <- schema do
      module_name = Module.concat(target_module, String.to_atom(class_name))
      class_path = "dspy.#{class_name}"
      
      # Generate module with discovered methods
      methods = class_info["methods"] 
                |> Map.keys() 
                |> Enum.filter(&(&1 != "__init__"))
                |> Map.new(&{&1, String.downcase(&1)})
      
      config = %{methods: methods}
      
      # This would create the module at runtime
      create_dynamic_module(module_name, class_path, config)
    end
  end
  
  defp create_dynamic_module(module_name, class_path, config) do
    # Use Module.create/3 for runtime module generation
    contents = quote do
      @class_path unquote(class_path)
      @config unquote(Macro.escape(config))
      
      def create(args \\ %{}, opts \\ []) do
        # Implementation from defdsyp macro
      end
      
      def execute(ref, args \\ %{}, opts \\ []) do
        # Implementation from defdsyp macro  
      end
    end
    
    Module.create(module_name, contents, Macro.Env.location(__ENV__))
  end
end
```

#### Configuration System

```elixir
# config/dspy_bridge.exs
%{
  # Core modules with custom Elixir wrappers
  "dspy.Predict" => %{
    elixir_module: DSPex.Modules.Predict,
    execute_method: "__call__",
    methods: %{
      "forward" => "forward",
      "reset" => "reset"
    },
    result_transform: &DSPex.ResultTransforms.prediction_result/1
  },
  
  "dspy.ChainOfThought" => %{
    elixir_module: DSPex.Modules.ChainOfThought,
    execute_method: "__call__",
    result_transform: &DSPex.ResultTransforms.cot_result/1
  },
  
  # Optimizers - auto-generated
  "dspy.BootstrapFewShot" => %{
    elixir_module: DSPex.Optimizers.BootstrapFewShot,
    methods: %{
      "compile" => "optimize"
    }
  },
  
  "dspy.MIPROv2" => %{
    elixir_module: DSPex.Optimizers.MIPROv2,
    methods: %{
      "compile" => "optimize"  
    }
  },
  
  # Auto-discover everything else
  auto_discover: [
    "dspy.retrievers",
    "dspy.teleprompt", 
    "dspy.evaluate"
  ]
}
```

### 3. Application Layer Integration

#### Existing Modules Enhanced

```elixir
defmodule DSPex.Modules.Predict do
  @moduledoc "Enhanced Predict module using schema bridge"
  
  use DSPex.Bridge
  
  # This macro call generates the core functionality
  defdsyp __MODULE__.Core, "dspy.Predict", %{
    execute_method: "__call__"
  }
  
  # Enhanced API with error handling and result transformation
  def create(signature, opts \\ []) do
    case __MODULE__.Core.create(%{"signature" => signature}, opts) do
      {:ok, ref} -> {:ok, ref}
      {:error, error} -> 
        Logger.error("Predict creation failed: #{error}")
        {:error, parse_dspy_error(error)}
    end
  end
  
  def execute(ref, inputs, opts \\ []) do
    case __MODULE__.Core.execute(ref, inputs, opts) do
      {:ok, raw_result} -> 
        {:ok, transform_prediction_result(raw_result)}
      {:error, error} ->
        Logger.error("Predict execution failed: #{error}")
        {:error, parse_dspy_error(error)}
    end
  end
  
  defp transform_prediction_result(raw_result) do
    # Transform Python result to Elixir-friendly format
    case raw_result do
      %{"completions" => completions} when is_list(completions) ->
        # Handle DSPy completion format
        %{"prediction_data" => List.first(completions)}
      result when is_map(result) ->
        %{"prediction_data" => result}
      _ ->
        %{"prediction_data" => %{"answer" => to_string(raw_result)}}
    end
  end
  
  defp parse_dspy_error(error_str) do
    # Parse Python traceback for meaningful error messages
    cond do
      String.contains?(error_str, "signature") -> 
        "Invalid signature format"
      String.contains?(error_str, "LM not configured") ->
        "Language model not configured"
      true -> 
        error_str
    end
  end
end
```

#### Auto-Generated Modules

```elixir
# These would be generated automatically at compile time

defmodule DSPex.Auto.MIPRO do
  use DSPex.Bridge
  defdsyp __MODULE__, "dspy.MIPRO"
end

defmodule DSPex.Auto.COPRO do  
  use DSPex.Bridge
  defdsyp __MODULE__, "dspy.COPRO"
end

defmodule DSPex.Auto.ColBERTv2 do
  use DSPex.Bridge  
  defdsyp __MODULE__, "dspy.ColBERTv2"
end

# Usage:
# {:ok, mipro} = DSPex.Auto.MIPRO.create(%{"num_candidates" => 10})
# {:ok, result} = DSPex.Auto.MIPRO.execute(mipro, %{"program" => program, "trainset" => trainset})
```

## Benefits

### 1. Automatic Expansion
- New DSPy classes/methods automatically available via schema discovery
- No manual wrapper creation required
- DSPy updates reflected immediately after schema refresh

### 2. Robust Error Handling
- Python introspection validates calls before execution
- Structured error responses with tracebacks
- Type checking and parameter validation

### 3. Debuggable
- Clear call paths: `Elixir → call_dspy → Python → DSPy`
- Detailed error messages with context
- Traceable execution flow

### 4. Maintainable
- Single generic bridge tool handles all DSPy interactions
- Configuration-driven API customization
- Clear separation between generated and custom code

### 5. Leverages Elixir Strengths
- Metaprogramming for API generation
- Pattern matching for result transformation
- Supervision trees for fault tolerance
- GenServer for schema caching

### 6. Type Safety
- Runtime validation of Python function signatures
- Structured input/output formats
- Compile-time warnings for invalid configurations

## Migration Strategy

### Phase 1: Core Infrastructure (Week 1)
1. Implement `call_dspy` and `discover_dspy_schema` tools
2. Create `DSPex.Schema` GenServer for caching
3. Build basic `defdsyp` macro

### Phase 2: Existing Module Enhancement (Week 2)  
4. Migrate `DSPex.Modules.Predict` to use schema bridge
5. Migrate `DSPex.Modules.ChainOfThought`
6. Test with existing examples

### Phase 3: Auto-Generation (Week 3)
7. Implement dynamic module generation
8. Create configuration system
9. Generate all DSPy optimizer modules

### Phase 4: Advanced Features (Week 4)
10. Add result transformation pipeline
11. Implement compile-time schema validation
12. Create development tools for schema exploration

## Usage Examples

### Basic Usage
```elixir
# Schema discovery (cached)
{:ok, schema} = DSPex.Schema.discover_schema()

# Use existing enhanced modules  
{:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
{:ok, result} = DSPex.Modules.Predict.execute(predictor, %{question: "What is DSPy?"})

# Use auto-generated modules
{:ok, mipro} = DSPex.Auto.MIPRO.create(%{num_candidates: 10})
{:ok, optimized} = DSPex.Auto.MIPRO.execute(mipro, %{program: program, trainset: trainset})
```

### Advanced Configuration
```elixir
# Custom module generation
defmodule MyApp.CustomPredictor do
  use DSPex.Bridge
  
  defdsyp __MODULE__, "dspy.Predict", %{
    execute_method: "__call__",
    methods: %{
      "forward" => "predict_forward",
      "inspect" => "inspect_state"
    },
    result_transform: &MyApp.ResultTransforms.custom_transform/1
  }
end
```

### Development Tools
```elixir
# Explore available DSPy functionality
DSPex.Schema.explore("dspy.retrievers")
# => %{"ColBERTv2" => %{...}, "ChromaRetriever" => %{...}}

# Validate call before execution
DSPex.Bridge.validate_call("dspy.MIPRO", %{num_candidates: "invalid"})
# => {:error, "num_candidates must be integer, got string"}

# Force schema refresh
DSPex.Schema.discover_schema(force_refresh: true)
```

## Risk Mitigation

### Schema Validation
- Schema discovery validates against known DSPy patterns
- Fallback to manual tools if auto-discovery fails
- Version compatibility checking

### Error Recovery
- Graceful degradation if Python introspection fails  
- Detailed logging for debugging bridge issues
- Circuit breaker pattern for repeated failures

### Performance Considerations
- Schema caching reduces discovery overhead
- Lazy module generation only when needed
- Connection pooling for high-throughput scenarios

## Future Enhancements

### Multi-Language Support
- Extend bridge pattern to other Python ML libraries (transformers, sklearn)
- Support for R libraries via similar pattern
- Language-agnostic schema format

### Advanced Introspection
- Type hint extraction for better validation
- Docstring parsing for automatic documentation
- Performance profiling integration

### Development Experience  
- IDE integration for auto-completion
- Schema visualization tools
- Interactive REPL for DSPy exploration

## Conclusion

The Schema-Driven Dynamic Bridge provides a robust, maintainable, and automatically expanding integration between DSPex and DSPy. By leveraging Python introspection and Elixir metaprogramming, we achieve the best of both worlds: the flexibility of dynamic discovery with the safety and performance of compiled interfaces.

This architecture positions DSPex to automatically benefit from DSPy's rapid development while maintaining the reliability and debuggability required for production systems.