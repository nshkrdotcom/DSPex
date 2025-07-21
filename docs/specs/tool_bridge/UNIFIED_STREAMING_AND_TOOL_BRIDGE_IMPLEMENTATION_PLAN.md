# Unified Streaming and Tool Bridge Implementation Plan

## Executive Summary

This document outlines a phased implementation plan that delivers streaming DSPy operations from Python to Elixir while laying the groundwork for the tool bridge. Based on analysis of the existing infrastructure, we prioritize immediate value delivery through streaming, followed by compositional patterns, and finally selective tool bridge implementation where needed.

## Current State Assessment

### What's Working
- ✅ **gRPC streaming infrastructure**: Fully implemented in Snakepit
- ✅ **Python gRPC bridge**: Complete with example streaming handlers
- ✅ **Enhanced bridge**: Working for non-streaming DSPy operations
- ✅ **Session management**: Functional across all protocols

### What's Missing
- ❌ **DSPy streaming integration**: No streaming DSPy operations implemented
- ❌ **DSPex streaming API**: No `execute_stream` methods in DSPex modules
- ❌ **Tool bridge**: Remains unimplemented with placeholder code
- ❌ **Compositional framework**: No native composition support

## Implementation Philosophy

Based on the compositional insights and existing infrastructure, we adopt a **"Streaming First, Composition Second, Bridge Last"** approach:

1. **Leverage existing infrastructure** - Use Snakepit's streaming immediately
2. **Compositional over RPC** - Prefer in-language composition to cross-language calls
3. **Selective bridging** - Implement tool bridge only where truly needed
4. **Progressive enhancement** - Each phase builds on the previous

## Phase 1: DSPy Streaming Integration (Week 1-2)

### Objective
Enable streaming DSPy operations from Python to Elixir using existing gRPC infrastructure.

### 1.1 Python DSPy Streaming Handler

```python
# File: snakepit/priv/python/snakepit_bridge/adapters/dspy_streaming.py

import dspy
from typing import Iterator, Dict, Any
import asyncio

class DSPyStreamingHandler:
    """Handler for streaming DSPy operations"""
    
    def __init__(self):
        self.streaming_commands = {
            "stream_chain_of_thought": self._stream_cot,
            "stream_react": self._stream_react,
            "stream_batch_predict": self._stream_batch_predict,
            "stream_optimization": self._stream_optimization
        }
        
    def process_stream_command(self, command: str, args: Dict[str, Any]) -> Iterator[Dict[str, Any]]:
        """Main entry point for streaming commands"""
        if command in self.streaming_commands:
            yield from self.streaming_commands[command](args)
        else:
            yield {"error": f"Unknown streaming command: {command}"}
            
    def _stream_cot(self, args: Dict[str, Any]) -> Iterator[Dict[str, Any]]:
        """Stream Chain of Thought reasoning steps"""
        signature = args.get("signature", "question -> answer")
        question = args.get("question")
        
        # Create module
        cot = dspy.ChainOfThought(signature)
        
        # Hook into reasoning process
        reasoning_steps = []
        
        def reasoning_callback(step):
            reasoning_steps.append(step)
            # Yield intermediate reasoning
            return {"type": "reasoning_step", "step": step, "index": len(reasoning_steps)}
        
        # Execute with callback
        with dspy.callbacks.reasoning_stream(reasoning_callback):
            result = cot(question=question)
            
        # Yield final result
        yield {
            "type": "final_result",
            "answer": result.answer,
            "reasoning": result.reasoning,
            "total_steps": len(reasoning_steps)
        }
        
    def _stream_batch_predict(self, args: Dict[str, Any]) -> Iterator[Dict[str, Any]]:
        """Stream results for batch prediction"""
        signature = args.get("signature")
        items = args.get("items", [])
        
        predictor = dspy.Predict(signature)
        
        for i, item in enumerate(items):
            try:
                result = predictor(**item)
                yield {
                    "type": "item_complete",
                    "index": i,
                    "input": item,
                    "output": result.toDict(),
                    "progress": (i + 1) / len(items)
                }
            except Exception as e:
                yield {
                    "type": "item_error",
                    "index": i,
                    "input": item,
                    "error": str(e)
                }
                
        yield {"type": "batch_complete", "total": len(items)}
```

### 1.2 DSPex Streaming API

```elixir
# File: lib/dspex/modules/streaming.ex

defmodule DSPex.Modules.Streaming do
  @moduledoc """
  Streaming implementations of DSPy modules
  """
  
  alias DSPex.Python.Bridge
  
  @doc """
  Stream Chain of Thought reasoning steps
  """
  def stream_chain_of_thought(signature, question, callback) do
    Bridge.execute_stream(
      "stream_chain_of_thought",
      %{signature: signature, question: question},
      fn chunk ->
        case chunk["type"] do
          "reasoning_step" ->
            callback.({:reasoning, chunk["step"], chunk["index"]})
            
          "final_result" ->
            callback.({:complete, %{
              answer: chunk["answer"],
              reasoning: chunk["reasoning"],
              steps: chunk["total_steps"]
            }})
            
          _ ->
            callback.({:unknown, chunk})
        end
      end
    )
  end
  
  @doc """
  Stream batch predictions with progress
  """
  def stream_batch_predict(signature, items, callback) do
    Bridge.execute_stream(
      "stream_batch_predict", 
      %{signature: signature, items: items},
      fn chunk ->
        case chunk["type"] do
          "item_complete" ->
            callback.({:item, chunk["index"], chunk["output"], chunk["progress"]})
            
          "item_error" ->
            callback.({:error, chunk["index"], chunk["error"]})
            
          "batch_complete" ->
            callback.({:complete, chunk["total"]})
            
          _ ->
            callback.({:unknown, chunk})
        end
      end
    )
  end
end
```

### 1.3 Update Python Bridge Configuration

```elixir
# File: lib/dspex/python/bridge.ex

defmodule DSPex.Python.Bridge do
  # Add streaming support
  def execute_stream(command, args, callback, opts \\ []) do
    pool = Keyword.get(opts, :pool, get_pool(:streaming))
    timeout = Keyword.get(opts, :timeout, 300_000)  # 5 minutes for streaming
    
    Snakepit.execute_stream(command, args, callback, 
      pool: pool,
      timeout: timeout
    )
  end
  
  defp get_pool(:streaming), do: :dspex_grpc_pool
  defp get_pool(_), do: :dspex_pool
end
```

## Phase 2: Compositional Framework (Week 3-4)

### Objective
Implement compositional patterns to reduce the need for cross-language tool calls.

### 2.1 DSPex Composer

```elixir
# File: lib/dspex/composer.ex

defmodule DSPex.Composer do
  @moduledoc """
  Compositional framework for building complex DSPy pipelines
  """
  
  defstruct [:session_id, :pipelines, :state]
  
  alias DSPex.Python.Bridge
  
  def new(opts \\ []) do
    session_id = generate_session_id()
    
    # Initialize Python composer
    {:ok, _} = Bridge.call("composer.initialize", %{
      session_id: session_id,
      config: Keyword.get(opts, :config, %{})
    })
    
    %__MODULE__{
      session_id: session_id,
      pipelines: %{},
      state: :ready
    }
  end
  
  def pipeline(composer, name, steps) when is_list(steps) do
    # Convert Elixir pipeline definition to Python
    python_steps = Enum.map(steps, &convert_step/1)
    
    {:ok, _} = Bridge.call("composer.create_pipeline", %{
      session_id: composer.session_id,
      name: name,
      steps: python_steps
    })
    
    %{composer | pipelines: Map.put(composer.pipelines, name, steps)}
  end
  
  def stream(composer, pipeline_name, input, callback) do
    """Execute pipeline with streaming results"""
    Bridge.execute_stream(
      "composer.stream_pipeline",
      %{
        session_id: composer.session_id,
        pipeline: pipeline_name,
        input: input
      },
      fn chunk ->
        case chunk["type"] do
          "step_complete" ->
            callback.({:step, chunk["step_name"], chunk["result"]})
            
          "branch_taken" ->
            callback.({:branch, chunk["condition"], chunk["branch"]})
            
          "pipeline_complete" ->
            callback.({:complete, chunk["result"]})
            
          "error" ->
            callback.({:error, chunk["step"], chunk["message"]})
        end
      end
    )
  end
  
  defp convert_step(%{type: :predict} = step) do
    %{
      "type" => "module",
      "class" => "Predict",
      "signature" => step.signature,
      "config" => Map.get(step, :config, %{})
    }
  end
  
  defp convert_step(%{type: :branch} = step) do
    %{
      "type" => "branch",
      "condition" => serialize_condition(step.condition),
      "true_branch" => step.true_branch,
      "false_branch" => step.false_branch
    }
  end
  
  defp convert_step(%{type: :parallel} = step) do
    %{
      "type" => "parallel",
      "branches" => step.branches,
      "aggregator" => serialize_aggregator(step.aggregator)
    }
  end
end
```

### 2.2 Python Compositional Engine

```python
# File: snakepit/priv/python/snakepit_bridge/composer.py

class DSPyComposer:
    """Compositional engine for complex DSPy workflows"""
    
    def __init__(self, session_id: str, config: dict):
        self.session_id = session_id
        self.config = config
        self.pipelines = {}
        self.modules = {}
        self.state = {}
        
    def create_pipeline(self, name: str, steps: List[dict]):
        """Create a reusable pipeline"""
        pipeline = []
        for step in steps:
            if step["type"] == "module":
                module = self._create_module(step)
                pipeline.append(("module", module))
            elif step["type"] == "branch":
                pipeline.append(("branch", step))
            elif step["type"] == "parallel":
                pipeline.append(("parallel", step))
                
        self.pipelines[name] = pipeline
        return {"status": "created", "name": name}
        
    def stream_pipeline(self, pipeline_name: str, input_data: dict):
        """Execute pipeline with streaming results"""
        pipeline = self.pipelines[pipeline_name]
        current_data = input_data
        
        for i, (step_type, step) in enumerate(pipeline):
            step_name = f"step_{i}_{step_type}"
            
            try:
                if step_type == "module":
                    # Execute DSPy module
                    result = step(**current_data)
                    current_data = result.toDict()
                    yield {
                        "type": "step_complete",
                        "step_name": step_name,
                        "result": current_data
                    }
                    
                elif step_type == "branch":
                    # Evaluate condition and branch
                    condition_result = self._evaluate_condition(
                        step["condition"], 
                        current_data
                    )
                    branch = step["true_branch"] if condition_result else step["false_branch"]
                    
                    yield {
                        "type": "branch_taken",
                        "condition": step["condition"],
                        "branch": branch,
                        "result": condition_result
                    }
                    
                    # Execute branch pipeline
                    for result in self.stream_pipeline(branch, current_data):
                        yield result
                        
                elif step_type == "parallel":
                    # Execute branches in parallel
                    results = []
                    for branch_name in step["branches"]:
                        # In real implementation, use asyncio
                        branch_result = list(self.stream_pipeline(branch_name, current_data))
                        results.append(branch_result[-1]["result"])  # Get final result
                        
                    # Aggregate results
                    current_data = self._aggregate_results(step["aggregator"], results)
                    yield {
                        "type": "step_complete",
                        "step_name": step_name,
                        "result": current_data
                    }
                    
            except Exception as e:
                yield {
                    "type": "error",
                    "step": step_name,
                    "message": str(e),
                    "traceback": traceback.format_exc()
                }
                raise
                
        yield {
            "type": "pipeline_complete",
            "result": current_data
        }
```

## Phase 3: Selective Tool Bridge (Week 5-6)

### Objective
Implement lightweight tool bridge only for external tool integration needs.

### 3.1 Minimal Tool Registry

```elixir
# File: lib/dspex/tools/registry.ex

defmodule DSPex.Tools.Registry do
  @moduledoc """
  Lightweight tool registry for selective bridging
  """
  
  use GenServer
  
  defstruct [:tools, :sessions]
  
  def register_batch(session_id, tools) do
    """Register tools for a specific session"""
    GenServer.call(__MODULE__, {:register_batch, session_id, tools})
  end
  
  def handle_call({:register_batch, session_id, tools}, _from, state) do
    # Only register tools that need bridge functionality
    bridged_tools = Enum.filter(tools, &requires_bridge?/1)
    
    tool_specs = Enum.map(bridged_tools, fn tool ->
      %{
        name: tool.name,
        tool_id: generate_tool_id(session_id, tool.name),
        type: tool.type
      }
    end)
    
    new_state = put_in(state.sessions[session_id], tool_specs)
    {:reply, {:ok, tool_specs}, new_state}
  end
  
  defp requires_bridge?(%{type: :external}), do: true
  defp requires_bridge?(%{type: :database}), do: true
  defp requires_bridge?(_), do: false
end
```

### 3.2 Streaming Tool Bridge

```python
# File: snakepit/priv/python/snakepit_bridge/streaming_tools.py

class StreamingToolBridge:
    """Minimal tool bridge with streaming support"""
    
    def __init__(self, session_id: str):
        self.session_id = session_id
        self.tools = {}
        
    def register_streaming_tool(self, name: str, tool_id: str):
        """Register a tool that supports streaming"""
        
        async def streaming_tool_wrapper(*args, **kwargs):
            """Wrapper that streams results back to Elixir"""
            
            # Send tool call request
            request_id = f"tool_{uuid.uuid4().hex}"
            
            yield {
                "type": "tool_call_start",
                "tool_id": tool_id,
                "request_id": request_id,
                "args": args,
                "kwargs": kwargs
            }
            
            # In real implementation, this would use asyncio
            # to receive streamed results from Elixir
            async for chunk in self._stream_from_elixir(request_id):
                yield chunk
                
        self.tools[name] = streaming_tool_wrapper
        return streaming_tool_wrapper
```

## Phase 4: Integration and Optimization (Week 7-8)

### 4.1 Unified Streaming Interface

```elixir
# File: lib/dspex/streaming.ex

defmodule DSPex.Streaming do
  @moduledoc """
  Unified streaming interface for all DSPex operations
  """
  
  def stream(operation, args, callback, opts \\ []) do
    strategy = determine_strategy(operation, args)
    
    case strategy do
      :direct_streaming ->
        # Use native streaming for simple operations
        DSPex.Modules.Streaming.stream(operation, args, callback, opts)
        
      :compositional ->
        # Use composer for complex pipelines
        composer = DSPex.Composer.new()
        DSPex.Composer.stream(composer, operation, args, callback)
        
      :tool_bridge ->
        # Use tool bridge only when necessary
        with {:ok, tools} <- prepare_tools(args),
             {:ok, session} <- setup_bridge_session(tools) do
          execute_with_tools(session, operation, args, callback)
        end
    end
  end
  
  defp determine_strategy(operation, args) do
    cond do
      simple_streaming?(operation) -> :direct_streaming
      has_pipeline?(args) -> :compositional
      has_external_tools?(args) -> :tool_bridge
      true -> :direct_streaming
    end
  end
end
```

### 4.2 Performance Monitoring

```elixir
# File: lib/dspex/streaming/telemetry.ex

defmodule DSPex.Streaming.Telemetry do
  @moduledoc """
  Performance monitoring for streaming operations
  """
  
  def setup do
    events = [
      [:dspex, :streaming, :start],
      [:dspex, :streaming, :chunk],
      [:dspex, :streaming, :complete],
      [:dspex, :streaming, :error]
    ]
    
    :telemetry.attach_many(
      "dspex-streaming",
      events,
      &handle_event/4,
      nil
    )
  end
  
  def handle_event([:dspex, :streaming, :chunk], measurements, metadata, _) do
    # Track streaming performance
    latency = measurements.latency
    chunk_size = measurements.size
    
    if latency > 100 do  # 100ms threshold
      Logger.warning("Slow streaming chunk: #{latency}ms for #{chunk_size} bytes")
    end
  end
end
```

## Implementation Timeline

### Week 1-2: DSPy Streaming
- [ ] Implement DSPy streaming handler
- [ ] Add streaming API to DSPex modules
- [ ] Update examples to use real streaming
- [ ] Test with gRPC adapter

### Week 3-4: Compositional Framework
- [ ] Build DSPex.Composer
- [ ] Implement Python compositional engine
- [ ] Create pipeline examples
- [ ] Add branching and parallel execution

### Week 5-6: Selective Tool Bridge
- [ ] Implement minimal tool registry
- [ ] Add streaming tool support
- [ ] Create external tool examples
- [ ] Test tool + streaming integration

### Week 7-8: Integration
- [ ] Unified streaming interface
- [ ] Performance monitoring
- [ ] Documentation
- [ ] Production testing

## Success Metrics

1. **Streaming Performance**
   - First chunk latency < 50ms
   - Sustained throughput > 1000 chunks/second
   - Memory usage stable during long streams

2. **Compositional Efficiency**
   - 80% of use cases handled without tool bridge
   - Pipeline execution 2x faster than sequential calls
   - Reduced serialization overhead by 60%

3. **Tool Bridge Usage**
   - < 20% of operations require tool bridge
   - Tool call latency < 10ms
   - Zero memory leaks in long-running sessions

## Risk Mitigation

1. **Streaming Backpressure**
   - Implement flow control in gRPC streams
   - Add buffering with configurable limits
   - Monitor memory usage

2. **Compositional Complexity**
   - Start with simple pipelines
   - Extensive testing of edge cases
   - Clear error propagation

3. **Tool Bridge Performance**
   - Connection pooling for tools
   - Async tool execution
   - Timeout handling

## Conclusion

This implementation plan delivers immediate value through streaming while building toward a more sophisticated compositional architecture. By prioritizing streaming first, we can:

1. Deliver working streaming DSPy operations quickly
2. Learn from real usage patterns
3. Build compositional features based on actual needs
4. Implement tool bridge only where necessary

The phased approach ensures each component is production-ready before moving to the next, reducing risk and maximizing value delivery.