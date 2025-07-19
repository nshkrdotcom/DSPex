# Task: PYTHON.1 - Snakepit Integration Layer

## Context
You are implementing the Snakepit integration layer that manages Python process pools for DSPex. This layer provides the foundation for all Python/DSPy operations by leveraging Snakepit's battle-tested pooling capabilities.

## Required Reading

### 1. Snakepit Documentation
- **File**: `/home/home/p/g/n/dspex/snakepit/README.md`
  - Lines 13-21: Core features
  - Lines 39-62: Quick start
  - Lines 92-114: Core concepts
  - Lines 125-162: Configuration options

### 2. Snakepit Python Bridge V2
- **File**: `/home/home/p/g/n/dspex/snakepit/PYTHON_BRIDGE_V2.md`
  - Lines 9-30: Key improvements
  - Lines 100-130: V2 bridge pattern

### 3. DSPex Architecture
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/01_CORE_ARCHITECTURE.md`
  - Section on Snakepit integration
  - Pool strategy (general, optimizer, neural)

### 4. Python Bridge Module
- **File**: `/home/home/p/g/n/dspex/lib/dspex/python/bridge.ex`
  - Current integration approach
  - Note any patterns to maintain

### 5. Pool Manager
- **File**: `/home/home/p/g/n/dspex/lib/dspex/python/pool_manager.ex`
  - Pool configuration patterns
  - Lifecycle management

## Implementation Requirements

### Pool Configuration
```elixir
defmodule DSPex.Python.SnakepitConfig do
  @moduledoc """
  Snakepit pool configurations for different workload types
  """
  
  def pools do
    [
      # General purpose pool for lightweight operations
      general: [
        adapter_module: Snakepit.Adapters.GenericPythonV2,
        pool_size: System.schedulers_online() * 2,
        pool_config: %{
          memory_limit: "512MB",
          timeout: 30_000,
          health_check_interval: 30_000
        }
      ],
      
      # Optimizer pool for heavy ML tasks
      optimizer: [
        adapter_module: DSPex.Adapters.OptimizerPython,
        pool_size: 2,
        pool_config: %{
          memory_limit: "4GB",
          timeout: 300_000,  # 5 minutes
          health_check_interval: 60_000
        }
      ],
      
      # Neural pool for GPU operations
      neural: [
        adapter_module: DSPex.Adapters.NeuralPython,
        pool_size: 4,
        pool_config: %{
          memory_limit: "8GB",
          gpu_enabled: true,
          timeout: 600_000,  # 10 minutes
          health_check_interval: 60_000
        }
      ]
    ]
  end
end
```

### Integration Layer
```elixir
defmodule DSPex.Python.Snakepit do
  @moduledoc """
  Snakepit integration for DSPex Python operations
  """
  
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    children = build_pool_specs()
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  defp build_pool_specs do
    DSPex.Python.SnakepitConfig.pools()
    |> Enum.map(fn {name, config} ->
      %{
        id: :"snakepit_pool_#{name}",
        start: {Snakepit.Pool, :start_link, [
          Keyword.put(config, :name, pool_name(name))
        ]}
      }
    end)
  end
  
  def pool_name(type), do: :"dspex_python_#{type}"
  
  # Public API
  def execute(pool_type, command, args, opts \\ []) do
    pool = pool_name(pool_type)
    timeout = opts[:timeout] || default_timeout(pool_type)
    
    Snakepit.execute(pool, command, args, timeout: timeout)
  end
  
  def execute_in_session(session_id, pool_type, command, args, opts \\ []) do
    pool = pool_name(pool_type)
    Snakepit.execute_in_session(session_id, command, args, opts)
  end
end
```

### Health Monitoring
```elixir
defmodule DSPex.Python.HealthMonitor do
  use GenServer
  require Logger
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    schedule_health_check()
    {:ok, %{pools: DSPex.Python.SnakepitConfig.pools()}}
  end
  
  def handle_info(:health_check, state) do
    Enum.each(state.pools, fn {name, _config} ->
      check_pool_health(name)
    end)
    
    schedule_health_check()
    {:noreply, state}
  end
  
  defp check_pool_health(pool_type) do
    pool = DSPex.Python.Snakepit.pool_name(pool_type)
    
    case Snakepit.get_pool_stats(pool) do
      {:ok, stats} ->
        :telemetry.execute(
          [:dspex, :python, :pool_health],
          %{
            available: stats.available,
            busy: stats.busy,
            total: stats.size
          },
          %{pool: pool_type}
        )
        
      {:error, reason} ->
        Logger.error("Pool health check failed for #{pool_type}: #{inspect(reason)}")
    end
  end
end
```

### Session Management Integration
```elixir
defmodule DSPex.Python.SessionManager do
  @moduledoc """
  Manages DSPex sessions with Snakepit session support
  """
  
  def create_session(opts \\ []) do
    session_id = generate_session_id()
    pool_type = opts[:pool_type] || :general
    
    metadata = %{
      created_at: DateTime.utc_now(),
      pool_type: pool_type,
      dspex_context: opts[:context] || %{}
    }
    
    case Snakepit.Bridge.SessionStore.create_session(session_id, 
      ttl: opts[:ttl] || 3600,
      metadata: metadata
    ) do
      {:ok, _} -> {:ok, session_id}
      error -> error
    end
  end
  
  def execute_in_session(session_id, command, args) do
    case get_session_metadata(session_id) do
      {:ok, %{pool_type: pool_type}} ->
        DSPex.Python.Snakepit.execute_in_session(
          session_id,
          pool_type,
          command,
          args
        )
        
      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end
end
```

## Acceptance Criteria
- [ ] Three pool types configured (general, optimizer, neural)
- [ ] Pools start automatically with application
- [ ] Health monitoring for all pools
- [ ] Session management integration
- [ ] Telemetry events for pool metrics
- [ ] Graceful shutdown handling
- [ ] Error recovery for failed workers
- [ ] Configuration validation
- [ ] Pool selection logic based on operation type

## Error Handling
```elixir
def handle_execute_error({:error, :pool_saturated}) do
  {:error, %{
    type: :resource_exhausted,
    message: "Python pool is at capacity",
    retry_after: 1000
  }}
end

def handle_execute_error({:error, :worker_timeout}) do
  {:error, %{
    type: :timeout,
    message: "Python operation timed out",
    suggestion: "Consider using optimizer pool for long operations"
  }}
end
```

## Testing Requirements
Create tests in:
- `test/dspex/python/snakepit_test.exs`
- `test/dspex/python/health_monitor_test.exs`

Test scenarios:
- Pool initialization
- Basic execution in each pool type
- Session persistence
- Pool saturation handling
- Worker failure recovery
- Health check operation

## Example Usage
```elixir
# Simple execution
{:ok, result} = DSPex.Python.Snakepit.execute(
  :general,
  "echo",
  %{message: "Hello from Python"}
)

# Long-running optimization
{:ok, result} = DSPex.Python.Snakepit.execute(
  :optimizer,
  "optimize_model",
  %{iterations: 1000, data: data},
  timeout: 300_000
)

# Session-based execution
{:ok, session_id} = DSPex.Python.SessionManager.create_session(
  pool_type: :neural,
  ttl: 7200
)

{:ok, result} = DSPex.Python.SessionManager.execute_in_session(
  session_id,
  "train_model",
  %{epochs: 10, batch_size: 32}
)
```

## Dependencies
- Snakepit library properly configured
- Python environment with DSPy installed
- No circular dependencies with other DSPex modules

## Time Estimate
6 hours total:
- 2 hours: Pool configuration and initialization
- 1 hour: Health monitoring setup
- 1 hour: Session management integration
- 1 hour: Error handling and telemetry
- 1 hour: Comprehensive testing

## Notes
- Start pools in parallel for faster startup
- Monitor memory usage in Python processes
- Consider pool warming for better performance
- Add metrics for pool utilization
- Document pool selection guidelines
- Consider dynamic pool sizing based on load