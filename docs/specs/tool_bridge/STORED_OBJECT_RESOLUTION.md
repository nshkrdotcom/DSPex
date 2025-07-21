# Stored Object Resolution in Enhanced Bridge

## Overview

The enhanced bridge provides a mechanism for storing Python objects and referencing them later using string identifiers like `"stored.object_id"`. This is crucial for DSPy integration where objects need to persist across multiple bridge calls.

## The Problem We Solved

When configuring DSPy with a language model (LM), the enhanced bridge stores the LM object with an ID like `"default_lm"`. However, when DSPy modules try to use this LM, they receive the string `"stored.default_lm"` instead of the actual LM object, causing errors like "No LM is loaded".

## How Stored Object Resolution Works

### 1. Object Storage

When an object needs to persist across calls:

```python
# In enhanced_bridge.py
self.stored_objects["default_lm"] = lm_instance
```

### 2. String References

Elixir sends references as strings:

```elixir
# In Elixir
%{lm: "stored.default_lm"}
```

### 3. Automatic Resolution

The `_resolve_stored_references` method recursively resolves these strings:

```python
def _resolve_stored_references(self, data):
    if isinstance(data, str):
        if data.startswith("stored."):
            parts = data.split(".", 1)
            if len(parts) == 2:
                object_id = parts[1]
                if object_id in self.stored_objects:
                    return self.stored_objects[object_id]
```

### 4. Resolution Points

The resolution happens at two critical points in `handle_call`:

```python
# Resolve references in arguments BEFORE execution
call_args = self._resolve_stored_references(call_args)
call_kwargs = self._resolve_stored_references(call_kwargs)
```

## Key Implementation Details

### Recursive Resolution

The method handles nested data structures:

- **Strings**: Checks if they match `"stored.object_id"` pattern
- **Dictionaries**: Recursively resolves all values
- **Lists**: Recursively resolves all items
- **Tuples**: Preserves immutability while resolving

### Error Handling

If a stored object is not found:

```python
raise ValueError(f"Stored object '{object_id}' not found")
```

## Common Use Cases

### 1. Language Model Configuration

```python
# Python side stores the LM
lm = dspy.LM("gemini/gemini-2.0-flash-lite", api_key=api_key)
dspy.configure(lm=lm)
self.stored_objects["default_lm"] = lm

# Elixir references it
{:ok, _} = Python.call(pid, "dspy.configure", %{lm: "stored.default_lm"})
```

### 2. Module Persistence

```python
# Store a DSPy module
predictor = dspy.Predict("question -> answer")
self.stored_objects["qa_predictor"] = predictor

# Use it later
Python.call(pid, "stored.qa_predictor.__call__", %{question: "What is 2+2?"})
```

### 3. Complex Object Graphs

The resolution works with nested structures:

```python
config = {
    "primary_lm": "stored.default_lm",
    "fallback_lm": "stored.backup_lm",
    "tools": ["stored.search_tool", "stored.calc_tool"]
}
# All stored references are resolved automatically
```

## Debugging Tips

### 1. Check Stored Objects

Add logging to see what's stored:

```python
print(f"Stored objects: {list(self.stored_objects.keys())}", file=sys.stderr)
```

### 2. Trace Resolution

Add logging in `_resolve_stored_references`:

```python
if data.startswith("stored."):
    print(f"Resolving: {data} -> {type(self.stored_objects.get(object_id))}", file=sys.stderr)
```

### 3. Verify DSPy State

Check what DSPy actually receives:

```python
print(f"dspy.settings.lm type: {type(dspy.settings.lm)}", file=sys.stderr)
print(f"dspy.settings.lm value: {dspy.settings.lm}", file=sys.stderr)
```

## Best Practices

1. **Consistent Naming**: Use descriptive IDs like `"default_lm"`, `"search_tool"`
2. **Lifecycle Management**: Clear stored objects when done with `handle_clear_session`
3. **Error Handling**: Always handle the case where a stored object might not exist
4. **Type Safety**: Document what type of object each ID should contain

## Example: Complete LM Configuration Flow

```python
# 1. Configure DSPy with LM
def handle_configure_lm(self, args):
    lm = dspy.LM(f"gemini/{model}", api_key=api_key)
    dspy.configure(lm=lm)
    
    # Store for later reference
    self.stored_objects["default_lm"] = lm
    
    # Also store in dspy settings
    self.stored_objects["test_lm"] = lm  # Alternative name
    
    return {"status": "ok", "message": "LM configured"}

# 2. Later call uses stored reference
def some_dspy_operation(self, args):
    # This will automatically resolve "stored.default_lm" to the actual LM object
    result = self.handle_call({
        "target": "dspy.Predict",
        "kwargs": {"signature": "question -> answer", "lm": "stored.default_lm"}
    })
```

## Related Documentation

- [PYTHON_TOOL_BRIDGE.md](./PYTHON_TOOL_BRIDGE.md) - Overall bridge architecture
- [PYTHON_TOOL_BRIDGE_COMMON.md](./PYTHON_TOOL_BRIDGE_COMMON.md) - Protocol-specific implementations