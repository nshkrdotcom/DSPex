# Python as First-Class Citizen in DSPex

## Philosophy

DSPex V2 treats Python processes not as a necessary evil, but as first-class citizens in the ML pipeline ecosystem. This document details how Python components, especially complex ones like MIPROv2, integrate seamlessly with native Elixir components.

## Core Integration Patterns

### 1. Dedicated Python Pools

Different Python components have different resource requirements. DSPex manages specialized pools:

```elixir
defmodule DSPex.PythonPools do
  @moduledoc """
  Manages specialized Snakepit pools for different Python workloads.
  """
  
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    children = [
      # Lightweight pool for simple operations
      {Snakepit.Pool, 
        name: :dspy_light,
        adapter: Snakepit.Adapters.Python,
        python_path: python_env("light"),
        script: "priv/python/dspy_light.py",
        pool_size: 8,
        max_memory: "512MB"},
      
      # Heavy pool for MIPROv2 and optimization
      {Snakepit.Pool,
        name: :dspy_mipro,
        adapter: Snakepit.Adapters.Python,
        python_path: python_env("mipro"),  # Separate venv with more deps
        script: "priv/python/mipro_bridge.py",
        pool_size: 2,  # MIPROv2 is memory intensive
        max_memory: "4GB",
        env: %{"PYTORCH_CUDA_ALLOC_CONF" => "max_split_size_mb:512"}},
      
      # Specialized pool for ColBERT/retrieval models  
      {Snakepit.Pool,
        name: :dspy_retrieval,
        adapter: Snakepit.Adapters.Python,
        python_path: python_env("retrieval"),
        script: "priv/python/retrieval_bridge.py",
        pool_size: 4,
        gpu_enabled: true}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  defp python_env(type) do
    base = Application.get_env(:dspex, :python_base_path, "~/.dspex/envs")
    Path.join([base, type, "bin/python"])
  end
end
```

### 2. Stateful Python Sessions

Some Python operations (like MIPROv2 optimization) are inherently stateful. DSPex provides first-class support:

```elixir
defmodule DSPex.PythonSession do
  @moduledoc """
  Manages stateful Python sessions for complex operations.
  """
  
  defstruct [:id, :pool, :worker_pid, :state, :created_at, :last_used]
  
  def create(pool_name, initial_state \\ %{}) do
    session_id = generate_id()
    
    # Reserve a worker for this session
    {:ok, worker} = Snakepit.checkout_exclusive(pool_name, 
      timeout: :timer.minutes(30))  # Long timeout for optimization
    
    # Initialize session state in Python
    {:ok, _} = Snakepit.call(worker, %{
      op: "init_session",
      session_id: session_id,
      state: initial_state
    })
    
    %__MODULE__{
      id: session_id,
      pool: pool_name,
      worker_pid: worker,
      state: initial_state,
      created_at: DateTime.utc_now(),
      last_used: DateTime.utc_now()
    }
  end
  
  def call(session, operation, args) do
    # All calls go to the same worker
    result = Snakepit.call(session.worker_pid, %{
      op: operation,
      session_id: session.id,
      args: args
    })
    
    # Update last used
    %{session | last_used: DateTime.utc_now()}
    
    result
  end
  
  # Example: MIPROv2 optimization session
  def mipro_optimization_session(module, trainset, config) do
    with {:ok, session} <- create(:dspy_mipro, %{module: module}),
         {:ok, _} <- call(session, "load_trainset", %{data: trainset}),
         {:ok, _} <- call(session, "configure_mipro", config),
         {:ok, result} <- call(session, "optimize", %{iterations: 100}) do
      
      # Get optimized module back
      {:ok, optimized} = call(session, "get_optimized_module", %{})
      
      # Clean up
      release(session)
      
      {:ok, optimized}
    end
  end
end
```

### 3. Python-Native Data Exchange

Efficient data exchange between Elixir and Python without unnecessary serialization:

```elixir
defmodule DSPex.DataExchange do
  @moduledoc """
  Optimized data exchange between Elixir and Python.
  """
  
  # For large datasets, use shared memory or files
  def exchange_large_dataset(data, python_worker) do
    case byte_size(data) do
      size when size < 1_000_000 ->
        # Small data: direct JSON
        {:json, Jason.encode!(data)}
        
      size when size < 100_000_000 ->
        # Medium data: temporary file with memory mapping
        path = write_temp_file(data)
        {:mmap_file, path}
        
      _ ->
        # Large data: Arrow format for zero-copy
        {:ok, arrow_path} = ArrowWriter.write(data)
        {:arrow_file, arrow_path}
    end
  end
  
  # Streaming results from Python
  def stream_from_python(session, operation, args) do
    Stream.resource(
      fn -> 
        # Start streaming operation
        {:ok, stream_id} = DSPex.PythonSession.call(session, 
          "start_stream", %{op: operation, args: args})
        {session, stream_id}
      end,
      fn {session, stream_id} ->
        case DSPex.PythonSession.call(session, "next_chunk", %{id: stream_id}) do
          {:ok, :done} -> {:halt, {session, stream_id}}
          {:ok, chunk} -> {[chunk], {session, stream_id}}
          {:error, reason} -> raise "Stream error: #{inspect(reason)}"
        end
      end,
      fn {session, stream_id} ->
        # Cleanup
        DSPex.PythonSession.call(session, "close_stream", %{id: stream_id})
      end
    )
  end
end
```

### 4. MIPROv2 Integration Example

Here's how MIPROv2, a complex Python-only optimizer, integrates as a first-class citizen:

```elixir
defmodule DSPex.Optimizers.MIPROv2 do
  @moduledoc """
  First-class integration of MIPROv2 optimizer.
  """
  
  defstruct [:session, :config, :status, :metrics]
  
  def create(config \\ %{}) do
    default_config = %{
      num_candidates: 10,
      init_temperature: 1.0,
      metric: "accuracy",
      verbose: true,
      track_stats: true,
      requires_permission_to_run: false
    }
    
    config = Map.merge(default_config, config)
    
    # Create dedicated session
    {:ok, session} = DSPex.PythonSession.create(:dspy_mipro)
    
    # Initialize MIPROv2 in Python
    {:ok, _} = DSPex.PythonSession.call(session, "init_mipro", config)
    
    %__MODULE__{
      session: session,
      config: config,
      status: :initialized,
      metrics: %{}
    }
  end
  
  def optimize(mipro, module, trainset, opts \\ []) do
    # Progress callback from Elixir
    progress_callback = opts[:on_progress] || fn _ -> :ok end
    
    # Start optimization with streaming updates
    stream = DSPex.DataExchange.stream_from_python(
      mipro.session,
      "mipro_optimize",
      %{
        module: serialize_module(module),
        trainset: prepare_trainset(trainset),
        config: mipro.config
      }
    )
    
    # Process streaming updates
    Enum.reduce(stream, mipro, fn update, acc ->
      case update do
        %{"type" => "progress", "data" => progress} ->
          progress_callback.(progress)
          %{acc | status: :optimizing, metrics: update_metrics(acc.metrics, progress)}
          
        %{"type" => "candidate", "data" => candidate} ->
          # Store intermediate candidates if needed
          maybe_store_candidate(acc, candidate)
          
        %{"type" => "complete", "data" => result} ->
          %{acc | status: :complete, metrics: result["final_metrics"]}
      end
    end)
  end
  
  # Get optimized module back in Elixir-friendly format
  def get_optimized_module(mipro) do
    {:ok, python_module} = DSPex.PythonSession.call(
      mipro.session, 
      "get_optimized_module", 
      %{}
    )
    
    # Convert to Elixir representation
    %DSPex.Module{
      type: :optimized,
      implementation: {:python, python_module["id"]},
      prompts: python_module["prompts"],
      demonstrations: python_module["demonstrations"],
      metadata: %{
        optimizer: "MIPROv2",
        metrics: mipro.metrics,
        config: mipro.config
      }
    }
  end
  
  # Advanced: Checkpointing for long-running optimizations
  def checkpoint(mipro, path) do
    DSPex.PythonSession.call(mipro.session, "checkpoint", %{path: path})
  end
  
  def resume_from_checkpoint(path) do
    {:ok, session} = DSPex.PythonSession.create(:dspy_mipro)
    {:ok, state} = DSPex.PythonSession.call(session, "load_checkpoint", %{path: path})
    
    %__MODULE__{
      session: session,
      config: state["config"],
      status: :resumed,
      metrics: state["metrics"]
    }
  end
end
```

### 5. Python Process Lifecycle Management

First-class Python processes need proper lifecycle management:

```elixir
defmodule DSPex.PythonLifecycle do
  @moduledoc """
  Manages Python process lifecycles as first-class citizens.
  """
  
  use GenServer
  
  # Warmup Python processes with imports
  def warmup_pool(pool_name, warmup_script \\ nil) do
    pool_config = Snakepit.get_pool_config(pool_name)
    
    # Parallel warmup
    tasks = for i <- 1..pool_config.pool_size do
      Task.async(fn ->
        Snakepit.call(pool_name, %{
          op: "warmup",
          imports: get_required_imports(pool_name),
          script: warmup_script
        })
      end)
    end
    
    Task.await_many(tasks, :timer.seconds(30))
  end
  
  # Health monitoring specific to Python components
  def monitor_python_health do
    %{
      memory: check_python_memory(),
      gpu: check_gpu_usage(),
      model_cache: check_model_cache_size(),
      active_sessions: count_active_sessions()
    }
  end
  
  # Graceful shutdown with state preservation
  def graceful_shutdown(pool_name) do
    # Get all active sessions
    sessions = DSPex.SessionRegistry.list_active(pool_name)
    
    # Checkpoint each session
    Enum.each(sessions, fn session ->
      checkpoint_path = "/tmp/dspex_checkpoint_#{session.id}"
      DSPex.PythonSession.checkpoint(session, checkpoint_path)
      
      # Store checkpoint location
      :persistent_term.put({:dspex, :checkpoint, session.id}, checkpoint_path)
    end)
    
    # Now safe to shutdown
    Snakepit.stop_pool(pool_name)
  end
end
```

### 6. Python Error Handling as First-Class

Python errors are handled with the same sophistication as Elixir errors:

```elixir
defmodule DSPex.PythonErrorHandler do
  @moduledoc """
  Sophisticated error handling for Python components.
  """
  
  def handle_python_error({:python_error, type, message, traceback}) do
    case classify_error(type, message) do
      {:gpu_oom, details} ->
        # GPU out of memory - specific handling
        handle_gpu_oom(details)
        
      {:model_not_found, model_name} ->
        # Auto-download missing model
        maybe_download_model(model_name)
        
      {:optimization_diverged, metrics} ->
        # MIPROv2 specific - restart with different config
        suggest_alternative_config(metrics)
        
      {:dependency_missing, package} ->
        # Suggest installation command
        installation_command(package)
        
      _ ->
        # Generic Python error
        format_python_traceback(traceback)
    end
  end
  
  defp handle_gpu_oom(details) do
    # Clear GPU cache
    DSPex.PythonSession.call(:dspy_mipro, "clear_gpu_cache", %{})
    
    # Reduce batch size
    new_config = Map.update(details.config, :batch_size, 32, &div(&1, 2))
    
    {:retry_with_config, new_config}
  end
end
```

## Benefits of First-Class Python Integration

1. **No Compromise**: Use the best tool for each job
2. **State Management**: Stateful Python operations work naturally
3. **Resource Optimization**: Different pools for different workloads
4. **Error Recovery**: Sophisticated handling of Python-specific errors
5. **Performance**: Optimized data exchange and parallel execution
6. **Debugging**: Full visibility into Python processes

## Example: Complete ML Pipeline

```elixir
defmodule MyApp.MLPipeline do
  def train_and_deploy(dataset) do
    # Native data prep
    prepared = DSPex.Native.DataPrep.prepare(dataset)
    
    # Python feature engineering
    features = DSPex.Python.call(:dspy_light, "extract_features", prepared)
    
    # Create MIPROv2 optimizer
    optimizer = DSPex.Optimizers.MIPROv2.create(%{
      num_candidates: 50,
      metric: "f1_score"
    })
    
    # Define module to optimize
    module = DSPex.module([
      {:python, "dspy.ChainOfThought", signature: "question -> answer"},
      {:native, DSPex.Native.Validator, rules: :strict}
    ])
    
    # Run optimization (Python)
    optimized = DSPex.Optimizers.MIPROv2.optimize(
      optimizer, 
      module, 
      prepared.trainset,
      on_progress: &Logger.info("Progress: #{inspect(&1)}")
    )
    
    # Deploy with mixed execution
    DSPex.deploy(optimized, [
      cache: {:native, DSPex.Native.Cache},
      executor: {:mixed, python: 0.3, native: 0.7}
    ])
  end
end
```

This architecture truly makes Python a first-class citizen while leveraging Elixir's strengths where they matter most.