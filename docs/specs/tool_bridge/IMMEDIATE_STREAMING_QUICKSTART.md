# Immediate Streaming Implementation Quickstart

## Overview

This document provides the minimal steps needed to get DSPy streaming working TODAY using the existing Snakepit gRPC infrastructure. No new infrastructure needed - just connect the dots.

## Current Blockers & Solutions

### Blocker 1: gRPC Adapter Not Loading
**Issue**: The GRPCPython adapter has conditional compilation that fails in DSPex context.

**Solution**: The gRPC adapter IS loading successfully! The issue was misdiagnosed. The adapter works when:
1. gRPC dependencies are available (they are)
2. Python has gRPC bridge installed (it does)
3. The adapter is properly configured (it is in the example)

### Blocker 2: No DSPy Streaming Commands
**Issue**: The Python bridge doesn't have DSPy-specific streaming commands.

**Solution**: Add streaming commands to the existing enhanced bridge.

## Step 1: Add DSPy Streaming to Enhanced Bridge (30 minutes)

```python
# File: snakepit/priv/python/enhanced_bridge.py
# Add to the EnhancedCommandHandler class

def _register_streaming_commands(self):
    """Register DSPy streaming commands"""
    if hasattr(self, 'supports_streaming') and self.supports_streaming():
        self.streaming_commands = {
            'stream_predict_batch': self._stream_predict_batch,
            'stream_chain_of_thought': self._stream_chain_of_thought,
            'stream_react_steps': self._stream_react_steps
        }
        
def process_stream_command(self, command, args):
    """Process streaming commands"""
    if command in self.streaming_commands:
        yield from self.streaming_commands[command](args)
    else:
        yield {"error": f"Unknown streaming command: {command}"}
        
def _stream_predict_batch(self, args):
    """Stream predictions for a batch of inputs"""
    import dspy
    
    signature = args.get('signature', 'input -> output')
    items = args.get('items', [])
    
    # Create predictor
    predictor = dspy.Predict(signature)
    
    # Stream results
    for i, item in enumerate(items):
        try:
            prediction = predictor(**item)
            yield {
                'type': 'prediction',
                'index': i,
                'total': len(items),
                'input': item,
                'output': prediction.toDict() if hasattr(prediction, 'toDict') else str(prediction),
                'progress': (i + 1) / len(items)
            }
        except Exception as e:
            yield {
                'type': 'error',
                'index': i,
                'error': str(e)
            }
    
    yield {'type': 'complete', 'total': len(items)}

def _stream_chain_of_thought(self, args):
    """Stream reasoning steps from Chain of Thought"""
    import dspy
    
    signature = args.get('signature', 'question -> answer')
    question = args.get('question', '')
    
    # For now, simulate streaming by yielding intermediate steps
    # In production, hook into DSPy's internal reasoning
    yield {'type': 'thinking', 'status': 'Analyzing question...'}
    
    cot = dspy.ChainOfThought(signature)
    
    yield {'type': 'thinking', 'status': 'Generating reasoning...'}
    
    result = cot(question=question)
    
    # Yield reasoning steps (if available)
    if hasattr(result, 'reasoning'):
        reasoning_lines = result.reasoning.split('\n')
        for i, line in enumerate(reasoning_lines):
            if line.strip():
                yield {
                    'type': 'reasoning_step',
                    'step': i + 1,
                    'content': line.strip()
                }
    
    # Final answer
    yield {
        'type': 'final_answer',
        'answer': result.answer if hasattr(result, 'answer') else str(result),
        'full_reasoning': result.reasoning if hasattr(result, 'reasoning') else None
    }
```

## Step 2: Update DSPex to Use Streaming (20 minutes)

```elixir
# File: lib/dspex/modules/predict.ex
# Add streaming version

defmodule DSPex.Modules.Predict do
  # ... existing code ...
  
  @doc """
  Stream predictions for a batch of inputs
  """
  def stream_batch(signature, items, callback, opts \\ []) when is_list(items) do
    # Use gRPC pool for streaming
    opts = Keyword.put(opts, :adapter, Snakepit.Adapters.GRPCPython)
    
    Snakepit.execute_stream(
      "stream_predict_batch",
      %{
        signature: DSPex.Signatures.Parser.to_string(signature),
        items: items
      },
      fn chunk ->
        case chunk["type"] do
          "prediction" ->
            callback.({:prediction, chunk["index"], chunk["output"], chunk["progress"]})
            
          "error" ->
            callback.({:error, chunk["index"], chunk["error"]})
            
          "complete" ->
            callback.({:complete, chunk["total"]})
            
          _ ->
            callback.({:chunk, chunk})
        end
      end,
      opts
    )
  end
end
```

## Step 3: Create Working Example (10 minutes)

```elixir
# File: examples/dspy/working_streaming_example.exs

# Load default configuration (same pattern as other examples)
config_path = Path.join(__DIR__, "../config.exs")
config = Code.eval_file(config_path) |> elem(0)

# Configure DSPex with default provider (Gemini)
{:ok, _} = DSPex.LM.configure(config.model, api_key: config.api_key)

# Ensure gRPC adapter is available
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)

# Start the application
{:ok, _} = Application.ensure_all_started(:snakepit)

# Create test data
items = [
  %{text: "Paris is the capital of"},
  %{text: "The largest planet is"},
  %{text: "Water boils at"},
  %{text: "The speed of light is"}
]

# Stream predictions
IO.puts("Starting streaming predictions...\n")

DSPex.Modules.Predict.stream_batch(
  "text -> completion",
  items,
  fn
    {:prediction, index, output, progress} ->
      IO.puts("[#{index + 1}/#{length(items)}] Completed: #{output["completion"]}")
      IO.puts("Progress: #{round(progress * 100)}%\n")
      
    {:error, index, error} ->
      IO.puts("[#{index + 1}] Error: #{error}\n")
      
    {:complete, total} ->
      IO.puts("✅ Streaming complete! Processed #{total} items.")
  end
)
```

## Step 4: Test the Implementation (5 minutes)

```bash
# 1. Ensure Python dependencies
cd snakepit/priv/python
pip install dspy-ai

# 2. Run the streaming example
cd ../../../  # Back to project root
mix run examples/dspy/working_streaming_example.exs
```

## Expected Output

```
Starting streaming predictions...

[1/4] Completed: France
Progress: 25%

[2/4] Completed: Jupiter
Progress: 50%

[3/4] Completed: 100 degrees Celsius
Progress: 75%

[4/4] Completed: 299,792,458 meters per second
Progress: 100%

✅ Streaming complete! Processed 4 items.
```

## Troubleshooting

### If gRPC adapter fails to load:
```elixir
# Check if modules are available
IO.inspect(Code.ensure_loaded?(GRPC.Channel))
IO.inspect(Code.ensure_loaded?(Protobuf))

# These should return true
```

### If streaming returns "not supported":
```elixir
# Verify adapter supports streaming
adapter = Snakepit.Adapters.GRPCPython
IO.inspect(function_exported?(adapter, :uses_grpc?, 0))
IO.inspect(adapter.uses_grpc?())

# Both should be true
```

### If Python bridge fails:
```bash
# Check Python gRPC installation
cd snakepit/priv/python
python -c "import grpc; print('gRPC available')"
```

## Next Steps

Once basic streaming works:

1. **Add more streaming operations**:
   - Stream optimization progress
   - Stream ReAct tool calls
   - Stream dataset processing

2. **Optimize performance**:
   - Batch size tuning
   - Concurrent streams
   - Memory management

3. **Add telemetry**:
   - Stream latency metrics
   - Throughput monitoring
   - Error tracking

## Why This Works

1. **Snakepit already has streaming** - We're just using it
2. **gRPC is already configured** - The example proves it works
3. **Python bridge is extensible** - Just add streaming methods
4. **No new dependencies** - Everything needed is already there

## Summary

Getting DSPy streaming working requires:
- ✅ 30 minutes to add streaming methods to Python bridge
- ✅ 20 minutes to add streaming API to DSPex
- ✅ 10 minutes to create and test example
- ✅ 0 new infrastructure or dependencies

Total time: ~1 hour to working streaming DSPy operations!