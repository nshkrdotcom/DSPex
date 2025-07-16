# Python Pool V3 Implementation Guide

## Module Structure

```
lib/dspex/python/
├── worker_supervisor.ex    # DynamicSupervisor for workers
├── worker.ex              # Individual Python process manager
├── pool.ex                # Request distribution and queueing
├── registry.ex            # Worker registration (thin wrapper)
└── protocol.ex            # Reuse existing protocol module
```

## Implementation Order

### Phase 1: Core Infrastructure (Day 1)

1. **Registry Setup**
   ```elixir
   defmodule DSPex.Python.Registry do
     def child_spec(_opts) do
       Registry.child_spec(keys: :unique, name: __MODULE__)
     end
     
     def via_tuple(worker_id) do
       {:via, Registry, {__MODULE__, worker_id}}
     end
   end
   ```

2. **Worker Supervisor**
   ```elixir
   defmodule DSPex.Python.WorkerSupervisor do
     use DynamicSupervisor
     
     def start_link(opts) do
       DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
     end
     
     def init(_opts) do
       DynamicSupervisor.init(strategy: :one_for_one)
     end
     
     def start_worker(worker_id) do
       spec = {DSPex.Python.Worker, id: worker_id}
       DynamicSupervisor.start_child(__MODULE__, spec)
     end
   end
   ```

### Phase 2: Worker Implementation (Day 1-2)

1. **Basic Worker Structure**
   ```elixir
   defmodule DSPex.Python.Worker do
     use GenServer, restart: :permanent
     require Logger
     
     defstruct [:id, :port, :busy, :pending_requests, :health_status]
     
     def start_link(opts) do
       GenServer.start_link(__MODULE__, opts, name: DSPex.Python.Registry.via_tuple(opts[:id]))
     end
   end
   ```

2. **Port Management**
   - Reuse existing PythonPort module for port creation
   - Handle port messages with existing Protocol module
   - Add health check timer on init

3. **Request Handling**
   - Store pending requests by request_id
   - Use existing Protocol.encode_request/3
   - Reply to correct caller on response

### Phase 3: Pool Manager (Day 2)

1. **State Structure**
   ```elixir
   defstruct [
     :workers,           # All worker IDs
     :available,         # Queue of available worker IDs
     :busy,              # Map of worker_id => true
     :request_queue,     # Queue of {from, command, args}
     :size,              # Target pool size
     :stats              # Basic metrics
   ]
   ```

2. **Concurrent Initialization**
   ```elixir
   defp start_workers_concurrently(count) do
     Logger.info("Starting #{count} Python workers concurrently...")
     
     results = 1..count
     |> Task.async_stream(
       fn i ->
         worker_id = "python_worker_#{i}_#{:erlang.unique_integer([:positive])}"
         case DSPex.Python.WorkerSupervisor.start_worker(worker_id) do
           {:ok, _pid} -> 
             Logger.info("Worker #{i}/#{count} started: #{worker_id}")
             worker_id
           {:error, reason} -> 
             Logger.error("Failed to start worker #{i}: #{inspect(reason)}")
             nil
         end
       end,
       timeout: 10_000,
       max_concurrency: count,
       on_timeout: :kill_task
     )
     |> Enum.map(fn
       {:ok, worker_id} -> worker_id
       {:exit, reason} -> 
         Logger.error("Worker start task failed: #{inspect(reason)}")
         nil
     end)
     |> Enum.filter(&(&1 != nil))
     
     Logger.info("Successfully started #{length(results)}/#{count} workers")
     results
   end
   ```

3. **Request Distribution**
   - Check available queue first
   - If worker available: assign and execute async
   - If no workers: add to request queue
   - Handle completion: check queue or return to available

### Phase 4: Integration (Day 3)

1. **Application Supervisor**
   ```elixir
   defmodule DSPex.Application do
     def start(_type, _args) do
       children = [
         DSPex.Python.Registry,
         DSPex.Python.WorkerSupervisor,
         {DSPex.Python.Pool, pool_config()},
         DSPex.PythonBridge.SessionStore  # Keep existing
       ]
       
       Supervisor.start_link(children, strategy: :one_for_one)
     end
   end
   ```

2. **Session Integration**
   ```elixir
   defmodule DSPex.Python.SessionAdapter do
     alias DSPex.PythonBridge.SessionStore
     alias DSPex.Python.Pool
     
     def execute_in_session(session_id, command, args, opts \\ []) do
       # Enhance args with session data if needed
       enhanced_args = enhance_with_session(session_id, command, args)
       
       # Execute on any available worker
       Pool.execute(command, enhanced_args, opts)
     end
     
     defp enhance_with_session(session_id, :execute_program, args) do
       case SessionStore.get_session(session_id) do
         {:ok, session} ->
           # Add program data if available
           program_id = Map.get(args, :program_id)
           case Map.get(session.programs, program_id) do
             nil -> args
             program_data -> Map.put(args, :program_data, program_data)
           end
         _ -> args
       end
     end
     
     defp enhance_with_session(_session_id, _command, args), do: args
   end
   ```

### Phase 5: Migration Strategy (Day 4)

1. **Feature Flag Approach**
   ```elixir
   def execute(command, args, opts) do
     case feature_enabled?(:python_pool_v3) do
       true -> DSPex.Python.Pool.execute(command, args, opts)
       false -> DSPex.PythonBridge.SessionPoolV2.execute_anonymous(command, args, opts)
     end
   end
   ```

2. **Gradual Rollout**
   - Start with read-only operations
   - Move to low-risk write operations
   - Finally migrate critical path
   - Keep V2 running during transition

3. **Rollback Plan**
   - Feature flag can instantly revert
   - Both pools can run simultaneously
   - Monitor metrics during transition

## Testing Strategy

### Unit Tests

1. **Worker Tests**
   ```elixir
   test "worker handles request and response" do
     {:ok, worker} = start_supervised({Worker, id: "test_worker"})
     
     ref = make_ref()
     send(worker, {:execute, ref, :ping, %{}})
     
     assert_receive {:response, ^ref, {:ok, %{"pong" => true}}}, 5_000
   end
   ```

2. **Pool Tests**
   ```elixir
   test "pool starts all workers concurrently" do
     start_time = System.monotonic_time(:millisecond)
     {:ok, pool} = start_supervised({Pool, size: 4})
     startup_time = System.monotonic_time(:millisecond) - start_time
     
     # Should take ~3 seconds, not 12 seconds
     assert startup_time < 5_000
   end
   ```

### Integration Tests

1. **End-to-End Flow**
   ```elixir
   test "executes Python program through pool" do
     {:ok, _} = start_supervised(python_pool_spec())
     
     # Create program
     assert {:ok, _} = Pool.execute(:create_program, %{
       id: "test_prog",
       signature: "question -> answer"
     })
     
     # Execute program
     assert {:ok, %{"answer" => _}} = Pool.execute(:execute_program, %{
       program_id: "test_prog",
       inputs: %{question: "What is 2+2?"}
     })
   end
   ```

2. **Concurrent Load Test**
   ```elixir
   test "handles concurrent requests efficiently" do
     {:ok, _} = start_supervised({Pool, size: 4})
     
     # Fire 100 concurrent requests
     tasks = for i <- 1..100 do
       Task.async(fn ->
         Pool.execute(:calculate, %{expression: "#{i} + #{i}"})
       end)
     end
     
     results = Task.await_many(tasks, 30_000)
     assert length(results) == 100
     assert Enum.all?(results, &match?({:ok, _}, &1))
   end
   ```

### Performance Tests

```elixir
defmodule PoolBenchmark do
  def run do
    Benchee.run(%{
      "v2_pool_startup" => fn ->
        start_supervised!({SessionPoolV2, size: 8})
      end,
      "v3_pool_startup" => fn ->
        start_supervised!({Pool, size: 8})
      end
    })
    
    # Expected results:
    # v2_pool_startup: 16-24 seconds
    # v3_pool_startup: 2-3 seconds
  end
end
```

## Configuration

### Minimal Configuration

```elixir
config :dspex, DSPex.Python.Pool,
  size: System.schedulers_online() * 2
```

### Full Configuration

```elixir
config :dspex, DSPex.Python.Pool,
  size: 8,                           # Number of Python workers
  python_path: "/usr/bin/python3",   # Python executable
  python_args: ["-u"],               # Python arguments
  startup_timeout: 10_000,           # Worker startup timeout
  health_check_interval: 30_000,     # Health check frequency
  max_queue_size: 1000,              # Max queued requests
  queue_timeout: 5_000               # How long to wait for worker
```

## Monitoring

### Key Metrics

1. **Pool Metrics**
   - `pool.size` - Current number of workers
   - `pool.available` - Available worker count
   - `pool.busy` - Busy worker count
   - `pool.queue_size` - Requests waiting

2. **Worker Metrics**
   - `worker.requests` - Total requests handled
   - `worker.errors` - Total errors
   - `worker.response_time` - Average response time
   - `worker.health_status` - Current health

3. **System Metrics**
   - `startup.duration` - Pool startup time
   - `request.queued_time` - Time spent in queue
   - `request.total_time` - End-to-end time

### Telemetry Events

```elixir
:telemetry.execute(
  [:dspex, :python, :pool, :request],
  %{duration: duration, queue_time: queue_time},
  %{command: command, worker_id: worker_id}
)
```

## Troubleshooting

### Common Issues

1. **Slow Startup**
   - Check Python process initialization
   - Verify no blocking operations in worker init
   - Check system resources (CPU, memory)

2. **Workers Crashing**
   - Check Python stderr output
   - Verify Python environment
   - Check for resource limits

3. **Request Timeouts**
   - Monitor queue size
   - Check worker health
   - Consider increasing pool size

### Debug Mode

```elixir
# Enable debug logging
config :logger, level: :debug

# Add debug instrumentation
config :dspex, DSPex.Python.Pool,
  debug: true,
  trace_requests: true
```