# Debugging DSPy Integration Issues

This guide covers common issues when integrating DSPy with DSPex through the enhanced bridge, based on real debugging experiences.

## Common Error: "No LM is loaded"

### Symptoms
```
Error: No LM is loaded.
Expected an instance of `dsp.BaseLM` but got <str>.
```

### Root Cause
DSPy receives a string reference like `"stored.default_lm"` instead of the actual language model object.

### Solution
Ensure the enhanced bridge's `_resolve_stored_references` method is called on all arguments:

```python
# In enhanced_bridge.py handle_call method
call_args = self._resolve_stored_references(call_args)
call_kwargs = self._resolve_stored_references(call_kwargs)
```

## Debugging Workflow

### 1. Add Strategic Logging

```python
# In handle_call
print(f"[DEBUG] Original kwargs: {call_kwargs}", file=sys.stderr)
call_kwargs = self._resolve_stored_references(call_kwargs)
print(f"[DEBUG] Resolved kwargs: {call_kwargs}", file=sys.stderr)
```

### 2. Check DSPy Configuration State

```python
# Add to your bridge for debugging
import dspy
print(f"[DEBUG] dspy.settings.lm: {dspy.settings.lm}", file=sys.stderr)
print(f"[DEBUG] dspy.settings.lm type: {type(dspy.settings.lm)}", file=sys.stderr)
```

### 3. Verify Stored Objects

```python
# List all stored objects
print(f"[DEBUG] Stored objects: {list(self.stored_objects.keys())}", file=sys.stderr)

# Check specific object
if "default_lm" in self.stored_objects:
    lm = self.stored_objects["default_lm"]
    print(f"[DEBUG] default_lm type: {type(lm)}", file=sys.stderr)
```

## Configuration Flow Verification

### Correct Flow

1. **LM Creation and Storage**
   ```python
   lm = dspy.LM("gemini/gemini-2.0-flash-lite", api_key=api_key)
   dspy.configure(lm=lm)
   self.stored_objects["default_lm"] = lm
   ```

2. **Reference Resolution**
   ```python
   # Elixir sends: {"lm": "stored.default_lm"}
   # Bridge resolves to: {"lm": <dspy.LM instance>}
   ```

3. **DSPy Receives Correct Object**
   ```python
   # dspy.settings.lm is now the actual LM instance
   ```

### Common Mistakes

1. **Not Storing the LM Object**
   ```python
   # WRONG: Only configuring without storing
   dspy.configure(lm=lm)
   
   # RIGHT: Configure AND store
   dspy.configure(lm=lm)
   self.stored_objects["default_lm"] = lm
   ```

2. **Wrong Storage Key**
   ```python
   # Storing as "test_lm" but referencing "default_lm"
   self.stored_objects["test_lm"] = lm
   # Later: "stored.default_lm" fails
   ```

3. **Not Resolving in All Paths**
   ```python
   # Some code paths might bypass resolution
   if special_case:
       # Forgot to resolve here!
       result = execute(args, kwargs)
   ```

## Testing Your Fix

### 1. Create a Test Script

```elixir
# test_lm_config.exs
{:ok, _} = DSPex.LM.configure("gemini-2.0-flash-lite", api_key: api_key)
{:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
{:ok, result} = DSPex.Modules.Predict.execute(predictor, %{question: "Test"})
IO.inspect(result)
```

### 2. Run with Verbose Logging

```bash
PYTHONUNBUFFERED=1 elixir test_lm_config.exs 2>&1 | grep DEBUG
```

### 3. Check Each Step

- LM configuration successful?
- Object stored with correct ID?
- Reference resolved when used?
- DSPy receives LM instance?

## Advanced Debugging

### 1. Trace Object Lifecycle

```python
class TrackedLM:
    def __init__(self, lm):
        self.lm = lm
        print(f"[TRACE] LM created: {id(self)}", file=sys.stderr)
    
    def __getattr__(self, name):
        print(f"[TRACE] LM.{name} accessed", file=sys.stderr)
        return getattr(self.lm, name)
```

### 2. Monitor Bridge Communication

```python
# In handle_call
print(f"[BRIDGE] Call: {target}", file=sys.stderr)
print(f"[BRIDGE] Args: {call_args}", file=sys.stderr)
print(f"[BRIDGE] Kwargs keys: {list(call_kwargs.keys())}", file=sys.stderr)
```

### 3. Validate Serialization

```python
# Check what gets serialized back to Elixir
result = self._smart_serialize(result, target)
print(f"[SERIAL] Result type: {result.get('type')}", file=sys.stderr)
```

## Prevention Tips

1. **Always Test Configuration First**
   - Run a simple predict after configuring LM
   - Verify it works before complex operations

2. **Use Consistent Naming**
   - Stick to "default_lm" for the main LM
   - Document any additional stored objects

3. **Add Assertions**
   ```python
   # In DSPy operations
   assert hasattr(dspy.settings, 'lm'), "No LM configured"
   assert dspy.settings.lm is not None, "LM is None"
   assert not isinstance(dspy.settings.lm, str), "LM is string, not object"
   ```

4. **Create Helper Functions**
   ```elixir
   # In DSPex
   def ensure_lm_configured do
     case Python.call(pid, "dspy.settings.__dict__", %{}) do
       {:ok, settings} when is_map_key(settings, "lm") -> :ok
       _ -> {:error, "LM not configured"}
     end
   end
   ```

## Related Issues

### Module Storage
The same resolution mechanism applies to storing DSPy modules:
```python
self.stored_objects["cot_module"] = dspy.ChainOfThought("question -> answer")
# Reference as "stored.cot_module"
```

### Tool References
For ReAct tools:
```python
self.stored_objects["search_tool"] = search_function
# Reference as "stored.search_tool"
```

## Quick Checklist

When debugging "No LM is loaded" or similar issues:

- [ ] Is the LM created with correct model name?
- [ ] Is the LM stored in `stored_objects`?
- [ ] Is the storage key correct?
- [ ] Is `_resolve_stored_references` called?
- [ ] Does it resolve both args and kwargs?
- [ ] Is the resolution recursive for nested structures?
- [ ] Are there any code paths that bypass resolution?
- [ ] Is DSPy's settings.lm the actual object after resolution?

## Getting Help

If issues persist:

1. Enable all debug logging
2. Create a minimal reproduction script
3. Check the stored objects at each step
4. Verify the bridge version matches this documentation
5. Look for any custom modifications to the bridge