# Enhanced Bridge Architecture

## Overview

The enhanced bridge extends Snakepit's base functionality to provide dynamic Python method invocation, object persistence, and framework-specific optimizations. This document explains the architecture and key components.

## Core Components

### 1. EnhancedCommandHandler

The main command handler that extends `BaseCommandHandler` with dynamic capabilities:

```python
class EnhancedCommandHandler(BaseCommandHandler):
    def __init__(self):
        super().__init__()
        self.stored_objects = {}      # Persistent object storage
        self.framework_plugins = {}   # Framework-specific handlers
        self.namespaces = {}         # Loaded Python modules
```

### 2. Framework Plugins

Specialized handlers for different Python frameworks:

#### DSPyPlugin
- Handles DSPy-specific configuration (especially Gemini)
- Serializes Prediction objects for easy access
- Manages LM configuration persistence

```python
class DSPyPlugin(FrameworkPlugin):
    def configure(self, config):
        if config.get("provider") == "google":
            return self._configure_gemini(config)
```

#### Other Plugins
- **TransformersPlugin**: Handles HuggingFace transformers
- **PandasPlugin**: Optimizes DataFrame serialization

### 3. Dynamic Method Invocation

The `handle_call` method enables calling any Python method:

```python
# Examples of supported calls:
"dspy.Predict"                    # Create instance
"stored.predictor.__call__"       # Call stored object
"dspy.settings.lm"               # Access attributes
"numpy.array"                    # Call any importable module
```

### 4. Object Storage and Resolution

#### Storage Mechanism

Objects are stored with unique IDs:

```python
self.stored_objects["default_lm"] = lm_instance
self.stored_objects["predictor_1"] = dspy.Predict(...)
```

#### Automatic Resolution

String references like `"stored.object_id"` are automatically resolved:

```python
def _resolve_stored_references(self, data):
    # Converts "stored.default_lm" -> actual LM object
    # Works recursively on nested structures
```

## Message Flow

### 1. Standard Command Flow

```
Elixir                          Python
  |                               |
  |------ Command Request ------> |
  |         (JSON/MP)             |
  |                               |
  |     EnhancedCommandHandler    |
  |          processes             |
  |                               |
  | <----- Command Response ----- |
  |         (JSON/MP)             |
```

### 2. Dynamic Call Flow

```
Elixir: Python.call(pid, "dspy.Predict", %{signature: "q->a"})
           |
           v
Python: handle_call receives:
        - target: "dspy.Predict"
        - kwargs: {"signature": "q->a"}
           |
           v
        _execute_dynamic_call:
        - Imports dspy if needed
        - Creates Predict instance
        - Stores if requested
           |
           v
        Returns serialized result
```

## Key Features

### 1. Stored Object References

Enables persistent objects across calls:

```elixir
# Elixir side
{:ok, _} = Python.call(pid, "dspy.Predict", 
  %{signature: "question -> answer"}, 
  store_as: "qa_predictor")

# Later use the stored object
{:ok, result} = Python.call(pid, "stored.qa_predictor.__call__", 
  %{question: "What is DSPy?"})
```

### 2. Smart Serialization

Framework-aware serialization:

```python
# DSPy Prediction objects are specially handled
{
    "type": "Prediction",
    "prediction_data": {
        "answer": "42",
        "reasoning": "..."
    }
}
```

### 3. Backward Compatibility

Legacy commands still work:

```python
# Old style
{"command": "configure_lm", "provider": "google", ...}

# Translates to new style
{"target": "dspy.configure", "kwargs": {...}}
```

## Configuration Flow

### 1. LM Configuration

```python
# 1. DSPyPlugin handles provider-specific setup
if provider == "google":
    lm = dspy.LM(f"gemini/{model}", api_key=api_key)
    
# 2. Configure DSPy
dspy.configure(lm=lm)

# 3. Store for persistence
self.stored_objects["default_lm"] = lm
```

### 2. Module Creation

```python
# 1. Create module
predictor = dspy.Predict(signature)

# 2. Store with ID
if store_as:
    self.stored_objects[store_as] = predictor
    
# 3. Return serialized info
return {"stored_as": store_as, ...}
```

## Error Handling

### 1. Missing Stored Objects

```python
if object_id not in self.stored_objects:
    raise ValueError(f"Stored object '{object_id}' not found")
```

### 2. Import Failures

```python
try:
    namespace = importlib.import_module(namespace_name)
except ImportError:
    raise ValueError(f"Cannot import namespace: {namespace_name}")
```

### 3. Execution Errors

All exceptions are caught and returned with full context:

```python
{
    "status": "error",
    "error": str(e),
    "traceback": traceback.format_exc()
}
```

## Best Practices

### 1. Object Lifecycle

```python
# Create and store
Python.call(pid, "dspy.ChainOfThought", 
  %{signature: "question -> answer"}, 
  store_as: "cot_module")

# Use multiple times
Python.call(pid, "stored.cot_module.__call__", %{question: "..."})

# Clean up when done
Python.call(pid, "delete_stored", %{id: "cot_module"})
```

### 2. Configuration Management

```python
# Configure once at startup
{:ok, _} = DSPex.LM.configure(model, api_key: key)

# All subsequent operations use the configured LM
{:ok, pred} = DSPex.Modules.Predict.create("q -> a")
```

### 3. Error Recovery

```elixir
case Python.call(pid, target, args) do
  {:ok, result} -> 
    process_result(result)
  {:error, %{"error" => msg, "traceback" => trace}} ->
    Logger.error("Python error: #{msg}\n#{trace}")
    {:error, msg}
end
```

## Performance Considerations

### 1. Object Reuse

Stored objects avoid recreation overhead:

```python
# Bad: Creates new predictor each time
Python.call(pid, "dspy.Predict", %{signature: "q->a"})

# Good: Reuse stored predictor
Python.call(pid, "stored.qa_predictor.__call__", %{question: q})
```

### 2. Serialization Limits

Large objects are truncated:

```python
# Lists limited to first 10 items
# Strings limited to 500 characters
# Attributes limited to 10 non-private fields
```

### 3. Framework Loading

Frameworks are loaded once and cached:

```python
self.namespaces["dspy"] = dspy  # Cached after first import
```

## Extending the Bridge

### 1. Adding a New Framework Plugin

```python
class MyFrameworkPlugin(FrameworkPlugin):
    def name(self):
        return "myframework"
        
    def load(self):
        import myframework
        return myframework
        
    def serialize_result(self, obj):
        # Custom serialization logic
        if isinstance(obj, myframework.SpecialType):
            return {"type": "SpecialType", ...}
```

### 2. Adding New Commands

```python
def handle_my_command(self, args):
    # Custom command logic
    return {"status": "ok", "result": ...}

# Register in _register_commands
self.register_command("my_command", self.handle_my_command)
```

## Troubleshooting

### Common Issues

1. **"No LM is loaded"** - Stored reference not resolved
2. **"Module not found"** - Framework not installed in Python env
3. **"Stored object not found"** - Object ID mismatch
4. **Serialization errors** - Complex objects need custom handling

### Debug Mode

Enable debug output:

```python
# Add to enhanced_bridge.py
DEBUG = os.environ.get('BRIDGE_DEBUG', '').lower() == 'true'

if DEBUG:
    print(f"[DEBUG] {message}", file=sys.stderr)
```

Run with:
```bash
BRIDGE_DEBUG=true mix run script.exs
```