# Complete NimblePool Documentation and Analysis
Generated on: Sun Jul 13 19:28:45 HST 2025


---
## Understanding NimblePool
File: docs/UNDERSTANDING_NIMBLE_POOL.md
---

Based on the provided documentation and source code for `NimblePool`, I will now demonstrate how to implement a custom resource pool.

### Understanding NimblePool

First, let's summarize the core concepts of `NimblePool` from the documentation:

*   **Process-less Resource Management**: Unlike traditional pools like `poolboy` that manage a pool of worker processes, `NimblePool` manages resources (like sockets, ports, or NIF resources) directly within a single `GenServer` process. This avoids the overhead of inter-process communication for each operation.
*   **Client-Owned Operations**: The pool "checks out" a resource and temporarily transfers its ownership to the client process. The client then interacts with the resource directly, performs its operation, and "checks in" the resource back to the pool.
*   **Callback-based Behaviour**: To use `NimblePool`, you define a worker module that implements the `NimblePool` behaviour. This involves defining callbacks like `init_worker`, `handle_checkout`, `handle_checkin`, and `terminate_worker` to manage the lifecycle of your specific resource.
*   **Use Cases**: It's ideal for managing resources that don't support multiplexing and where clients perform one-off operations, such as HTTP/1 connections or, as we'll see, ports to external programs.

### Implementation: A Line Processor Pool

To illustrate these concepts, I will implement a pool that manages OS processes through Elixir's `Port`s. Each worker in our pool will be a long-running external process (like `tr`, `sed`, or `cat`) that can process lines of text. This is a practical example of managing a non-Erlang resource.

I'll call the module `LineProcessorPool`. It will be configurable to run any command-line tool that processes text line-by-line.

Here is the complete implementation:

```elixir
defmodule LineProcessorPool do
  @moduledoc """
  A NimblePool for managing command-line tools that process text line-by-line.

  This pool starts and manages external OS processes via Elixir Ports.
  Clients can check out a port, send it a line of text, and read a
  processed line back.

  ## Example Usage

  First, add it to your supervision tree. Here, we configure it to create
  a pool of workers that convert text to uppercase using `tr`.

  ```elixir
  children = [
    {NimblePool,
     worker: {LineProcessorPool, {"tr", ["a-z", "A-Z"]}},
     name: :uppercase_pool,
     pool_size: 5}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
  ```

  Then, you can use the pool to process strings:

  ```elixir
  iex> LineProcessorPool.process(:uppercase_pool, "hello world")
  "HELLO WORLD"

  iex> LineProcessorPool.process(:uppercase_pool, "another line")
  "ANOTHER LINE"
  ```
  """
  @behaviour NimblePool

  require Logger

  @doc """
  Processes a string using a worker from the pool.
  """
  def process(pool, string, opts \\ []) do
    pool_timeout = Keyword.get(opts, :pool_timeout, 5000)
    receive_timeout = Keyword.get(opts, :receive_timeout, 5000)

    # 1. Checkout a worker. The anonymous function runs in the *client process*.
    NimblePool.checkout!(pool, :process, fn {_from, port} ->
      # 2. We have received the port. Send the command (string + newline).
      send(port, {self(), {:command, string <> "\n"}})

      # 3. Wait for the response from the port.
      receive do
        {^port, {:data, {:eol, line}}} ->
          # 4. Success! Unlink to prevent our death from killing the port.
          Process.unlink(port)
          # 5. Return the result and signal a clean checkin with :ok.
          {String.trim(line), :ok}
      after
        receive_timeout ->
          # The external process didn't respond in time.
          exit({:receive_timeout, "Did not receive a response from the worker process"})
      end
    end, pool_timeout)
  end

  # --- NimblePool Callbacks ---

  @impl NimblePool
  def init_worker({executable, args} = pool_state) do
    # Called by NimblePool for each worker on startup.
    # The `pool_state` is the `{executable, args}` tuple from the supervisor spec.
    case System.find_executable(executable) do
      nil ->
        # Returning :stop will terminate the entire pool.
        {:stop, "Could not find '#{executable}' executable in PATH"}

      path ->
        # Start the external command as a port.
        # :line - delivers data from the port line-by-line.
        # :binary - handle data as binaries.
        port = Port.open({:spawn_executable, path}, [:binary, :line, args: args])
        Logger.info("Started worker port for #{executable}")
        # The worker's state is the port itself. We pass the pool_state through.
        {:ok, port, pool_state}
    end
  end

  @impl NimblePool
  def handle_checkout(:process, {client_pid, _ref}, port, pool_state) do
    # A client wants a worker. `client_pid` is the process calling `checkout!`.
    # We transfer ownership and link the port to the client.
    # If the client crashes, the port will be closed, which is good cleanup.
    Port.connect(port, client_pid)

    # The first `port` is the `client_state` passed to the checkout! function.
    # The second `port` is the `worker_state` stored while checked out.
    {:ok, port, port, pool_state}
  end

  @impl NimblePool
  # The client returned the worker successfully using {:ok}.
  def handle_checkin(:ok, _from, port, pool_state) do
    # The worker is healthy, so we return it to the pool.
    {:ok, port, pool_state}
  end

  # This clause could be used if the client function returned an error tuple.
  def handle_checkin({:error, reason}, _from, _port, pool_state) do
    # The client signaled an error. We remove this worker from the pool.
    # `terminate_worker` will be called for cleanup.
    {:remove, reason, pool_state}
  end

  @impl NimblePool
  def terminate_worker(reason, port, pool_state) do
    # This worker is being removed (e.g., due to an error or pool shutdown).
    # We must explicitly close the port to terminate the external OS process.
    Logger.warn("Terminating worker port. Reason: #{inspect(reason)}")
    Port.close(port)
    {:ok, pool_state}
  end
end
```

### Explanation of the Implementation

This implementation closely follows the pattern described in the `NimblePool` documentation.

1.  **`init_worker/1`**: This callback is responsible for creating a resource. We receive the configuration (`{executable, args}`) that was passed when starting the pool. We find the executable on the system and use `Port.open/2` to start it. The `:line` option is particularly useful, as it simplifies the client-side logic by delivering data from the port's stdout one line at a time. The returned `port` identifier becomes this worker's state.

2.  **`process/3` (Public API)**: This is the client-facing function. It abstracts the pooling logic away from the user.
    *   It calls `NimblePool.checkout!`, which blocks until a worker is available or the `:pool_timeout` is hit.
    *   The anonymous function passed to `checkout!` is the heart of the client logic. **Crucially, this function runs in the client's own process, not the pool's process.**
    *   It receives the `port` (as `client_state`) from the pool and interacts with it directly using `send/2` and `receive`. This direct interaction is what makes `NimblePool` efficient.
    *   After a successful interaction, it returns a tuple: `{result, checkin_state}`. Here, `result` is the processed string, and `:ok` is the `checkin_state` that tells `handle_checkin` that the worker is healthy and can be returned to the pool.

3.  **`handle_checkout/4`**: This callback acts as the bridge between the pool and the client. When a client requests a worker, the pool calls this function. Its primary job here is to call `Port.connect(port, client_pid)`. This transfers control of the port to the client process, so messages from the port's stdout are sent to the client. It also links the port and the client, so if the client crashes, the external process is automatically terminated.

4.  **`handle_checkin/4`**: This is called when the client is done with the worker. The first argument is the `checkin_state` returned by the client's function. If it's `:ok`, we simply return the worker (the `port`) to the pool's available queue by returning `{:ok, port, pool_state}`. If we had detected an error, we could return `{:remove, reason, pool_state}` to discard the worker.

5.  **`terminate_worker/3`**: This is the cleanup crew. It's called whenever a worker is removed from the pool, either through `handle_checkin` returning `:remove` or during a normal pool shutdown. Its responsibility is to release the resource cleanly. For a port, this means calling `Port.close(port)`.


---
## Integration Recommendations
File: docs/UNDERSTANDING_NIMBLE_POOL_integrationRecs.md
---

Of course. I have read the provided codebase with a focus on your use of `NimblePool`. Here is a detailed report on your pool design and its implementation.

### Executive Summary

Your team has correctly identified `NimblePool` as an appropriate tool for managing a pool of external Python processes via Elixir's `Port` mechanism. The overall design shows a good understanding of the problem space, with a clear separation of concerns between the session management (`SessionPool`), the worker logic (`PoolWorker`), and the supervision (`PoolSupervisor`). The implementation includes several excellent patterns, such as health checks on worker initialization and graceful worker termination.

However, there is a **critical architectural flaw** in the implementation of the checkout process. The current design centralizes all I/O waiting within the `SessionPool` GenServer, which effectively serializes all requests to the Python workers and negates the primary performance benefit of `NimblePool`. This turns the pool manager into a bottleneck, preventing concurrent execution.

This report will detail the identified issues and provide a clear, step-by-step path to refactor the implementation to be truly concurrent and align with `NimblePool`'s intended design.

---

### 1. Pool Design & Architecture Review

#### **Positive Aspects:**

*   **Technology Choice**: Using `NimblePool` is a great choice for this use case. It avoids the overhead of an extra Elixir process for each Python worker, which is ideal for managing `Port` resources.
*   **Component Separation**: The architecture is well-structured:
    *   `DSPex.Adapters.PythonPool`: A clean public-facing adapter.
    *   `DSPex.PythonBridge.SessionPool`: A dedicated manager/client for the pool.
    *   `DSPex.PythonBridge.PoolWorker`: A module that correctly encapsulates the `NimblePool` behaviour and worker-specific logic.
    *   `DSPex.PythonBridge.PoolSupervisor`: A proper supervisor to manage the lifecycle of the pool system.
*   **Session Affinity**: The design attempts to handle session state, which is crucial for the intended use case. Checking out a worker for a specific session (`{:session, session_id}`) is a good pattern.
*   **Lazy Initialization**: The `SessionPool` correctly configures `NimblePool` with `lazy: true`, which is efficient as it avoids starting Python processes until they are first needed.

#### **Critical Architectural Issue: Pool Manager as a Bottleneck**

The fundamental purpose of `NimblePool` is to hand off a resource to a client process, allowing that client to perform its (potentially long-running) I/O operations without blocking other clients or the pool manager itself.

Your current implementation centralizes the blocking `receive` call inside the `checkout!` function, which runs in the context of the `SessionPool` GenServer.

**The Flawed Flow:**

1.  A client calls `SessionPool.execute_in_session(...)`.
2.  The `SessionPool` GenServer receives this call.
3.  It calls `NimblePool.checkout!`.
4.  The anonymous function passed to `checkout!` is executed **within the `SessionPool` GenServer's process**.
5.  Inside this function, you call `PoolWorker.send_command(...)`.
6.  `PoolWorker.send_command` calls `send_and_await_response`, which contains a `receive` block.
7.  **The entire `SessionPool` GenServer now blocks**, waiting for a single Python worker to send a response. No other clients can check out workers or interact with the `SessionPool` until this `receive` block completes.

This serializes all Python operations, completely defeating the purpose of having a pool for concurrency.

---

### 2. `DSPex.PythonBridge.PoolWorker` Implementation Review

This module implements the `@behaviour NimblePool`.

#### **Positive Aspects:**

*   **`init_worker/1`**: The `send_initialization_ping` is an excellent pattern. It ensures the Python process is fully ready and responsive before the worker is considered "available" in the pool. This prevents race conditions.
*   **`handle_checkout/4`**: Correctly uses `Port.connect(port, pid)` to transfer control of the port to the client process. This is a key part of the correct `NimblePool` pattern.
*   **`handle_checkin/4`**: The logic to handle different check-in states (`:ok`, `:close`, etc.) and the `should_remove_worker?` check are well-designed for managing worker health.
*   **`terminate_worker/3`**: The implementation is robust. It attempts a graceful shutdown by sending a command and then has a timeout to forcefully close the port, preventing zombie processes.

#### **Identified Issues:**

1.  **Incorrect `init_worker` Return Type**:
    *   In `init_worker/1`, if the `send_initialization_ping` fails, you return `{:error, reason}`.
    *   According to the `NimblePool` source and documentation, `init_worker/1` is expected to return `{:ok, worker_state, pool_state}` or `{:async, fun, pool_state}`. Returning any other tuple will cause the pool supervisor to crash during startup.
    *   **Fix**: Instead of returning an error tuple, you should `raise` an exception. This will be caught by `NimblePool`, which will log the error and attempt to start another worker.

    ```elixir
    # In DSPex.PythonBridge.PoolWorker -> init_worker/1

    # ...
    case send_initialization_ping(worker_state) do
      {:ok, updated_state} ->
        Logger.info("Pool worker #{worker_id} started successfully")
        {:ok, updated_state, pool_state}

      {:error, reason} ->
        # Change this:
        # {:error, reason} 
        # To this:
        raise "Worker #{worker_id} initialization failed: #{inspect(reason)}"
    end
    ```

2.  **Misunderstanding of `handle_info/2`**:
    *   Your `handle_info/2` implementation handles responses from the port and attempts to `GenServer.reply` to the original caller.
    *   However, `handle_info/2` is only ever called for **idle workers** that are sitting in the pool's ready queue. Once a worker is checked out, the port is connected to the client process, and messages from the port go directly to that client.
    *   This part of your code is currently unreachable for active workers and is a symptom of the larger architectural flaw. Once the checkout flow is corrected, this code will become unnecessary.

---

### 3. `DSPex.PythonBridge.SessionPool` (Client) Implementation Review

#### **Identified Issue: Blocking `checkout!` Implementation**

As mentioned in the architecture review, the `handle_call` for `:execute_in_session` contains the flawed blocking logic.

```elixir
# In DSPex.PythonBridge.SessionPool -> handle_call/3 for :execute_in_session

def handle_call({:execute_in_session, session_id, command, args, opts}, _from, state) do
  # ...
  result =
    try do
      NimblePool.checkout!(
        state.pool_name,
        {:session, session_id},
        fn _from, worker_state -> # THIS FUNCTION BLOCKS THE GenServer
          # This call contains a `receive` block, which is the problem.
          case PoolWorker.send_command(worker_state, command, enhanced_args, operation_timeout) do
            # ...
          end
        end,
        pool_timeout
      )
    # ...
end
```

This needs to be refactored to move the blocking I/O out of the `SessionPool` GenServer and into the process that is making the request.

---

### 4. Recommendations and Refactoring Path

The following steps will resolve the identified issues and align your implementation with `NimblePool`'s design for true concurrency.

#### **Step 1: Make `execute_in_session` a Public Client Function**

The call to `checkout!` should not be hidden inside a `GenServer.call`. It should be in a public function that is executed by the actual client process that needs the result.

#### **Step 2: Refactor the `checkout!` Logic**

The anonymous function passed to `checkout!` should perform the `send` and `receive` itself. The `PoolWorker` module should not be involved in the `receive` logic for a request.

Here is a corrected implementation of `DSPex.PythonBridge.SessionPool.execute_in_session/4`:

```elixir
# In DSPex.PythonBridge.SessionPool.ex

# This is now a public function, not a GenServer.call handler.
# It will be called directly by the client process.
def execute_in_session(session_id, command, args, opts \\ []) do
  # Get pool configuration
  pool_name = # ... get from config or state if needed
  pool_timeout = Keyword.get(opts, :pool_timeout, @default_checkout_timeout)
  operation_timeout = Keyword.get(opts, :timeout, @default_operation_timeout)

  # Prepare the request payload ONCE before checkout.
  # The PoolWorker no longer needs a public `send_command` function.
  request_id = # ... generate a unique request ID
  enhanced_args = Map.put(args, :session_id, session_id)
  request_payload = Protocol.encode_request(request_id, command, enhanced_args)

  # The checkout function now runs in THIS client process
  NimblePool.checkout!(
    pool_name,
    {:session, session_id},
    fn {_from, worker_state} ->
      # The client_state is the full worker_state, from which we get the port.
      port = worker_state.port

      # 1. Send the command to the port
      send(port, {self(), {:command, request_payload}})

      # 2. Wait for the response here (this blocks the client, not the pool manager)
      receive do
        {^port, {:data, data}} ->
          case Protocol.decode_response(data) do
            {:ok, ^request_id, result} ->
              # Success! Return the result and :ok to signal a clean checkin.
              {{:ok, result}, :ok}

            {:error, ^request_id, error_reason} ->
              # Python returned an error. Return it and signal a clean checkin.
              {{:error, error_reason}, :ok}
            
            other_response ->
              # Unexpected response, maybe a response for a different request.
              # This indicates a problem. We will close this worker.
              Logger.error("Received unexpected response: #{inspect(other_response)}")
              {{:error, :unexpected_response}, :close}
          end
      after
        operation_timeout ->
          # The operation timed out. We must assume the worker is in a bad state.
          exit({:timeout, "Operation timed out after #{operation_timeout}ms"})
      end
    end,
    pool_timeout
  )
end
```

#### **Step 3: Simplify `PoolWorker`**

With the logic moved, `PoolWorker` becomes simpler.

1.  Remove the public `send_command/4` and `send_and_await_response/4` functions. They are no longer needed.
2.  Remove the `handle_info/2` logic that deals with responses (`handle_port_data`, `handle_response`), as responses are now handled by the client that checked out the worker. You should still keep the `handle_info` clause for `{:exit_status, status}` to detect when a worker process dies unexpectedly.

### Conclusion

Your project has a solid foundation for its pooling architecture. The core issue is a misunderstanding of where the blocking `receive` operation should occur in the `NimblePool` pattern. By refactoring the `checkout!` logic to move the `send`/`receive` block from the `SessionPool` GenServer into the client-side function, you will unlock true concurrency and create a robust, high-performance system that correctly leverages the power of `NimblePool`.



---
## Fix Plan
File: docs/NIMBLEPOOL_FIX_PLAN.md
---

# NimblePool Integration Fix Plan

## Executive Summary

Based on deep analysis of the current DSPex NimblePool implementation and the provided documentation, I've identified critical architectural flaws that are preventing proper concurrent operation. The main issue is that the SessionPool GenServer is blocking on I/O operations during checkout, creating a bottleneck that serializes all Python operations.

This document provides a comprehensive plan to fix these issues and achieve true concurrent pool operation.

## Current Issues

### 1. Critical: Pool Manager Bottleneck

**Problem**: The SessionPool GenServer executes blocking I/O operations within the checkout callback, preventing concurrent operations.

**Current Flow**:
1. Client calls `SessionPool.execute_in_session(...)`
2. SessionPool GenServer receives the call
3. GenServer calls `NimblePool.checkout!` 
4. Anonymous function runs **inside GenServer process**
5. Function calls `PoolWorker.send_command` which blocks on `receive`
6. **Entire SessionPool is blocked** until Python responds

**Impact**: Complete loss of concurrency - all operations are serialized through the SessionPool process.

### 2. Incorrect init_worker Return Type

**Problem**: `PoolWorker.init_worker/1` returns `{:error, reason}` on failure, but NimblePool expects only `{:ok, ...}` or `{:async, ...}`.

**Impact**: Pool supervisor crashes on worker initialization failure instead of retrying.

### 3. Unreachable handle_info Logic

**Problem**: `PoolWorker.handle_info/2` contains response handling logic that is never reached because ports are connected to client processes during checkout.

**Impact**: Dead code that adds confusion and complexity.

## Root Cause Analysis

The fundamental misunderstanding is about **where blocking operations should occur** in the NimblePool pattern:

- **Incorrect**: Blocking inside the pool manager (GenServer)
- **Correct**: Blocking in the client process that needs the result

NimblePool's design principle is to hand off resources to clients so they can perform potentially long I/O operations without blocking the pool manager or other clients.

## Solution Architecture

### Key Design Principles

1. **Client-side Blocking**: Move all blocking I/O to client processes
2. **Direct Port Communication**: Clients communicate directly with ports after checkout
3. **Pool Manager as Coordinator**: SessionPool only manages checkout/checkin, not I/O
4. **Worker Simplification**: Remove unnecessary intermediary functions

### Architectural Changes

```
Current (Incorrect):
Client -> SessionPool.execute_in_session (GenServer.call)
         -> NimblePool.checkout! (blocks GenServer)
            -> PoolWorker.send_command (blocks on receive)
               -> Port communication

Proposed (Correct):
Client -> SessionPool.execute_in_session (public function)
         -> NimblePool.checkout! (blocks client only)
            -> Direct port communication (send/receive in client)
```

## Implementation Plan

### Phase 1: Fix Critical Blocking Issue

#### Step 1.1: Refactor SessionPool.execute_in_session

Convert from GenServer handler to public client function:

```elixir
# From GenServer handler:
def handle_call({:execute_in_session, ...}, _from, state) do
  # Blocking logic here - WRONG!
end

# To public function:
def execute_in_session(session_id, command, args, opts \\ []) do
  # This runs in client process - CORRECT!
  pool_name = get_pool_name()
  
  NimblePool.checkout!(
    pool_name,
    {:session, session_id},
    fn {_from, worker_state} ->
      # Direct port communication here
      port = worker_state.port
      # send/receive logic
    end
  )
end
```

#### Step 1.2: Move Protocol Logic to Client

The client function should handle:
- Request encoding
- Sending to port
- Receiving response
- Response decoding
- Error handling

#### Step 1.3: Update Session Tracking

Since we're no longer going through GenServer.call, we need alternative session tracking:
- Option 1: Separate session registry
- Option 2: ETS table for session metadata
- Option 3: Lightweight GenServer just for session tracking

### Phase 2: Fix PoolWorker Issues

#### Step 2.1: Fix init_worker Return Type

```elixir
def init_worker(pool_state) do
  # ...
  case send_initialization_ping(worker_state) do
    {:ok, updated_state} ->
      {:ok, updated_state, pool_state}
    
    {:error, reason} ->
      # Don't return error tuple - raise instead
      raise "Worker initialization failed: #{inspect(reason)}"
  end
end
```

#### Step 2.2: Remove Unnecessary Functions

Remove from PoolWorker:
- `send_command/4` - no longer needed
- `send_and_await_response/4` - moved to client
- Response handling in `handle_info/2` - not reachable

Keep in PoolWorker:
- NimblePool callbacks
- Worker lifecycle management
- Port death detection

### Phase 3: Simplify and Optimize

#### Step 3.1: Create Helper Module

Create `DSPex.PythonBridge.Protocol` for shared logic:
- Request encoding
- Response decoding  
- Error handling patterns

#### Step 3.2: Update Adapter Layer

Ensure `DSPex.Adapters.PythonPool` correctly uses the new public API.

#### Step 3.3: Session Management Optimization

Implement efficient session tracking that doesn't require GenServer calls for every operation.

## Migration Strategy

### Step-by-Step Migration

1. **Create New Modules**: Start with new implementations alongside existing code
2. **Test in Isolation**: Verify new implementation with dedicated tests
3. **Feature Flag**: Add temporary flag to switch between implementations
4. **Gradual Rollout**: Test with small subset of operations first
5. **Full Migration**: Switch all operations to new implementation
6. **Cleanup**: Remove old implementation and feature flag

### Backwards Compatibility

During migration, maintain API compatibility:

```elixir
# Temporary adapter pattern
def execute_in_session(session_id, command, args, opts) do
  if use_new_implementation?() do
    execute_in_session_v2(session_id, command, args, opts)
  else
    # Old GenServer.call approach
    GenServer.call(__MODULE__, {:execute_in_session, session_id, command, args, opts})
  end
end
```

## Testing Strategy

### Unit Tests

1. **PoolWorker Tests**
   - Test init_worker with various scenarios
   - Verify proper error handling (raises on init failure)
   - Test worker lifecycle callbacks

2. **Protocol Tests**
   - Test request/response encoding/decoding
   - Test error response handling
   - Test timeout scenarios

### Integration Tests

1. **Concurrency Tests**
   - Verify multiple clients can execute simultaneously
   - Measure throughput improvement
   - Test session isolation

2. **Failure Scenario Tests**
   - Worker death during operation
   - Network/protocol errors
   - Timeout handling

3. **Load Tests**
   - High concurrent load
   - Long-running operations
   - Pool exhaustion scenarios

## Expected Outcomes

### Performance Improvements

- **Concurrency**: True parallel execution of Python operations
- **Throughput**: N-fold increase where N = pool size
- **Latency**: Reduced queueing delays for concurrent requests

### Reliability Improvements

- **Fault Isolation**: Worker failures don't block entire pool
- **Better Error Handling**: Clear error propagation to clients
- **Resource Management**: Proper cleanup on all error paths

### Code Quality Improvements

- **Simplified Architecture**: Clear separation of concerns
- **Reduced Complexity**: Remove unnecessary intermediary layers
- **Better Testability**: Easier to test individual components

## Risk Mitigation

### Potential Risks

1. **Breaking Changes**: Client API changes
   - Mitigation: Phased migration with compatibility layer

2. **Session State Complexity**: Managing sessions without central GenServer
   - Mitigation: Use ETS or Registry for session tracking

3. **Error Handling Changes**: Different error propagation patterns
   - Mitigation: Comprehensive error mapping and testing

## Implementation Timeline

### Week 1: Foundation
- Fix init_worker return type
- Create Protocol helper module
- Set up new test infrastructure

### Week 2: Core Refactoring
- Implement new execute_in_session
- Remove blocking from checkout
- Update PoolWorker

### Week 3: Integration
- Update adapter layer
- Implement session tracking
- Migration compatibility layer

### Week 4: Testing and Rollout
- Comprehensive testing
- Performance benchmarking
- Gradual production rollout

## Conclusion

This plan addresses the fundamental architectural issues in the current NimblePool integration. By moving blocking operations to client processes and simplifying the worker implementation, we'll achieve true concurrent pool operation with better performance and reliability.

The key insight is understanding NimblePool's design philosophy: the pool manager coordinates resource allocation, but clients perform the actual work. This separation is crucial for achieving concurrency and scalability.

---
## V2 Implementation Challenges
File: docs/NIMBLEPOOL_V2_CHALLENGES.md
---

# NimblePool V2 Implementation Challenges

## Current Status

I attempted to refactor the DSPex pool implementation to fix a critical architectural flaw where all operations are serialized through the SessionPool GenServer, preventing true concurrent execution. However, I've encountered several blocking issues during implementation.

## Key Challenges

### 1. Worker Initialization Timeout

**Problem**: When starting PoolWorkerV2 with NimblePool, the initialization ping times out after 5 seconds.

**Symptoms**:
- Worker process starts successfully
- Python script launches in pool-worker mode
- Init ping is sent but no response is received
- Timeout occurs, causing worker initialization to fail

**Debug Output**:
```
19:13:53.900 [debug] Sending initialization ping for worker worker_18_1752470031201073
19:13:55.467 [info] Ping result: {:error, {:timeout, {NimblePool, :checkout, [DSPex.PythonBridge.SessionPoolV2_pool]}}}
```

**What I've Tried**:
- Added extensive logging to trace the issue
- Verified Python script supports pool-worker mode
- Checked port communication
- Added stderr_to_stdout to capture Python errors

### 2. NimblePool Integration Complexity

**Problem**: The interaction between NimblePool's lazy initialization and our worker startup is not working as expected.

**Details**:
- With `lazy: true`, workers should be created on first checkout
- But checkout is timing out before workers can initialize
- The timeout appears to be at the NimblePool level, not the worker level

### 3. Port Communication Issues

**Problem**: Uncertain if the 4-byte length-prefixed packet communication is working correctly in the refactored version.

**Observations**:
- Python script starts and shuts down cleanly
- No error messages from Python side
- But Elixir side doesn't receive init ping response

### 4. Testing Infrastructure

**Problem**: The existing test infrastructure assumes the V1 implementation, making it difficult to test V2 in isolation.

**Issues**:
- Application supervisor starts V1 components
- Name conflicts when trying to start V2 components
- Need to stop/restart parts of the supervision tree

## Specific Technical Questions

1. **NimblePool Checkout Function Arity**: Is the checkout function definitely supposed to be 2-arity `fn from, worker_state ->`? The error suggests it expects this, but examples show both patterns.

2. **Port Message Format**: When using `{:packet, 4}` mode, is `send(port, {self(), {:command, data}})` the correct way to send? Or should it be `Port.command(port, data)`?

3. **Worker Initialization Timing**: Should worker initialization (including Python process startup) happen in `init_worker/1` or should it be deferred somehow?

4. **Lazy vs Eager**: With `lazy: true`, how does NimblePool handle the first checkout if no workers exist yet?

## What's Working

- Python script properly supports pool-worker mode
- Basic NimblePool structure is set up correctly
- Session tracking via ETS is implemented
- Protocol encoding/decoding is functional

## What's Not Working

- Worker initialization completion
- First checkout after pool startup
- Port communication during init
- Integration with existing test suite

## Potential Root Causes

1. **Packet Mode Mismatch**: The Python side might expect different packet framing than what Elixir is sending

2. **Process Ownership**: During init_worker, the port might not be properly connected to the right process

3. **Timing Issues**: The Python script might need more time to initialize before accepting commands

4. **Message Format**: The init ping message format might not match what Python expects

## Next Steps Needed

1. Verify the exact message format Python expects for init ping
2. Test port communication in isolation without NimblePool
3. Understand NimblePool's lazy initialization sequence better
4. Consider simpler alternatives to full V2 refactoring

## Alternative Approaches

If V2 proves too complex:

1. **Minimal Fix**: Just move the blocking receive out of SessionPool without full refactoring
2. **Different Pool**: Consider Poolboy or other pooling libraries
3. **Custom Pool**: Build a simpler pool specifically for our use case
4. **Hybrid Approach**: Keep V1 structure but add async message passing

## Help Needed

I need assistance with:
1. Understanding why the init ping response isn't being received
2. Proper NimblePool lazy initialization patterns
3. Debugging port communication in packet mode
4. Best practices for testing pooled GenServers

The core architecture of V2 is sound - it correctly moves blocking operations to client processes. But the implementation details around worker initialization and port communication need to be resolved.

---
## Migration Guide
File: docs/POOL_V2_MIGRATION_GUIDE.md
---

# Pool V2 Migration Guide

## Overview

This guide describes how to migrate from the current SessionPool/PoolWorker implementation (V1) to the refactored V2 implementation that properly implements the NimblePool pattern for true concurrent execution.

## Why Migrate?

### V1 Problems
- **Serialized Execution**: All operations go through SessionPool GenServer, creating a bottleneck
- **No True Concurrency**: Despite having a pool, operations execute one at a time
- **Poor Performance**: High latency for concurrent requests due to queueing

### V2 Benefits
- **True Concurrency**: Operations execute in parallel in client processes
- **Better Performance**: N-fold throughput improvement (N = pool size)
- **Proper NimblePool Pattern**: Follows documented best practices
- **Simplified Architecture**: Cleaner separation of concerns

## Migration Strategy

### Phase 1: Parallel Implementation (Week 1)

1. **Keep V1 Running**: Don't modify existing code initially
2. **Deploy V2 Modules**: Add new modules alongside existing ones:
   - `SessionPoolV2`
   - `PoolWorkerV2`
   - `PythonPoolV2`

3. **Configuration Switch**: Add config to choose implementation:
   ```elixir
   config :dspex,
     pool_version: :v1  # or :v2
   ```

4. **Adapter Registry Update**: Modify registry to return correct adapter:
   ```elixir
   def get_adapter do
     case Application.get_env(:dspex, :pool_version, :v1) do
       :v1 -> DSPex.Adapters.PythonPool
       :v2 -> DSPex.Adapters.PythonPoolV2
     end
   end
   ```

### Phase 2: Testing & Validation (Week 2)

1. **Unit Tests**: Run both V1 and V2 tests in parallel
2. **Integration Tests**: Add tests that verify V2 behavior
3. **Performance Tests**: Benchmark V1 vs V2 performance
4. **Load Tests**: Verify V2 handles high concurrency correctly

### Phase 3: Gradual Rollout (Week 3)

1. **Development Environment**: Switch dev to V2 first
2. **Staging Environment**: Run V2 for subset of operations
3. **Production Canary**: Route small % of traffic to V2
4. **Monitor Metrics**: Track performance and error rates

### Phase 4: Full Migration (Week 4)

1. **Switch Default**: Change default from V1 to V2
2. **Deprecation Notice**: Mark V1 as deprecated
3. **Final Validation**: Ensure all systems using V2
4. **Cleanup**: Remove V1 code after burn-in period

## Code Changes Required

### Supervisor Configuration

Update `PoolSupervisor` to conditionally start V1 or V2:

```elixir
defmodule DSPex.PythonBridge.PoolSupervisor do
  def init(_args) do
    children = case Application.get_env(:dspex, :pool_version, :v1) do
      :v1 ->
        [{DSPex.PythonBridge.SessionPool, 
          pool_size: pool_size,
          overflow: overflow,
          name: DSPex.PythonBridge.SessionPool}]
      
      :v2 ->
        [{DSPex.PythonBridge.SessionPoolV2,
          pool_size: pool_size,
          overflow: overflow,
          name: DSPex.PythonBridge.SessionPoolV2}]
    end
    
    Supervisor.init(children, strategy: :one_for_all)
  end
end
```

### Application Code

No changes required! The adapter interface remains the same:

```elixir
# This code works with both V1 and V2
adapter = DSPex.Adapters.Registry.get_adapter()
{:ok, program_id} = adapter.create_program(config)
{:ok, result} = adapter.execute_program(program_id, inputs)
```

### Test Updates

Add environment variable to control which version tests run:

```elixir
# In test_helper.exs
if System.get_env("POOL_VERSION") == "v2" do
  Application.put_env(:dspex, :pool_version, :v2)
end
```

Run tests for both versions:
```bash
# Test V1
mix test

# Test V2
POOL_VERSION=v2 mix test
```

## Monitoring & Rollback

### Key Metrics to Monitor

1. **Performance Metrics**
   - Request latency (p50, p95, p99)
   - Throughput (requests/second)
   - Pool utilization
   - Worker creation/destruction rate

2. **Error Metrics**
   - Error rates by type
   - Timeout rates
   - Worker crash rates

3. **Resource Metrics**
   - Memory usage
   - CPU usage
   - Port/file descriptor usage

### Rollback Plan

If issues arise, rollback is simple:

1. **Immediate**: Change config from `:v2` to `:v1`
2. **Restart**: Restart application to pick up config
3. **Verify**: Confirm V1 is active via stats/logs

## Validation Checklist

Before considering migration complete:

- [ ] All unit tests pass for V2
- [ ] Integration tests show correct concurrent behavior
- [ ] Performance benchmarks show improvement
- [ ] Load tests pass without errors
- [ ] Session isolation verified
- [ ] Error handling works correctly
- [ ] Monitoring shows stable metrics
- [ ] No increase in error rates
- [ ] Memory usage is stable
- [ ] Documentation updated

## Common Issues & Solutions

### Issue: "module not found" errors
**Solution**: Ensure V2 modules are compiled and included in release

### Issue: Different error messages between V1/V2
**Solution**: Update error handling to normalize messages

### Issue: Session tracking differences
**Solution**: Ensure ETS table is properly initialized

### Issue: Performance regression in specific scenarios
**Solution**: Check pool size configuration and timeout settings

## Post-Migration

After successful migration:

1. **Remove V1 Code**: After 2-4 weeks of stable operation
2. **Update Documentation**: Remove references to V1
3. **Simplify Configuration**: Remove version switching logic
4. **Optimize Further**: Tune pool parameters based on production data

## Support

For migration support:
- Check logs for migration-related messages
- Monitor the `:dspex` application metrics
- Review error reports for V2-specific issues

The migration is designed to be safe and reversible at any point.

---
# Key Source Code Files
---

---
## SessionPool V1 (Current)
File: lib/dspex/python_bridge/session_pool.ex
---

defmodule DSPex.PythonBridge.SessionPool do
  @moduledoc """
  Session-aware pool manager for Python bridge workers.

  This module manages a pool of Python processes using NimblePool and provides
  session-based isolation for concurrent DSPy operations. Each session gets
  exclusive access to a worker during operations, ensuring program isolation.

  ## Features

  - Dynamic pool sizing based on system resources
  - Session-based worker allocation
  - Automatic worker health monitoring
  - Request queuing and timeout handling
  - Metrics and performance tracking
  - Graceful shutdown and cleanup

  ## Architecture

  ```
  SessionPool (Supervisor)
  ├── Pool Manager (GenServer)
  └── NimblePool
      ├── Worker 1 (Python Process)
      ├── Worker 2 (Python Process)
      └── Worker N (Python Process)
  ```

  ## Usage

      # Start the pool
      {:ok, _} = DSPex.PythonBridge.SessionPool.start_link()
      
      # Execute in session
      {:ok, result} = SessionPool.execute_in_session("session_123", :create_program, %{...})
      
      # Get pool status
      status = SessionPool.get_pool_status()
  """

  use GenServer
  require Logger

  alias DSPex.PythonBridge.PoolWorker

  # Pool configuration defaults
  @default_pool_size System.schedulers_online() * 2
  @default_overflow 2
  @default_checkout_timeout 5_000
  @default_operation_timeout 30_000
  @health_check_interval 30_000
  # 5 minutes
  @session_cleanup_interval 300_000

  # State structure
  defstruct [
    :pool_name,
    :pool_size,
    :overflow,
    :sessions,
    :metrics,
    :health_check_ref,
    :cleanup_ref,
    :started_at
  ]

  ## Public API

  @doc """
  Starts the session pool with the given options.

  ## Options

  - `:name` - The name to register the pool manager (default: `__MODULE__`)
  - `:pool_size` - Number of worker processes (default: schedulers * 2)
  - `:overflow` - Maximum additional workers when pool is full (default: 2)
  - `:checkout_timeout` - Maximum time to wait for available worker (default: 5000ms)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Executes a command within a session context.

  Checks out a worker from the pool, binds it to the session,
  executes the command, and returns the worker to the pool.

  ## Parameters

  - `session_id` - Unique session identifier
  - `command` - The command to execute (atom)
  - `args` - Command arguments (map)
  - `opts` - Options including timeouts

  ## Examples

      {:ok, program_id} = SessionPool.execute_in_session(
        "user_123_session", 
        :create_program,
        %{signature: %{inputs: [...], outputs: [...]}}
      )
  """
  def execute_in_session(session_id, command, args, opts \\ []) do
    GenServer.call(__MODULE__, {:execute_in_session, session_id, command, args, opts})
  end

  @doc """
  Executes a command without session binding.

  Useful for stateless operations that don't require session isolation.
  """
  def execute_anonymous(command, args, opts \\ []) do
    GenServer.call(__MODULE__, {:execute_anonymous, command, args, opts})
  end

  @doc """
  Ends a session and cleans up associated resources.
  """
  def end_session(session_id) do
    GenServer.call(__MODULE__, {:end_session, session_id})
  end

  @doc """
  Gets the current status of the pool including metrics.
  """
  def get_pool_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Gets detailed information about active sessions.
  """
  def get_session_info do
    GenServer.call(__MODULE__, :get_sessions)
  end

  @doc """
  Performs a health check on all workers in the pool.
  """
  def health_check do
    GenServer.call(__MODULE__, :health_check, 10_000)
  end

  @doc """
  Gracefully shuts down the pool, ending all sessions.
  """
  def shutdown(timeout \\ 10_000) do
    GenServer.call(__MODULE__, :shutdown, timeout)
  end

  @doc """
  Manually triggers cleanup of stale sessions.

  Called periodically by the pool monitor.
  """
  def cleanup_stale_sessions do
    GenServer.cast(__MODULE__, :cleanup_stale_sessions)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    # Parse configuration
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    overflow = Keyword.get(opts, :overflow, @default_overflow)
    name = Keyword.get(opts, :name, __MODULE__)
    pool_name = make_pool_name(name)

    # Start NimblePool as part of initialization
    pool_config = [
      worker: {PoolWorker, []},
      pool_size: pool_size,
      max_overflow: overflow,
      # Important: create workers on-demand, not eagerly
      lazy: true,
      name: pool_name
    ]

    case NimblePool.start_link(pool_config) do
      {:ok, _pool_pid} ->
        # Schedule periodic tasks
        health_check_ref = schedule_health_check()
        cleanup_ref = schedule_cleanup()

        state = %__MODULE__{
          pool_name: pool_name,
          pool_size: pool_size,
          overflow: overflow,
          sessions: %{},
          metrics: init_metrics(),
          health_check_ref: health_check_ref,
          cleanup_ref: cleanup_ref,
          started_at: System.monotonic_time(:millisecond)
        }

        Logger.info("Session pool started with #{pool_size} workers, #{overflow} overflow")
        {:ok, state}

      {:error, reason} ->
        {:stop, {:pool_start_failed, reason}}
    end
  end

  @impl true
  def handle_call({:execute_in_session, session_id, command, args, opts}, _from, state) do
    pool_timeout = Keyword.get(opts, :pool_timeout, @default_checkout_timeout)
    operation_timeout = Keyword.get(opts, :timeout, @default_operation_timeout)

    # Add session context
    enhanced_args = Map.put(args, :session_id, session_id)

    # Track session
    sessions =
      Map.put_new_lazy(state.sessions, session_id, fn ->
        %{
          started_at: System.monotonic_time(:millisecond),
          last_activity: System.monotonic_time(:millisecond),
          operations: 0,
          programs: MapSet.new()
        }
      end)

    updated_state = %{state | sessions: sessions}

    # Execute with NimblePool
    result =
      try do
        NimblePool.checkout!(
          state.pool_name,
          {:session, session_id},
          fn _from, worker_state ->
            # Execute command on worker
            case PoolWorker.send_command(worker_state, command, enhanced_args, operation_timeout) do
              {:ok, response, updated_state} ->
                {{:ok, response["result"]}, updated_state, :ok}

              {:error, reason} ->
                {{:error, reason}, worker_state, :ok}
            end
          end,
          pool_timeout
        )
      catch
        :exit, {:timeout, _} ->
          update_metrics(updated_state, :pool_timeout)
          {:error, :pool_timeout}

        :exit, reason ->
          Logger.error("Pool checkout failed: #{inspect(reason)}")
          {:error, {:pool_error, reason}}
      end

    # Update session activity
    final_state = update_session_activity(updated_state, session_id)
    {:reply, result, final_state}
  end

  @impl true
  def handle_call({:execute_anonymous, command, args, opts}, _from, state) do
    pool_timeout = Keyword.get(opts, :pool_timeout, @default_checkout_timeout)
    operation_timeout = Keyword.get(opts, :timeout, @default_operation_timeout)

    result =
      try do
        NimblePool.checkout!(
          state.pool_name,
          :anonymous,
          fn _from, worker_state ->
            case PoolWorker.send_command(worker_state, command, args, operation_timeout) do
              {:ok, response, updated_state} ->
                {{:ok, response["result"]}, updated_state, :ok}

              {:error, reason} ->
                {{:error, reason}, worker_state, :ok}
            end
          end,
          pool_timeout
        )
      catch
        :exit, {:timeout, _} ->
          update_metrics(state, :pool_timeout)
          {:error, :pool_timeout}

        :exit, reason ->
          Logger.error("Pool checkout failed: #{inspect(reason)}")
          {:error, {:pool_error, reason}}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:track_session, session_id}, _from, state) do
    sessions =
      Map.put_new_lazy(state.sessions, session_id, fn ->
        %{
          started_at: System.monotonic_time(:millisecond),
          last_activity: System.monotonic_time(:millisecond),
          operations: 0,
          programs: MapSet.new()
        }
      end)

    {:reply, :ok, %{state | sessions: sessions}}
  end

  @impl true
  def handle_call({:end_session, session_id}, _from, state) do
    case Map.pop(state.sessions, session_id) do
      {nil, _sessions} ->
        {:reply, {:error, :session_not_found}, state}

      {session_info, remaining_sessions} ->
        # Update metrics
        metrics = update_session_end_metrics(state.metrics, session_info)

        # Cleanup session in workers
        cleanup_session_in_workers(session_id)

        {:reply, :ok, %{state | sessions: remaining_sessions, metrics: metrics}}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      pool_size: state.pool_size,
      max_overflow: state.overflow,
      active_sessions: map_size(state.sessions),
      metrics: state.metrics,
      uptime_ms: System.monotonic_time(:millisecond) - state.started_at,
      pool_status: get_nimble_pool_status()
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_sessions, _from, state) do
    session_info =
      Map.new(state.sessions, fn {id, info} ->
        {id, Map.put(info, :session_id, id)}
      end)

    {:reply, session_info, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    health_results = perform_pool_health_check()

    metrics =
      Map.put(state.metrics, :last_health_check, %{
        timestamp: DateTime.utc_now(),
        results: health_results
      })

    {:reply, health_results, %{state | metrics: metrics}}
  end

  @impl true
  def handle_call(:shutdown, _from, state) do
    Logger.info("Shutting down session pool gracefully")

    # Cancel scheduled tasks
    Process.cancel_timer(state.health_check_ref)
    Process.cancel_timer(state.cleanup_ref)

    # End all sessions
    for {session_id, _} <- state.sessions do
      cleanup_session_in_workers(session_id)
    end

    # Stop the pool
    :ok = NimblePool.stop(state.pool_name, :shutdown, 5_000)

    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Perform health check asynchronously
    Task.start(fn -> perform_pool_health_check() end)

    # Reschedule
    health_check_ref = schedule_health_check()

    {:noreply, %{state | health_check_ref: health_check_ref}}
  end

  @impl true
  def handle_info(:cleanup_stale_sessions, state) do
    now = System.monotonic_time(:millisecond)
    # 1 hour
    stale_timeout = 3600_000

    {stale, active} =
      Map.split_with(state.sessions, fn {_id, info} ->
        now - info.last_activity > stale_timeout
      end)

    # Cleanup stale sessions
    for {session_id, _} <- stale do
      Logger.warning("Cleaning up stale session: #{session_id}")
      cleanup_session_in_workers(session_id)
    end

    # Update metrics
    metrics =
      if map_size(stale) > 0 do
        Map.update(
          state.metrics,
          :stale_sessions_cleaned,
          map_size(stale),
          &(&1 + map_size(stale))
        )
      else
        state.metrics
      end

    # Reschedule
    cleanup_ref = schedule_cleanup()

    {:noreply, %{state | sessions: active, metrics: metrics, cleanup_ref: cleanup_ref}}
  end

  @impl true
  def handle_cast(:cleanup_stale_sessions, state) do
    # Manual trigger of stale session cleanup
    handle_info(:cleanup_stale_sessions, state)
  end

  ## Private Functions

  defp make_pool_name(name) when is_atom(name) do
    :"#{name}_pool"
  end

  defp update_session_activity(state, session_id) do
    sessions =
      Map.update(state.sessions, session_id, nil, fn session ->
        %{
          session
          | last_activity: System.monotonic_time(:millisecond),
            operations: session.operations + 1
        }
      end)

    %{state | sessions: sessions}
  end

  defp update_metrics(state, metric) do
    metrics =
      case metric do
        :pool_timeout ->
          Map.update(state.metrics, :pool_timeouts, 1, &(&1 + 1))

        _ ->
          state.metrics
      end

    %{state | metrics: metrics}
  end

  defp init_metrics do
    %{
      total_operations: 0,
      successful_operations: 0,
      failed_operations: 0,
      total_sessions: 0,
      average_session_duration_ms: 0,
      pool_timeouts: 0,
      worker_errors: 0,
      stale_sessions_cleaned: 0
    }
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_stale_sessions, @session_cleanup_interval)
  end

  defp get_nimble_pool_status do
    # Get pool information from NimblePool
    # This is a simplified version - actual implementation would
    # need to interface with NimblePool's internals
    %{
      ready: :unknown,
      busy: :unknown,
      overflow: :unknown
    }
  end

  defp perform_pool_health_check do
    # Check health of all workers
    # This would iterate through workers and check their health
    %{
      healthy_workers: 0,
      unhealthy_workers: 0,
      total_workers: 0
    }
  end

  defp cleanup_session_in_workers(_session_id) do
    # During shutdown, we don't need to clean up individual sessions
    # as all workers will be terminated anyway
    :ok
  end

  defp update_session_end_metrics(metrics, session_info) do
    duration = System.monotonic_time(:millisecond) - session_info.started_at

    metrics
    |> Map.update(:total_sessions, 1, &(&1 + 1))
    |> Map.update(:average_session_duration_ms, duration, fn avg ->
      # Simple moving average
      sessions = metrics.total_sessions + 1
      (avg * (sessions - 1) + duration) / sessions
    end)
  end

  ## Supervisor Integration

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 10_000
    }
  end
end


---
## SessionPool V2 (Refactored)
File: lib/dspex/python_bridge/session_pool_v2.ex
---

defmodule DSPex.PythonBridge.SessionPoolV2 do
  @moduledoc """
  Refactored Session-aware pool manager for Python bridge workers.
  
  This version correctly implements the NimblePool pattern by moving blocking
  I/O operations to client processes instead of the pool manager GenServer.
  
  Key differences from V1:
  - execute_in_session/4 is a public function, not a GenServer call
  - Blocking receive operations happen in client processes
  - Direct port communication without intermediary functions
  - Simplified session tracking using ETS
  """
  
  use GenServer
  require Logger
  
  alias DSPex.PythonBridge.{PoolWorker, Protocol}
  
  # Configuration defaults
  @default_pool_size System.schedulers_online() * 2
  @default_overflow 2
  @default_checkout_timeout 5_000
  @default_operation_timeout 30_000
  @health_check_interval 30_000
  @session_cleanup_interval 300_000
  
  # ETS table for session tracking
  @session_table :dspex_pool_sessions
  
  # State structure
  defstruct [
    :pool_name,
    :pool_pid,
    :pool_size,
    :overflow,
    :health_check_ref,
    :cleanup_ref,
    :started_at
  ]
  
  ## Public API - Client Functions
  
  @doc """
  Executes a command within a session context.
  
  This function runs in the CLIENT process, not the pool manager.
  It checks out a worker, performs the operation, and returns the worker.
  """
  def execute_in_session(session_id, command, args, opts \\ []) do
    pool_name = get_pool_name()
    pool_timeout = Keyword.get(opts, :pool_timeout, @default_checkout_timeout)
    operation_timeout = Keyword.get(opts, :timeout, @default_operation_timeout)
    
    # Track session
    track_session(session_id)
    
    # Generate request ID
    request_id = System.unique_integer([:positive, :monotonic])
    
    # Add session context to args
    enhanced_args = Map.put(args, :session_id, session_id)
    
    # Encode request once before checkout
    request_payload = Protocol.encode_request(request_id, command, enhanced_args)
    
    # Checkout and execute - THIS RUNS IN THE CLIENT PROCESS
    Logger.debug("Attempting to checkout from pool: #{inspect(pool_name)}")
    
    try do
      NimblePool.checkout!(
        pool_name,
        {:session, session_id},
        fn _from, worker_state ->
          Logger.debug("Successfully checked out worker: #{inspect(worker_state.worker_id)}")
          # Get the port from worker state
          port = worker_state.port
          
          # Send command to port
          send(port, {self(), {:command, request_payload}})
          
          # Wait for response IN THE CLIENT PROCESS
          receive do
            {^port, {:data, data}} ->
              case Protocol.decode_response(data) do
                {:ok, ^request_id, response} ->
                  # Success - return result and signal clean checkin
                  case response do
                    %{"success" => true, "result" => result} ->
                      {{:ok, result}, :ok}
                    
                    %{"success" => false, "error" => error} ->
                      {{:error, error}, :ok}
                    
                    _ ->
                      Logger.error("Malformed response: #{inspect(response)}")
                      {{:error, :malformed_response}, :close}
                  end
                
                {:ok, other_id, _} ->
                  Logger.error("Response ID mismatch: expected #{request_id}, got #{other_id}")
                  {{:error, :response_mismatch}, :close}
                
                {:error, _id, reason} ->
                  {{:error, reason}, :ok}
                
                {:error, reason} ->
                  Logger.error("Failed to decode response: #{inspect(reason)}")
                  {{:error, {:decode_error, reason}}, :close}
              end
            
            {^port, {:exit_status, status}} ->
              Logger.error("Port exited during operation with status: #{status}")
              exit({:port_died, status})
          after
            operation_timeout ->
              # Operation timed out - exit to trigger worker removal
              Logger.error("Operation timed out after #{operation_timeout}ms")
              exit({:timeout, "Operation timed out after #{operation_timeout}ms"})
          end
        end,
        pool_timeout
      )
    catch
      :exit, {:timeout, _} = reason ->
        {:error, {:pool_timeout, reason}}
      
      :exit, reason ->
        Logger.error("Checkout failed: #{inspect(reason)}")
        {:error, {:checkout_failed, reason}}
    end
  end
  
  @doc """
  Executes a command without session binding.
  
  This function runs in the CLIENT process for anonymous operations.
  """
  def execute_anonymous(command, args, opts \\ []) do
    pool_name = get_pool_name()
    pool_timeout = Keyword.get(opts, :pool_timeout, @default_checkout_timeout)
    operation_timeout = Keyword.get(opts, :timeout, @default_operation_timeout)
    
    # Generate request ID
    request_id = System.unique_integer([:positive, :monotonic])
    
    # Encode request
    request_payload = Protocol.encode_request(request_id, command, args)
    
    # Checkout and execute
    try do
      NimblePool.checkout!(
        pool_name,
        :anonymous,
        fn _from, worker_state ->
          port = worker_state.port
          
          # Send command
          send(port, {self(), {:command, request_payload}})
          
          # Wait for response
          receive do
            {^port, {:data, data}} ->
              case Protocol.decode_response(data) do
                {:ok, ^request_id, response} ->
                  case response do
                    %{"success" => true, "result" => result} ->
                      {{:ok, result}, :ok}
                    
                    %{"success" => false, "error" => error} ->
                      {{:error, error}, :ok}
                    
                    _ ->
                      {{:error, :malformed_response}, :close}
                  end
                
                {:error, reason} ->
                  {{:error, reason}, :close}
              end
            
            {^port, {:exit_status, status}} ->
              exit({:port_died, status})
          after
            operation_timeout ->
              exit({:timeout, "Operation timed out"})
          end
        end,
        pool_timeout
      )
    catch
      :exit, reason ->
        {:error, reason}
    end
  end
  
  ## Session Management Functions
  
  @doc """
  Tracks a session in ETS for monitoring.
  """
  def track_session(session_id) do
    ensure_session_table()
    
    session_info = %{
      session_id: session_id,
      started_at: System.monotonic_time(:millisecond),
      last_activity: System.monotonic_time(:millisecond),
      operations: 0
    }
    
    :ets.insert(@session_table, {session_id, session_info})
    :ok
  end
  
  @doc """
  Updates session activity timestamp.
  """
  def update_session_activity(session_id) do
    ensure_session_table()
    
    case :ets.lookup(@session_table, session_id) do
      [{^session_id, info}] ->
        updated_info = %{info | 
          last_activity: System.monotonic_time(:millisecond),
          operations: info.operations + 1
        }
        :ets.insert(@session_table, {session_id, updated_info})
        :ok
      
      [] ->
        track_session(session_id)
    end
  end
  
  @doc """
  Ends a session and cleans up resources.
  """
  def end_session(session_id) do
    ensure_session_table()
    :ets.delete(@session_table, session_id)
    :ok
  end
  
  @doc """
  Gets information about active sessions.
  """
  def get_session_info do
    ensure_session_table()
    
    :ets.tab2list(@session_table)
    |> Enum.map(fn {_id, info} -> info end)
  end
  
  ## Pool Management API (GenServer)
  
  @doc """
  Starts the session pool manager.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Gets the current pool status.
  """
  def get_pool_status do
    GenServer.call(__MODULE__, :get_status)
  end
  
  @doc """
  Performs a health check on the pool.
  """
  def health_check do
    GenServer.call(__MODULE__, :health_check)
  end
  
  ## GenServer Callbacks
  
  @impl true
  def init(opts) do
    # Initialize session tracking table
    ensure_session_table()
    
    # Parse configuration
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    overflow = Keyword.get(opts, :overflow, @default_overflow)
    pool_name = get_pool_name()
    
    # Start NimblePool
    pool_config = [
      worker: {PoolWorker, []},
      pool_size: pool_size,
      max_overflow: overflow,
      lazy: true,
      name: pool_name
    ]
    
    case NimblePool.start_link(pool_config) do
      {:ok, pool_pid} ->
        # Schedule periodic tasks
        health_check_ref = schedule_health_check()
        cleanup_ref = schedule_cleanup()
        
        state = %__MODULE__{
          pool_name: pool_name,
          pool_pid: pool_pid,
          pool_size: pool_size,
          overflow: overflow,
          health_check_ref: health_check_ref,
          cleanup_ref: cleanup_ref,
          started_at: System.monotonic_time(:millisecond)
        }
        
        Logger.info("Session pool V2 started with #{pool_size} workers, #{overflow} overflow")
        {:ok, state}
      
      {:error, reason} ->
        {:stop, {:pool_start_failed, reason}}
    end
  end
  
  @impl true
  def handle_call(:get_status, _from, state) do
    sessions = get_session_info()
    
    status = %{
      pool_size: state.pool_size,
      max_overflow: state.overflow,
      active_sessions: length(sessions),
      sessions: sessions,
      uptime_ms: System.monotonic_time(:millisecond) - state.started_at
    }
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_call(:health_check, _from, state) do
    # For now, just return a simple status
    # In production, you'd check each worker's health
    {:reply, {:ok, :healthy}, state}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    # Perform periodic health check
    # In production, iterate through workers and check their health
    
    # Reschedule
    health_check_ref = schedule_health_check()
    {:noreply, %{state | health_check_ref: health_check_ref}}
  end
  
  @impl true
  def handle_info(:cleanup_stale_sessions, state) do
    # Clean up stale sessions from ETS
    now = System.monotonic_time(:millisecond)
    stale_timeout = 3600_000 # 1 hour
    
    ensure_session_table()
    
    # Find and remove stale sessions
    stale_sessions = :ets.select(@session_table, [
      {
        {:"$1", %{last_activity: :"$2"}},
        [{:<, :"$2", now - stale_timeout}],
        [:"$1"]
      }
    ])
    
    Enum.each(stale_sessions, fn session_id ->
      Logger.warning("Cleaning up stale session: #{session_id}")
      :ets.delete(@session_table, session_id)
    end)
    
    # Reschedule
    cleanup_ref = schedule_cleanup()
    {:noreply, %{state | cleanup_ref: cleanup_ref}}
  end
  
  @impl true
  def terminate(_reason, state) do
    # Cancel timers
    Process.cancel_timer(state.health_check_ref)
    Process.cancel_timer(state.cleanup_ref)
    
    # Stop the pool
    if state.pool_pid do
      NimblePool.stop(state.pool_name, :shutdown, 5_000)
    end
    
    :ok
  end
  
  ## Private Functions
  
  defp get_pool_name do
    :"#{__MODULE__}_pool"
  end
  
  defp ensure_session_table do
    case :ets.whereis(@session_table) do
      :undefined ->
        :ets.new(@session_table, [:set, :public, :named_table])
      
      _tid ->
        :ok
    end
  end
  
  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_stale_sessions, @session_cleanup_interval)
  end
  
  ## Supervisor Integration
  
  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 10_000
    }
  end
end

---
## PoolWorker V1 (Current)
File: lib/dspex/python_bridge/pool_worker.ex
---

defmodule DSPex.PythonBridge.PoolWorker do
  @moduledoc """
  NimblePool worker implementation for Python bridge processes.

  Each worker manages a single Python process that can handle multiple
  sessions through namespacing. Workers are checked out for session-based
  operations and returned to the pool after use.

  ## Features

  - Session-aware Python process management
  - Automatic process restart on failure
  - Request/response correlation
  - Health monitoring
  - Resource cleanup

  ## Worker Lifecycle

  1. **init_worker/1** - Starts Python process with pool-worker mode
  2. **handle_checkout/4** - Binds worker to session temporarily
  3. **handle_checkin/4** - Resets session binding and cleans up
  4. **terminate_worker/3** - Closes Python process gracefully
  """

  @behaviour NimblePool

  alias DSPex.PythonBridge.Protocol
  require Logger

  # Worker state structure
  defstruct [
    :port,
    :python_path,
    :script_path,
    :worker_id,
    :current_session,
    :request_id,
    :pending_requests,
    :stats,
    :health_status,
    :started_at
  ]

  ## NimblePool Callbacks

  @impl NimblePool
  def init_worker(pool_state) do
    worker_id = generate_worker_id()
    Logger.debug("Initializing pool worker: #{worker_id}")

    # Get Python environment details
    case DSPex.PythonBridge.EnvironmentCheck.validate_environment() do
      {:ok, env_info} ->
        python_path = env_info.python_path
        script_path = env_info.script_path

        # Start Python process in pool-worker mode
        port_opts = [
          :binary,
          :exit_status,
          {:packet, 4},
          {:args, [script_path, "--mode", "pool-worker", "--worker-id", worker_id]}
        ]

        Logger.debug("Starting Python process for worker #{worker_id}")
        port = Port.open({:spawn_executable, python_path}, port_opts)

        # Initialize worker state
        worker_state = %__MODULE__{
          port: port,
          python_path: python_path,
          script_path: script_path,
          worker_id: worker_id,
          current_session: nil,
          request_id: 0,
          pending_requests: %{},
          stats: init_stats(),
          health_status: :initializing,
          started_at: System.monotonic_time(:millisecond)
        }

        # Send initialization ping
        Logger.debug("Sending initialization ping for worker #{worker_id}")

        case send_initialization_ping(worker_state) do
          {:ok, updated_state} ->
            Logger.info("Pool worker #{worker_id} started successfully")
            {:ok, updated_state, pool_state}

          {:error, reason} ->
            Logger.error("Worker #{worker_id} initialization failed: #{inspect(reason)}")
            Port.close(port)
            raise "Worker #{worker_id} initialization failed: #{inspect(reason)}"
        end

      {:error, reason} ->
        Logger.error("Failed to validate Python environment: #{inspect(reason)}")
        raise "Failed to validate Python environment: #{inspect(reason)}"
    end
  end

  @impl NimblePool
  def handle_checkout(checkout_type, from, worker_state, pool_state) do
    case checkout_type do
      {:session, session_id} ->
        handle_session_checkout(session_id, from, worker_state, pool_state)

      :anonymous ->
        handle_anonymous_checkout(from, worker_state, pool_state)

      _ ->
        {:error, {:invalid_checkout_type, checkout_type}}
    end
  end

  @impl NimblePool
  def handle_checkin(checkin_type, _from, worker_state, pool_state) do
    Logger.debug("Worker #{worker_state.worker_id} checkin with type: #{inspect(checkin_type)}")

    updated_state =
      case checkin_type do
        :ok ->
          # Normal checkin - maintain session for affinity
          worker_state

        :session_cleanup ->
          # Session ended - cleanup session data
          cleanup_session(worker_state)

        {:error, _reason} ->
          # Error during checkout - keep healthy for test expectations
          worker_state

        :close ->
          # Worker should be terminated
          worker_state
      end

    # Update stats
    updated_state = update_checkin_stats(updated_state, checkin_type)

    # Determine if worker should be removed
    case should_remove_worker?(updated_state, checkin_type) do
      true ->
        Logger.debug("Worker #{worker_state.worker_id} will be removed")
        {:remove, :closed, pool_state}

      false ->
        {:ok, updated_state, pool_state}
    end
  end

  @impl NimblePool
  def handle_info(message, worker_state) do
    case message do
      {port, {:data, data}} when port == worker_state.port ->
        handle_port_data(data, worker_state)

      {port, {:exit_status, status}} when port == worker_state.port ->
        Logger.error("Python worker exited with status: #{status}")
        {:remove, :port_exited}

      {:check_health} ->
        handle_health_check(worker_state)

      _ ->
        Logger.debug("Pool worker received unknown message: #{inspect(message)}")
        {:ok, worker_state}
    end
  end

  @impl NimblePool
  def terminate_worker(reason, worker_state, pool_state) do
    Logger.info("Terminating pool worker #{worker_state.worker_id}, reason: #{inspect(reason)}")

    # Send shutdown command to Python process
    try do
      send_shutdown_command(worker_state)

      # Give Python process time to cleanup
      receive do
        {port, {:exit_status, _}} when port == worker_state.port ->
          :ok
      after
        1000 ->
          # Force close if not exited
          Port.close(worker_state.port)
      end
    catch
      :error, _ ->
        # Port already closed
        :ok
    end

    {:ok, pool_state}
  end

  ## Checkout Handlers

  defp handle_session_checkout(session_id, {pid, _ref}, worker_state, pool_state) do
    # Bind worker to session and update stats
    updated_state = %{
      worker_state
      | current_session: session_id,
        stats: Map.update(worker_state.stats, :checkouts, 1, &(&1 + 1))
    }

    # Connect port to checking out process
    try do
      # Only connect if it's a real port (not a mock PID)
      if is_port(worker_state.port) do
        Port.connect(worker_state.port, pid)
      end

      {:ok, updated_state, updated_state, pool_state}
    catch
      :error, reason ->
        Logger.error("Failed to connect port to process: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_anonymous_checkout({pid, _ref}, worker_state, pool_state) do
    # Anonymous checkout - no session binding, but update stats
    updated_state = %{
      worker_state
      | stats: Map.update(worker_state.stats, :checkouts, 1, &(&1 + 1))
    }

    try do
      # Only connect if it's a real port (not a mock PID)
      if is_port(updated_state.port) do
        Port.connect(updated_state.port, pid)
      end

      {:ok, updated_state, updated_state, pool_state}
    catch
      :error, reason ->
        Logger.error("Failed to connect port to process: #{inspect(reason)}")
        {:error, reason}
    end
  end

  ## Port Message Handling

  defp handle_port_data(data, worker_state) do
    case Protocol.decode_response(data) do
      {:ok, _id, response} ->
        handle_response(response, worker_state)

      {:error, _id, reason} ->
        Logger.error("Failed to decode response: #{inspect(reason)}")
        {:ok, worker_state}

      {:error, reason} ->
        Logger.error("Failed to decode response: #{inspect(reason)}")
        {:ok, worker_state}
    end
  end

  defp handle_response(response, worker_state) do
    request_id = response["id"] || response[:id]

    case Map.pop(worker_state.pending_requests, request_id) do
      {nil, _pending} ->
        Logger.warning("Received response for unknown request: #{request_id}")
        {:ok, worker_state}

      {{from, _timeout_ref}, remaining_requests} ->
        # Send response to waiting process
        GenServer.reply(from, format_response(response))

        # Update state
        updated_state = %{
          worker_state
          | pending_requests: remaining_requests,
            stats: update_response_stats(worker_state.stats, response)
        }

        {:ok, updated_state}
    end
  end

  ## Health Management

  defp handle_health_check(worker_state) do
    case send_ping(worker_state) do
      {:ok, updated_state} ->
        {:ok, %{updated_state | health_status: :healthy}}

      {:error, _reason} ->
        {:ok, %{worker_state | health_status: :unhealthy}}
    end
  end

  defp send_initialization_ping(worker_state) do
    request_id = worker_state.request_id + 1

    request =
      Protocol.encode_request(request_id, :ping, %{
        initialization: true,
        worker_id: worker_state.worker_id
      })

    case send_and_await_response(worker_state, request, request_id, 5000) do
      {:ok, _response, updated_state} ->
        {:ok, %{updated_state | health_status: :healthy}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_ping(worker_state) do
    request_id = worker_state.request_id + 1

    request =
      Protocol.encode_request(request_id, :ping, %{
        worker_id: worker_state.worker_id,
        current_session: worker_state.current_session
      })

    case send_and_await_response(worker_state, request, request_id, 1000) do
      {:ok, _response, updated_state} ->
        {:ok, updated_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Session Management

  defp cleanup_session(worker_state) do
    case worker_state.current_session do
      nil ->
        worker_state

      session_id ->
        # Send session cleanup command
        request_id = worker_state.request_id + 1

        request =
          Protocol.encode_request(request_id, :cleanup_session, %{
            session_id: session_id
          })

        # Fire and forget - we don't wait for response
        try do
          send(worker_state.port, {self(), {:command, request}})
        catch
          :error, _ -> :ok
        end

        %{worker_state | current_session: nil, request_id: request_id}
    end
  end

  ## Communication Helpers

  defp send_and_await_response(worker_state, request, request_id, timeout) do
    try do
      send(worker_state.port, {self(), {:command, request}})

      receive do
        {port, {:data, data}} when port == worker_state.port ->
          case Protocol.decode_response(data) do
            {:ok, resp_id, response} ->
              if resp_id == request_id do
                {:ok, response, %{worker_state | request_id: request_id}}
              else
                # Wrong response ID
                Logger.warning("Response ID mismatch: expected #{request_id}, got #{resp_id}")
                {:error, :response_mismatch}
              end

            {:error, _resp_id, reason} ->
              {:error, reason}

            {:error, reason} ->
              {:error, reason}
          end

        {port, {:exit_status, status}} when port == worker_state.port ->
          Logger.error("Port exited with status: #{status}")
          {:error, {:port_exited, status}}
      after
        timeout ->
          {:error, :timeout}
      end
    catch
      :error, reason ->
        {:error, {:send_failed, reason}}
    end
  end

  defp send_shutdown_command(worker_state) do
    request_id = worker_state.request_id + 1

    request =
      Protocol.encode_request(request_id, :shutdown, %{
        worker_id: worker_state.worker_id
      })

    send(worker_state.port, {self(), {:command, request}})
  end

  ## Utility Functions

  defp generate_worker_id do
    "worker_#{:erlang.unique_integer([:positive])}_#{:erlang.system_time(:microsecond)}"
  end

  defp init_stats do
    %{
      requests_handled: 0,
      errors: 0,
      sessions_served: 0,
      uptime_ms: 0,
      last_activity: System.monotonic_time(:millisecond),
      checkouts: 0
    }
  end

  defp update_checkin_stats(worker_state, checkin_type) do
    stats = worker_state.stats

    updated_stats =
      case checkin_type do
        :ok ->
          %{stats | requests_handled: stats.requests_handled + 1}

        {:error, _} ->
          %{stats | errors: stats.errors + 1}

        :session_cleanup ->
          %{stats | sessions_served: stats.sessions_served + 1}

        _ ->
          stats
      end

    %{worker_state | stats: updated_stats}
  end

  defp update_response_stats(stats, response) do
    case response["success"] do
      true ->
        %{
          stats
          | requests_handled: stats.requests_handled + 1,
            last_activity: System.monotonic_time(:millisecond)
        }

      false ->
        %{stats | errors: stats.errors + 1, last_activity: System.monotonic_time(:millisecond)}
    end
  end

  defp should_remove_worker?(worker_state, checkin_type) do
    case checkin_type do
      :close ->
        true

      _ ->
        # Remove if unhealthy or has too many errors
        worker_state.health_status == :unhealthy ||
          worker_state.stats.errors > 10
    end
  end

  defp format_response(response) do
    case response["success"] do
      true ->
        {:ok, response["result"]}

      false ->
        {:error, response["error"]}
    end
  end

  ## Public API for Pool Users

  @doc """
  Sends a command to the worker and waits for response.

  This is used by the pool checkout function to execute commands
  on the checked-out worker.
  """
  def send_command(worker_state, command, args, timeout \\ 5000) do
    request_id = worker_state.request_id + 1

    # Add session context if bound to session
    enhanced_args =
      case worker_state.current_session do
        nil -> args
        session_id -> Map.put(args, :session_id, session_id)
      end

    request = Protocol.encode_request(request_id, command, enhanced_args)

    send_and_await_response(worker_state, request, request_id, timeout)
  end

  @doc """
  Gets the current state and statistics of the worker.
  """
  def get_worker_info(worker_state) do
    %{
      worker_id: worker_state.worker_id,
      current_session: worker_state.current_session,
      health_status: worker_state.health_status,
      stats: worker_state.stats,
      uptime_ms: System.monotonic_time(:millisecond) - worker_state.started_at
    }
  end
end


---
## PoolWorker V2 (Refactored)
File: lib/dspex/python_bridge/pool_worker_v2.ex
---

defmodule DSPex.PythonBridge.PoolWorkerV2 do
  @moduledoc """
  Simplified NimblePool worker implementation for Python bridge processes.
  
  This version removes unnecessary response handling logic since clients
  communicate directly with ports after checkout.
  
  Key differences from V1:
  - No send_command/4 public function
  - No response handling in handle_info/2
  - Simplified to just manage worker lifecycle
  - Raises on init failure instead of returning error tuple
  """
  
  @behaviour NimblePool
  
  alias DSPex.PythonBridge.Protocol
  require Logger
  
  # Worker state structure
  defstruct [
    :port,
    :python_path,
    :script_path,
    :worker_id,
    :current_session,
    :stats,
    :health_status,
    :started_at
  ]
  
  ## NimblePool Callbacks
  
  @impl NimblePool
  def init_worker(pool_state) do
    worker_id = generate_worker_id()
    Logger.debug("Initializing pool worker: #{worker_id}")
    
    # Get Python environment details
    case DSPex.PythonBridge.EnvironmentCheck.validate_environment() do
      {:ok, env_info} ->
        python_path = env_info.python_path
        script_path = env_info.script_path
        
        # Start Python process in pool-worker mode
        port_opts = [
          :binary,
          :exit_status,
          {:packet, 4},
          :stderr_to_stdout,  # Capture stderr
          {:args, [script_path, "--mode", "pool-worker", "--worker-id", worker_id]}
        ]
        
        Logger.debug("Starting Python process for worker #{worker_id}")
        port = Port.open({:spawn_executable, python_path}, port_opts)
        
        # Initialize worker state
        worker_state = %__MODULE__{
          port: port,
          python_path: python_path,
          script_path: script_path,
          worker_id: worker_id,
          current_session: nil,
          stats: init_stats(),
          health_status: :initializing,
          started_at: System.monotonic_time(:millisecond)
        }
        
        # Send initialization ping to verify worker is ready
        case send_initialization_ping(worker_state) do
          {:ok, updated_state} ->
            Logger.info("Pool worker #{worker_id} started successfully")
            {:ok, updated_state, pool_state}
          
          {:error, reason} ->
            Logger.error("Worker #{worker_id} initialization failed: #{inspect(reason)}")
            Port.close(port)
            raise "Worker #{worker_id} initialization failed: #{inspect(reason)}"
        end
      
      {:error, reason} ->
        Logger.error("Failed to validate Python environment: #{inspect(reason)}")
        raise "Failed to validate Python environment: #{inspect(reason)}"
    end
  end
  
  @impl NimblePool
  def handle_checkout(checkout_type, from, worker_state, pool_state) do
    case checkout_type do
      {:session, session_id} ->
        handle_session_checkout(session_id, from, worker_state, pool_state)
      
      :anonymous ->
        handle_anonymous_checkout(from, worker_state, pool_state)
      
      _ ->
        {:error, {:invalid_checkout_type, checkout_type}}
    end
  end
  
  @impl NimblePool
  def handle_checkin(checkin_type, _from, worker_state, pool_state) do
    Logger.debug("Worker #{worker_state.worker_id} checkin with type: #{inspect(checkin_type)}")
    
    # Update stats
    updated_state = update_checkin_stats(worker_state, checkin_type)
    
    # Determine if worker should be removed
    case should_remove_worker?(updated_state, checkin_type) do
      true ->
        Logger.debug("Worker #{worker_state.worker_id} will be removed")
        {:remove, :closed, pool_state}
      
      false ->
        {:ok, updated_state, pool_state}
    end
  end
  
  @impl NimblePool
  def handle_info(message, worker_state) do
    case message do
      # Port died unexpectedly
      {port, {:exit_status, status}} when port == worker_state.port ->
        Logger.error("Python worker #{worker_state.worker_id} exited with status: #{status}")
        {:remove, :port_exited}
      
      # Ignore other messages - responses are handled by clients
      _ ->
        {:ok, worker_state}
    end
  end
  
  @impl NimblePool
  def terminate_worker(reason, worker_state, pool_state) do
    Logger.info("Terminating pool worker #{worker_state.worker_id}, reason: #{inspect(reason)}")
    
    # Send shutdown command to Python process
    try do
      send_shutdown_command(worker_state)
      
      # Give Python process time to cleanup
      receive do
        {port, {:exit_status, _}} when port == worker_state.port ->
          :ok
      after
        1000 ->
          # Force close if not exited
          Port.close(worker_state.port)
      end
    catch
      :error, _ ->
        # Port already closed
        :ok
    end
    
    {:ok, pool_state}
  end
  
  ## Checkout Handlers
  
  defp handle_session_checkout(session_id, {pid, _ref}, worker_state, pool_state) do
    # Bind worker to session and update stats
    updated_state = %{
      worker_state
      | current_session: session_id,
        stats: Map.update(worker_state.stats, :checkouts, 1, &(&1 + 1))
    }
    
    # Connect port to checking out process
    try do
      if is_port(worker_state.port) do
        Port.connect(worker_state.port, pid)
      end
      
      # Return worker state as client state
      {:ok, updated_state, updated_state, pool_state}
    catch
      :error, reason ->
        Logger.error("Failed to connect port to process: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp handle_anonymous_checkout({pid, _ref}, worker_state, pool_state) do
    # Anonymous checkout - no session binding
    updated_state = %{
      worker_state
      | stats: Map.update(worker_state.stats, :checkouts, 1, &(&1 + 1))
    }
    
    try do
      if is_port(updated_state.port) do
        Port.connect(updated_state.port, pid)
      end
      
      {:ok, updated_state, updated_state, pool_state}
    catch
      :error, reason ->
        Logger.error("Failed to connect port to process: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  ## Initialization
  
  defp send_initialization_ping(worker_state) do
    request_id = 0  # Special ID for init ping
    
    request = Protocol.encode_request(request_id, :ping, %{
      initialization: true,
      worker_id: worker_state.worker_id
    })
    
    Logger.info("Sending init ping request: #{inspect(request)}")
    Logger.info("To port: #{inspect(worker_state.port)}")
    
    try do
      send(worker_state.port, {self(), {:command, request}})
      
      receive do
        {port, {:data, data}} when port == worker_state.port ->
          Logger.debug("Received init response data: #{inspect(data, limit: :infinity)}")
          Logger.debug("Data byte size: #{byte_size(data)}")
          
          case Protocol.decode_response(data) do
            {:ok, ^request_id, response} ->
              Logger.debug("Decoded init response: #{inspect(response)}")
              
              case response do
                %{"success" => true} ->
                  {:ok, %{worker_state | health_status: :healthy}}
                
                %{"success" => false, "error" => error} ->
                  {:error, {:init_failed, error}}
                
                _ ->
                  {:error, :malformed_init_response}
              end
            
            {:ok, other_id, _response} ->
              Logger.error("Init response ID mismatch: expected 0, got #{other_id}")
              {:error, :response_id_mismatch}
            
            {:error, reason} ->
              Logger.error("Failed to decode init response: #{inspect(reason)}")
              {:error, {:decode_error, reason}}
          end
        
        {port, {:exit_status, status}} when port == worker_state.port ->
          Logger.error("Port exited during init with status #{status}")
          {:error, {:port_exited, status}}
          
        other ->
          Logger.error("Unexpected message during init: #{inspect(other)}")
          # Keep receiving in case there are more messages
          receive do
            msg -> Logger.error("Additional message: #{inspect(msg)}")
          after
            100 -> :ok
          end
          {:error, {:unexpected_message, other}}
      after
        5000 ->
          Logger.error("Init ping timeout after 5 seconds for worker #{worker_state.worker_id}")
          # Check if port is still alive
          port_info = Port.info(worker_state.port)
          Logger.error("Port info at timeout: #{inspect(port_info)}")
          {:error, :init_timeout}
      end
    catch
      :error, reason ->
        Logger.error("Failed to send init ping: #{inspect(reason)}")
        {:error, {:send_failed, reason}}
    end
  end
  
  defp send_shutdown_command(worker_state) do
    request_id = System.unique_integer([:positive])
    
    request = Protocol.encode_request(request_id, :shutdown, %{
      worker_id: worker_state.worker_id
    })
    
    send(worker_state.port, {self(), {:command, request}})
  end
  
  ## Stats Management
  
  defp init_stats do
    %{
      checkouts: 0,
      successful_checkins: 0,
      error_checkins: 0,
      uptime_ms: 0,
      last_activity: System.monotonic_time(:millisecond)
    }
  end
  
  defp update_checkin_stats(worker_state, checkin_type) do
    stats = worker_state.stats
    
    updated_stats = case checkin_type do
      :ok ->
        %{stats | successful_checkins: stats.successful_checkins + 1}
      
      {:error, _} ->
        %{stats | error_checkins: stats.error_checkins + 1}
      
      _ ->
        stats
    end
    
    %{worker_state | 
      stats: Map.put(updated_stats, :last_activity, System.monotonic_time(:millisecond))
    }
  end
  
  defp should_remove_worker?(_worker_state, checkin_type) do
    case checkin_type do
      :close -> true
      _ -> false
    end
  end
  
  ## Utility Functions
  
  defp generate_worker_id do
    "worker_#{:erlang.unique_integer([:positive])}_#{:erlang.system_time(:microsecond)}"
  end
  
  @doc """
  Gets the current state and statistics of the worker.
  Used for monitoring and debugging.
  """
  def get_worker_info(worker_state) do
    %{
      worker_id: worker_state.worker_id,
      current_session: worker_state.current_session,
      health_status: worker_state.health_status,
      stats: worker_state.stats,
      uptime_ms: System.monotonic_time(:millisecond) - worker_state.started_at
    }
  end
end

---
## PythonPool Adapter V1
File: lib/dspex/adapters/python_pool.ex
---

defmodule DSPex.Adapters.PythonPool do
  @moduledoc """
  Python pool adapter using NimblePool for concurrent session isolation.

  This adapter provides a production-ready implementation with:
  - Process pool management
  - Session-based isolation
  - Automatic load balancing
  - Health monitoring
  - Resource cleanup

  ## Features

  - **Concurrent Execution**: Multiple isolated Python processes
  - **Session Isolation**: Each session has its own program namespace
  - **Scalability**: Pool size based on system resources
  - **Fault Tolerance**: Automatic worker restart on failure
  - **Performance**: Reuses processes across sessions

  ## Configuration

      config :dspex, DSPex.Adapters.PythonPool,
        pool_size: System.schedulers_online() * 2,
        overflow: 2,
        checkout_timeout: 5_000,
        operation_timeout: 30_000

  ## Usage

      # Create a session-aware adapter
      {:ok, adapter} = DSPex.Adapters.PythonPool.start_session("user_123")
      
      # Use within session
      {:ok, program_id} = adapter.create_program(%{signature: %{...}})
      {:ok, result} = adapter.execute_program(program_id, %{input: "test"})
      
      # End session
      :ok = DSPex.Adapters.PythonPool.end_session("user_123")
  """

  @behaviour DSPex.Adapters.Adapter

  alias DSPex.PythonBridge.SessionPool

  require Logger

  # Default session for anonymous operations
  @default_session "anonymous"

  ## Adapter Callbacks

  @impl true
  def create_program(config) do
    session_id = get_session_id(config)

    # Convert config for Python bridge
    python_config = convert_config(config)

    case SessionPool.execute_in_session(session_id, :create_program, python_config) do
      {:ok, response} ->
        program_id = extract_program_id(response)
        {:ok, program_id}

      {:error, reason} ->
        handle_pool_error(reason)
    end
  end

  @impl true
  def execute_program(program_id, inputs) do
    execute_program(program_id, inputs, %{})
  end

  @impl true
  def execute_program(program_id, inputs, options) do
    session_id = get_session_id(options)

    args = %{
      program_id: program_id,
      inputs: inputs,
      options: Map.delete(options, :session_id)
    }

    case SessionPool.execute_in_session(session_id, :execute_program, args, options) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        handle_pool_error(reason)
    end
  end

  @impl true
  def list_programs do
    list_programs(%{})
  end

  def list_programs(options) do
    session_id = get_session_id(options)

    case SessionPool.execute_in_session(session_id, :list_programs, %{}) do
      {:ok, %{"programs" => programs}} ->
        program_ids = Enum.map(programs, &extract_program_id/1)
        {:ok, program_ids}

      {:ok, %{programs: programs}} ->
        program_ids = Enum.map(programs, &extract_program_id/1)
        {:ok, program_ids}

      {:error, reason} ->
        handle_pool_error(reason)
    end
  end

  @impl true
  def delete_program(program_id) do
    delete_program(program_id, %{})
  end

  def delete_program(program_id, options) do
    session_id = get_session_id(options)

    case SessionPool.execute_in_session(session_id, :delete_program, %{program_id: program_id}) do
      {:ok, _} -> :ok
      {:error, reason} -> handle_pool_error(reason)
    end
  end

  @impl true
  def get_program_info(program_id) do
    get_program_info(program_id, %{})
  end

  def get_program_info(program_id, options) do
    session_id = get_session_id(options)

    case SessionPool.execute_in_session(session_id, :get_program_info, %{program_id: program_id}) do
      {:ok, info} ->
        enhanced_info =
          Map.merge(info, %{
            "id" => program_id,
            :id => program_id,
            :session_id => session_id
          })

        {:ok, enhanced_info}

      {:error, reason} ->
        handle_pool_error(reason)
    end
  end

  @impl true
  def health_check do
    case SessionPool.execute_anonymous(:ping, %{}) do
      {:ok, %{"status" => "ok"}} -> :ok
      {:ok, %{status: "ok"}} -> :ok
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unhealthy}
    end
  end

  @impl true
  def get_stats do
    get_stats(%{})
  end

  def get_stats(options) do
    session_id = get_session_id(options)

    # Get pool-level stats
    pool_status = SessionPool.get_pool_status()

    # Get session-specific stats if requested
    session_stats =
      if session_id != @default_session do
        case SessionPool.execute_in_session(session_id, :get_stats, %{}) do
          {:ok, stats} -> stats
          _ -> %{}
        end
      else
        %{}
      end

    # Combine stats
    {:ok,
     %{
       adapter_type: :python_pool,
       layer: :production,
       pool_status: pool_status,
       session_stats: session_stats,
       python_execution: true,
       concurrent_sessions: true
     }}
  end

  @impl true
  def configure_lm(config) do
    # Configure LM globally (all workers will use it)
    case SessionPool.execute_anonymous(:configure_lm, config) do
      {:ok, %{"status" => "configured"}} -> :ok
      {:ok, %{status: "configured"}} -> :ok
      {:error, reason} -> {:error, reason}
      _ -> {:error, :configuration_failed}
    end
  end

  @impl true
  def supports_test_layer?(layer), do: layer == :production

  @impl true
  def get_test_capabilities do
    %{
      python_execution: true,
      real_ml_models: true,
      protocol_validation: true,
      deterministic_outputs: false,
      performance: :optimized,
      requires_environment: [:python, :dspy, :nimble_pool],
      concurrent_execution: true,
      session_isolation: true,
      production_ready: true
    }
  end

  ## Session Management

  @doc """
  Starts a new session for isolated operations.

  ## Examples

      {:ok, session_id} = PythonPool.start_session("user_123")
  """
  def start_session(session_id, _opts \\ []) do
    # Session will be created on first use
    Logger.debug("Starting session: #{session_id}")
    {:ok, session_id}
  end

  @doc """
  Ends a session and cleans up resources.

  ## Examples

      :ok = PythonPool.end_session("user_123")
  """
  def end_session(session_id) do
    SessionPool.end_session(session_id)
  end

  @doc """
  Gets information about active sessions.
  """
  def get_session_info do
    SessionPool.get_session_info()
  end

  @doc """
  Creates a session-bound adapter instance.

  This returns a map with all adapter functions bound to a specific session.

  ## Examples

      adapter = PythonPool.session_adapter("user_123")
      {:ok, program_id} = adapter.create_program(%{...})
  """
  def session_adapter(session_id) do
    %{
      create_program: fn config ->
        create_program(Map.put(config, :session_id, session_id))
      end,
      execute_program: fn program_id, inputs, opts ->
        execute_program(program_id, inputs, Map.put(opts || %{}, :session_id, session_id))
      end,
      list_programs: fn ->
        list_programs(%{session_id: session_id})
      end,
      delete_program: fn program_id ->
        delete_program(program_id, %{session_id: session_id})
      end,
      get_program_info: fn program_id ->
        get_program_info(program_id, %{session_id: session_id})
      end,
      get_stats: fn ->
        get_stats(%{session_id: session_id})
      end,
      health_check: &health_check/0,
      session_id: session_id
    }
  end

  ## Private Functions

  defp get_session_id(config_or_options) do
    Map.get(config_or_options, :session_id, @default_session)
  end

  defp convert_config(config) do
    config
    |> Map.new(fn
      {:id, value} -> {"id", value}
      {"id", value} -> {"id", value}
      {:signature, value} -> {"signature", convert_signature(value)}
      {"signature", value} -> {"signature", convert_signature(value)}
      # Keep session_id as atom
      {:session_id, value} -> {:session_id, value}
      {key, value} -> {to_string(key), value}
    end)
    |> ensure_program_id()
  end

  defp convert_signature(signature) when is_atom(signature) do
    # TypeConverter.convert_signature_to_format returns the converted signature directly
    DSPex.Adapters.TypeConverter.convert_signature_to_format(signature, :python)
  end

  defp convert_signature(signature) when is_map(signature) do
    signature
    |> Map.new(fn
      {:inputs, value} -> {"inputs", convert_io_list(value)}
      {"inputs", value} -> {"inputs", convert_io_list(value)}
      {:outputs, value} -> {"outputs", convert_io_list(value)}
      {"outputs", value} -> {"outputs", convert_io_list(value)}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp convert_signature(signature), do: signature

  defp convert_io_list(io_list) when is_list(io_list) do
    Enum.map(io_list, fn item ->
      Map.new(item, fn
        {:name, value} -> {"name", value}
        {"name", value} -> {"name", value}
        {:type, value} -> {"type", value}
        {"type", value} -> {"type", value}
        {key, value} -> {to_string(key), value}
      end)
    end)
  end

  defp convert_io_list(io_list), do: io_list

  defp ensure_program_id(config) do
    case Map.get(config, "id") do
      nil -> Map.put(config, "id", generate_program_id())
      "" -> Map.put(config, "id", generate_program_id())
      _id -> config
    end
  end

  defp extract_program_id(response) when is_map(response) do
    Map.get(response, "program_id") ||
      Map.get(response, :program_id) ||
      Map.get(response, "id") ||
      Map.get(response, :id)
  end

  defp extract_program_id(id) when is_binary(id), do: id

  defp generate_program_id do
    "pool_#{:erlang.unique_integer([:positive])}_#{System.system_time(:microsecond)}"
  end

  defp handle_pool_error(:pool_timeout) do
    {:error, "Pool timeout - all workers busy"}
  end

  defp handle_pool_error({:pool_error, reason}) do
    {:error, "Pool error: #{inspect(reason)}"}
  end

  defp handle_pool_error(reason) do
    {:error, reason}
  end
end


---
## PythonPool Adapter V2
File: lib/dspex/adapters/python_pool_v2.ex
---

defmodule DSPex.Adapters.PythonPoolV2 do
  @moduledoc """
  Python pool adapter using refactored SessionPoolV2 with proper NimblePool pattern.
  
  This version uses the corrected SessionPoolV2 that allows true concurrent execution
  by moving blocking I/O operations to client processes.
  
  Key differences from V1:
  - Uses SessionPoolV2 which doesn't block the pool manager
  - Calls execute_in_session/4 directly as a public function
  - True concurrent execution of Python operations
  """
  
  @behaviour DSPex.Adapters.Adapter
  
  alias DSPex.PythonBridge.SessionPoolV2
  
  require Logger
  
  # Default session for anonymous operations
  @default_session "anonymous"
  
  ## Adapter Callbacks
  
  @impl true
  def create_program(config) do
    session_id = get_session_id(config)
    
    # Convert config for Python bridge
    python_config = convert_config(config)
    
    # This now runs in the client process, not the pool manager
    case SessionPoolV2.execute_in_session(session_id, :create_program, python_config) do
      {:ok, response} ->
        program_id = extract_program_id(response)
        {:ok, program_id}
      
      {:error, reason} ->
        handle_pool_error(reason)
    end
  end
  
  @impl true
  def execute_program(program_id, inputs) do
    execute_program(program_id, inputs, %{})
  end
  
  @impl true
  def execute_program(program_id, inputs, options) do
    session_id = get_session_id(options)
    
    args = %{
      program_id: program_id,
      inputs: inputs,
      options: Map.delete(options, :session_id)
    }
    
    # Direct execution in client process
    case SessionPoolV2.execute_in_session(session_id, :execute_program, args, options) do
      {:ok, response} ->
        {:ok, response}
      
      {:error, reason} ->
        handle_pool_error(reason)
    end
  end
  
  @impl true
  def list_programs do
    list_programs(%{})
  end
  
  def list_programs(options) do
    session_id = get_session_id(options)
    
    case SessionPoolV2.execute_in_session(session_id, :list_programs, %{}) do
      {:ok, %{"programs" => programs}} ->
        program_ids = Enum.map(programs, &extract_program_id/1)
        {:ok, program_ids}
      
      {:ok, %{programs: programs}} ->
        program_ids = Enum.map(programs, &extract_program_id/1)
        {:ok, program_ids}
      
      {:error, reason} ->
        handle_pool_error(reason)
    end
  end
  
  @impl true
  def delete_program(program_id) do
    delete_program(program_id, %{})
  end
  
  def delete_program(program_id, options) do
    session_id = get_session_id(options)
    
    case SessionPoolV2.execute_in_session(session_id, :delete_program, %{program_id: program_id}) do
      {:ok, _} -> :ok
      {:error, reason} -> handle_pool_error(reason)
    end
  end
  
  @impl true
  def get_program_info(program_id) do
    get_program_info(program_id, %{})
  end
  
  def get_program_info(program_id, options) do
    session_id = get_session_id(options)
    
    case SessionPoolV2.execute_in_session(session_id, :get_program_info, %{program_id: program_id}) do
      {:ok, info} ->
        enhanced_info = Map.merge(info, %{
          "id" => program_id,
          :id => program_id,
          :session_id => session_id
        })
        
        {:ok, enhanced_info}
      
      {:error, reason} ->
        handle_pool_error(reason)
    end
  end
  
  @impl true
  def health_check do
    # Anonymous operation doesn't need session
    case SessionPoolV2.execute_anonymous(:ping, %{}) do
      {:ok, %{"status" => "ok"}} -> :ok
      {:ok, %{status: "ok"}} -> :ok
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unhealthy}
    end
  end
  
  @impl true
  def get_stats do
    get_stats(%{})
  end
  
  def get_stats(options) do
    session_id = get_session_id(options)
    
    # Get pool-level stats from the GenServer
    pool_status = SessionPoolV2.get_pool_status()
    
    # Get session-specific stats if requested
    session_stats = if session_id != @default_session do
      case SessionPoolV2.execute_in_session(session_id, :get_stats, %{}) do
        {:ok, stats} -> stats
        _ -> %{}
      end
    else
      %{}
    end
    
    # Combine stats
    {:ok, %{
      adapter_type: :python_pool_v2,
      layer: :production,
      pool_status: pool_status,
      session_stats: session_stats,
      python_execution: true,
      concurrent_sessions: true,
      true_concurrency: true  # Key difference from V1
    }}
  end
  
  @impl true
  def configure_lm(config) do
    # Configure LM globally (all workers will use it)
    case SessionPoolV2.execute_anonymous(:configure_lm, config) do
      {:ok, %{"status" => "configured"}} -> :ok
      {:ok, %{status: "configured"}} -> :ok
      {:error, reason} -> {:error, reason}
      _ -> {:error, :configuration_failed}
    end
  end
  
  @impl true
  def supports_test_layer?(layer), do: layer == :production
  
  @impl true
  def get_test_capabilities do
    %{
      python_execution: true,
      real_ml_models: true,
      protocol_validation: true,
      deterministic_outputs: false,
      performance: :highly_optimized,  # Better than V1
      requires_environment: [:python, :dspy, :nimble_pool],
      concurrent_execution: true,
      true_concurrent_execution: true,  # Key difference
      session_isolation: true,
      production_ready: true
    }
  end
  
  ## Session Management
  
  @doc """
  Starts a new session for isolated operations.
  """
  def start_session(session_id, _opts \\ []) do
    # Session tracking happens in ETS on first use
    Logger.debug("Starting session: #{session_id}")
    {:ok, session_id}
  end
  
  @doc """
  Ends a session and cleans up resources.
  """
  def end_session(session_id) do
    SessionPoolV2.end_session(session_id)
  end
  
  @doc """
  Gets information about active sessions.
  """
  def get_session_info do
    SessionPoolV2.get_session_info()
  end
  
  @doc """
  Creates a session-bound adapter instance.
  """
  def session_adapter(session_id) do
    %{
      create_program: fn config ->
        create_program(Map.put(config, :session_id, session_id))
      end,
      execute_program: fn program_id, inputs, opts ->
        execute_program(program_id, inputs, Map.put(opts || %{}, :session_id, session_id))
      end,
      list_programs: fn ->
        list_programs(%{session_id: session_id})
      end,
      delete_program: fn program_id ->
        delete_program(program_id, %{session_id: session_id})
      end,
      get_program_info: fn program_id ->
        get_program_info(program_id, %{session_id: session_id})
      end,
      get_stats: fn ->
        get_stats(%{session_id: session_id})
      end,
      health_check: &health_check/0,
      session_id: session_id
    }
  end
  
  ## Private Functions
  
  defp get_session_id(config_or_options) do
    Map.get(config_or_options, :session_id, @default_session)
  end
  
  defp convert_config(config) do
    config
    |> Map.new(fn
      {:id, value} -> {"id", value}
      {"id", value} -> {"id", value}
      {:signature, value} -> {"signature", convert_signature(value)}
      {"signature", value} -> {"signature", convert_signature(value)}
      # Keep session_id as atom
      {:session_id, value} -> {:session_id, value}
      {key, value} -> {to_string(key), value}
    end)
    |> ensure_program_id()
  end
  
  defp convert_signature(signature) when is_atom(signature) do
    DSPex.Adapters.TypeConverter.convert_signature_to_format(signature, :python)
  end
  
  defp convert_signature(signature) when is_map(signature) do
    signature
    |> Map.new(fn
      {:inputs, value} -> {"inputs", convert_io_list(value)}
      {"inputs", value} -> {"inputs", convert_io_list(value)}
      {:outputs, value} -> {"outputs", convert_io_list(value)}
      {"outputs", value} -> {"outputs", convert_io_list(value)}
      {key, value} -> {to_string(key), value}
    end)
  end
  
  defp convert_signature(signature), do: signature
  
  defp convert_io_list(io_list) when is_list(io_list) do
    Enum.map(io_list, fn item ->
      Map.new(item, fn
        {:name, value} -> {"name", value}
        {"name", value} -> {"name", value}
        {:type, value} -> {"type", value}
        {"type", value} -> {"type", value}
        {key, value} -> {to_string(key), value}
      end)
    end)
  end
  
  defp convert_io_list(io_list), do: io_list
  
  defp ensure_program_id(config) do
    case Map.get(config, "id") do
      nil -> Map.put(config, "id", generate_program_id())
      "" -> Map.put(config, "id", generate_program_id())
      _id -> config
    end
  end
  
  defp extract_program_id(response) when is_map(response) do
    Map.get(response, "program_id") ||
      Map.get(response, :program_id) ||
      Map.get(response, "id") ||
      Map.get(response, :id)
  end
  
  defp extract_program_id(id) when is_binary(id), do: id
  
  defp generate_program_id do
    "pool_#{:erlang.unique_integer([:positive])}_#{System.system_time(:microsecond)}"
  end
  
  defp handle_pool_error({:pool_timeout, reason}) do
    {:error, "Pool timeout: #{inspect(reason)}"}
  end
  
  defp handle_pool_error({:checkout_failed, reason}) do
    {:error, "Checkout failed: #{inspect(reason)}"}
  end
  
  defp handle_pool_error({:decode_error, reason}) do
    {:error, "Response decode error: #{inspect(reason)}"}
  end
  
  defp handle_pool_error(:response_mismatch) do
    {:error, "Response ID mismatch - possible concurrent operation conflict"}
  end
  
  defp handle_pool_error(:malformed_response) do
    {:error, "Malformed response from Python worker"}
  end
  
  defp handle_pool_error(reason) do
    {:error, reason}
  end
end

---
## Python Bridge Script
File: priv/python/dspy_bridge.py
---

#!/usr/bin/env python3
"""
DSPy Bridge for Elixir Integration

This module provides a communication bridge between Elixir and Python DSPy
processes using a JSON-based protocol with length-prefixed messages.

Features:
- Dynamic DSPy signature creation from Elixir definitions
- Program lifecycle management (create, execute, cleanup)
- Health monitoring and statistics
- Error handling and logging
- Memory management and cleanup

Protocol:
- 4-byte big-endian length header
- JSON message payload
- Request/response correlation with IDs

Usage:
    python3 dspy_bridge.py

The script reads from stdin and writes to stdout using the packet protocol.
"""

import sys
import json
import struct
import traceback
import time
import gc
import threading
import os
import argparse
from typing import Dict, Any, Optional, List, Union

# Handle DSPy import with fallback
try:
    import dspy
    DSPY_AVAILABLE = True
except ImportError:
    DSPY_AVAILABLE = False
    print("Warning: DSPy not available. Some functionality will be limited.", file=sys.stderr)

# Handle Gemini import with fallback
try:
    import google.generativeai as genai
    GEMINI_AVAILABLE = True
except ImportError:
    GEMINI_AVAILABLE = False
    print("Warning: Google GenerativeAI not available. Gemini functionality will be limited.", file=sys.stderr)


class DSPyBridge:
    """
    Main bridge class handling DSPy program management and execution.
    
    This class maintains a registry of DSPy programs and handles command
    execution requests from the Elixir side.
    """
    
    def __init__(self, mode="standalone", worker_id=None):
        """Initialize the bridge with empty program registry."""
        self.mode = mode
        self.worker_id = worker_id
        
        # In pool-worker mode, programs are namespaced by session
        if mode == "pool-worker":
            self.session_programs: Dict[str, Dict[str, Any]] = {}  # {session_id: {program_id: program}}
            self.current_session = None
        else:
            self.programs: Dict[str, Any] = {}
            
        self.start_time = time.time()
        self.command_count = 0
        self.error_count = 0
        self.lock = threading.Lock()
        
        # Language Model configuration
        self.lm_configured = False
        self.current_lm_config = None
        
        # Initialize DSPy if available
        if DSPY_AVAILABLE:
            self._initialize_dspy()
            
        # Initialize Gemini if available
        if GEMINI_AVAILABLE:
            self._initialize_gemini()
    
    def _initialize_dspy(self):
        """Initialize DSPy with default settings."""
        try:
            # Set up default DSPy configuration
            # This can be customized based on requirements
            pass
        except Exception as e:
            print(f"Warning: DSPy initialization failed: {e}", file=sys.stderr)
    
    def _initialize_gemini(self):
        """Initialize Gemini with API key from environment."""
        try:
            api_key = os.environ.get('GEMINI_API_KEY')
            if api_key:
                genai.configure(api_key=api_key)
                print("Gemini API configured successfully", file=sys.stderr)
            else:
                print("Warning: GEMINI_API_KEY not found in environment", file=sys.stderr)
        except Exception as e:
            print(f"Warning: Gemini initialization failed: {e}", file=sys.stderr)
    
    def handle_command(self, command: str, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle incoming commands from Elixir.
        
        Args:
            command: The command name to execute
            args: Command arguments as a dictionary
            
        Returns:
            Dictionary containing the command result
            
        Raises:
            ValueError: If the command is unknown
            Exception: If command execution fails
        """
        with self.lock:
            self.command_count += 1
            
            handlers = {
                'ping': self.ping,
                'configure_lm': self.configure_lm,
                'create_program': self.create_program,
                'create_gemini_program': self.create_gemini_program,
                'execute_program': self.execute_program,
                'execute_gemini_program': self.execute_gemini_program,
                'list_programs': self.list_programs,
                'delete_program': self.delete_program,
                'get_stats': self.get_stats,
                'cleanup': self.cleanup,
                'reset_state': self.reset_state,
                'get_program_info': self.get_program_info,
                'cleanup_session': self.cleanup_session,
                'shutdown': self.shutdown
            }
            
            if command not in handlers:
                self.error_count += 1
                raise ValueError(f"Unknown command: {command}")
            
            try:
                result = handlers[command](args)
                return result
            except Exception as e:
                self.error_count += 1
                raise
    
    def ping(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Health check command.
        
        Args:
            args: Empty or containing optional parameters
            
        Returns:
            Status information including timestamp
        """
        response = {
            "status": "ok",
            "timestamp": time.time(),
            "dspy_available": DSPY_AVAILABLE,
            "gemini_available": GEMINI_AVAILABLE,
            "uptime": time.time() - self.start_time,
            "mode": self.mode
        }
        
        if self.worker_id:
            response["worker_id"] = self.worker_id
            
        if self.mode == "pool-worker" and hasattr(self, 'current_session'):
            response["current_session"] = self.current_session
            
        return response
    
    def configure_lm(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Configure the language model for DSPy.
        
        Args:
            args: Configuration with model, api_key, temperature
            
        Returns:
            Status information about the configuration
        """
        try:
            model = args.get('model')
            api_key = args.get('api_key')
            temperature = args.get('temperature', 0.7)
            provider = args.get('provider', 'google')
            
            if not model:
                raise ValueError("Model name is required")
            if not api_key:
                raise ValueError("API key is required")
            
            # Configure based on provider
            if provider == 'google' and model.startswith('gemini'):
                import dspy
                # Configure Google/Gemini LM
                lm = dspy.Google(
                    model=model,
                    api_key=api_key,
                    temperature=temperature
                )
                dspy.settings.configure(lm=lm)
                
                self.lm_configured = True
                self.current_lm_config = args
                
                # Store per-session in pool-worker mode
                if self.mode == "pool-worker" and hasattr(self, 'current_session') and self.current_session:
                    if not hasattr(self, 'session_lms'):
                        self.session_lms = {}
                    self.session_lms[self.current_session] = args
                
                return {
                    "status": "configured",
                    "model": model,
                    "provider": provider,
                    "temperature": temperature
                }
            else:
                raise ValueError(f"Unsupported provider/model combination: {provider}/{model}")
                
        except Exception as e:
            self.error_count += 1
            return {"error": str(e)}
    
    def create_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create a new DSPy program from signature definition.
        
        Args:
            args: Dictionary containing:
                - id: Unique program identifier
                - signature: Signature definition with inputs/outputs
                - program_type: Type of program to create (default: 'predict')
                
        Returns:
            Dictionary with program creation status
        """
        if not DSPY_AVAILABLE:
            raise RuntimeError("DSPy not available - cannot create programs")
        
        program_id = args.get('id')
        signature_def = args.get('signature', {})
        program_type = args.get('program_type', 'predict')
        
        if not program_id:
            raise ValueError("Program ID is required")
        
        # Handle session-based storage in pool-worker mode
        if self.mode == "pool-worker":
            session_id = args.get('session_id')
            if not session_id:
                raise ValueError("Session ID required in pool-worker mode")
            
            # Initialize session if needed
            if session_id not in self.session_programs:
                self.session_programs[session_id] = {}
                
            if program_id in self.session_programs[session_id]:
                raise ValueError(f"Program with ID '{program_id}' already exists in session {session_id}")
        else:
            if program_id in self.programs:
                raise ValueError(f"Program with ID '{program_id}' already exists")
        
        try:
            # Create dynamic signature class
            signature_class = self._create_signature_class(signature_def)
            
            # Create program based on type
            program = self._create_program_instance(signature_class, program_type)
            
            # Store program based on mode
            program_info = {
                'program': program,
                'signature': signature_def,
                'created_at': time.time(),
                'execution_count': 0,
                'last_executed': None
            }
            
            if self.mode == "pool-worker":
                session_id = args.get('session_id')
                self.session_programs[session_id][program_id] = program_info
            else:
                self.programs[program_id] = program_info
            
            return {
                "program_id": program_id,
                "status": "created",
                "signature": signature_def,
                "program_type": program_type
            }
            
        except Exception as e:
            raise RuntimeError(f"Failed to create program: {str(e)}")
    
    def _create_signature_class(self, signature_def: Dict[str, Any]) -> type:
        """
        Create a dynamic DSPy signature class from definition.
        
        Args:
            signature_def: Dictionary containing inputs and outputs
            
        Returns:
            Dynamic signature class
        """
        class DynamicSignature(dspy.Signature):
            pass
        
        inputs = signature_def.get('inputs', [])
        outputs = signature_def.get('outputs', [])
        
        # Add input fields
        for field in inputs:
            field_name = field.get('name')
            field_desc = field.get('description', '')
            
            if not field_name:
                raise ValueError("Input field must have a name")
            
            setattr(DynamicSignature, field_name, dspy.InputField(desc=field_desc))
        
        # Add output fields
        for field in outputs:
            field_name = field.get('name')
            field_desc = field.get('description', '')
            
            if not field_name:
                raise ValueError("Output field must have a name")
            
            setattr(DynamicSignature, field_name, dspy.OutputField(desc=field_desc))
        
        return DynamicSignature
    
    def _create_program_instance(self, signature_class: type, program_type: str) -> Any:
        """
        Create a DSPy program instance of the specified type.
        
        Args:
            signature_class: The signature class to use
            program_type: Type of program ('predict', 'chain_of_thought', etc.)
            
        Returns:
            DSPy program instance
        """
        if program_type == 'predict':
            return dspy.Predict(signature_class)
        elif program_type == 'chain_of_thought':
            return dspy.ChainOfThought(signature_class)
        elif program_type == 'react':
            return dspy.ReAct(signature_class)
        else:
            # Default to Predict for unknown types
            return dspy.Predict(signature_class)
    
    def execute_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Execute a DSPy program with given inputs.
        
        Args:
            args: Dictionary containing:
                - program_id: ID of the program to execute
                - inputs: Input values for the program
                
        Returns:
            Dictionary containing program outputs
        """
        program_id = args.get('program_id')
        inputs = args.get('inputs', {})
        
        if not program_id:
            raise ValueError("Program ID is required")
        
        # Get program based on mode
        if self.mode == "pool-worker":
            session_id = args.get('session_id')
            if not session_id:
                raise ValueError("Session ID required in pool-worker mode")
            
            if session_id not in self.session_programs:
                raise ValueError(f"Session not found: {session_id}")
                
            if program_id not in self.session_programs[session_id]:
                raise ValueError(f"Program not found in session {session_id}: {program_id}")
                
            program_info = self.session_programs[session_id][program_id]
        else:
            if program_id not in self.programs:
                raise ValueError(f"Program not found: {program_id}")
                
            program_info = self.programs[program_id]
            
        program = program_info['program']
        
        # Check if LM is configured
        if not self.lm_configured:
            # Try to use default from environment if available
            api_key = os.environ.get('GEMINI_API_KEY')
            if api_key:
                self.configure_lm({
                    'model': 'gemini-1.5-flash',
                    'api_key': api_key,
                    'temperature': 0.7,
                    'provider': 'google'
                })
            else:
                raise RuntimeError("No LM is loaded.")
        
        # Restore session LM if in pool-worker mode
        if self.mode == "pool-worker" and hasattr(self, 'session_lms'):
            session_id = args.get('session_id')
            if session_id in self.session_lms:
                self.configure_lm(self.session_lms[session_id])
        
        try:
            # Execute the program
            result = program(**inputs)
            
            # Update execution statistics
            program_info['execution_count'] += 1
            program_info['last_executed'] = time.time()
            
            # Convert result to dictionary
            if hasattr(result, '__dict__'):
                output = {k: v for k, v in result.__dict__.items() 
                         if not k.startswith('_')}
            else:
                output = {"result": str(result)}
            
            return {
                "program_id": program_id,
                "outputs": output,
                "execution_time": time.time()
            }
            
        except Exception as e:
            raise RuntimeError(f"Program execution failed: {str(e)}")
    
    def list_programs(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        List all available programs.
        
        Args:
            args: Empty or containing optional filters
            
        Returns:
            Dictionary with program list and metadata
        """
        program_list = []
        
        if self.mode == "pool-worker":
            session_id = args.get('session_id')
            if session_id and session_id in self.session_programs:
                # List programs for specific session
                for program_id, program_info in self.session_programs[session_id].items():
                    program_list.append({
                        "id": program_id,
                        "created_at": program_info['created_at'],
                        "execution_count": program_info['execution_count'],
                        "last_executed": program_info['last_executed'],
                        "signature": program_info['signature'],
                        "session_id": session_id
                    })
            else:
                # List all programs across all sessions
                for session_id, session_programs in self.session_programs.items():
                    for program_id, program_info in session_programs.items():
                        program_list.append({
                            "id": program_id,
                            "created_at": program_info['created_at'],
                            "execution_count": program_info['execution_count'],
                            "last_executed": program_info['last_executed'],
                            "signature": program_info['signature'],
                            "session_id": session_id
                        })
        else:
            for program_id, program_info in self.programs.items():
                program_list.append({
                    "id": program_id,
                    "created_at": program_info['created_at'],
                    "execution_count": program_info['execution_count'],
                    "last_executed": program_info['last_executed'],
                    "signature": program_info['signature']
                })
        
        return {
            "programs": program_list,
            "total_count": len(program_list)
        }
    
    def delete_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Delete a program and free its resources.
        
        Args:
            args: Dictionary containing:
                - program_id: ID of the program to delete
                
        Returns:
            Dictionary with deletion status
        """
        program_id = args.get('program_id')
        
        if not program_id:
            raise ValueError("Program ID is required")
        
        if self.mode == "pool-worker":
            session_id = args.get('session_id')
            if not session_id:
                raise ValueError("Session ID required in pool-worker mode")
            
            if session_id not in self.session_programs:
                raise ValueError(f"Session not found: {session_id}")
                
            if program_id not in self.session_programs[session_id]:
                raise ValueError(f"Program not found in session {session_id}: {program_id}")
                
            del self.session_programs[session_id][program_id]
        else:
            if program_id not in self.programs:
                raise ValueError(f"Program not found: {program_id}")
            
            del self.programs[program_id]
        
        # Trigger garbage collection to free memory
        gc.collect()
        
        return {
            "program_id": program_id,
            "status": "deleted"
        }
    
    def get_program_info(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get detailed information about a specific program.
        
        Args:
            args: Dictionary containing:
                - program_id: ID of the program
                
        Returns:
            Dictionary with program information
        """
        program_id = args.get('program_id')
        
        if not program_id:
            raise ValueError("Program ID is required")
        
        if program_id not in self.programs:
            raise ValueError(f"Program not found: {program_id}")
        
        program_info = self.programs[program_id]
        
        return {
            "program_id": program_id,
            "signature": program_info['signature'],
            "created_at": program_info['created_at'],
            "execution_count": program_info['execution_count'],
            "last_executed": program_info['last_executed']
        }
    
    def get_stats(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get bridge statistics and performance metrics.
        
        Args:
            args: Empty or containing optional parameters
            
        Returns:
            Dictionary with statistics
        """
        return {
            "programs_count": len(self.programs),
            "command_count": self.command_count,
            "error_count": self.error_count,
            "uptime": time.time() - self.start_time,
            "memory_usage": self._get_memory_usage(),
            "dspy_available": DSPY_AVAILABLE,
            "gemini_available": GEMINI_AVAILABLE
        }
    
    def cleanup(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Clean up all programs and free resources.
        
        Args:
            args: Empty or containing optional parameters
            
        Returns:
            Dictionary with cleanup status
        """
        program_count = len(self.programs)
        self.programs.clear()
        
        # Force garbage collection
        gc.collect()
        
        return {
            "status": "cleaned",
            "programs_removed": program_count
        }
    
    def reset_state(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Reset all bridge state (alias for cleanup with additional reset info).
        
        Clears all programs and resets counters for clean test isolation.
        
        Args:
            args: Optional parameters
            
        Returns:
            Dictionary with reset status
        """
        program_count = len(self.programs)
        command_count = self.command_count
        error_count = self.error_count
        
        # Clear all state
        self.programs.clear()
        self.command_count = 0
        self.error_count = 0
        
        # Force garbage collection
        gc.collect()
        
        return {
            "status": "reset",
            "programs_cleared": program_count,
            "commands_reset": command_count,
            "errors_reset": error_count
        }
    
    def cleanup_session(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Clean up a specific session in pool-worker mode.
        
        Args:
            args: Dictionary containing session_id
            
        Returns:
            Dictionary with cleanup status
        """
        if self.mode != "pool-worker":
            return {"status": "not_applicable", "mode": self.mode}
            
        session_id = args.get('session_id')
        if not session_id:
            raise ValueError("Session ID required for cleanup")
            
        if session_id in self.session_programs:
            program_count = len(self.session_programs[session_id])
            del self.session_programs[session_id]
            
            # Force garbage collection
            gc.collect()
            
            return {
                "status": "cleaned",
                "session_id": session_id,
                "programs_removed": program_count
            }
        else:
            return {
                "status": "not_found",
                "session_id": session_id
            }
    
    def shutdown(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Graceful shutdown command for pool-worker mode.
        
        Args:
            args: Dictionary containing optional worker_id
            
        Returns:
            Dictionary with shutdown acknowledgment
        """
        # Clean up all sessions if in pool-worker mode
        if self.mode == "pool-worker":
            sessions_cleaned = len(self.session_programs)
            self.session_programs.clear()
        else:
            self.programs.clear()
            
        # Force garbage collection
        gc.collect()
        
        return {
            "status": "shutting_down",
            "worker_id": self.worker_id,
            "mode": self.mode,
            "sessions_cleaned": sessions_cleaned if self.mode == "pool-worker" else 0
        }
    
    def _get_memory_usage(self) -> Dict[str, Union[int, str]]:
        """
        Get current memory usage statistics.
        
        Returns:
            Dictionary with memory information
        """
        try:
            import psutil
            process = psutil.Process()
            memory_info = process.memory_info()
            
            return {
                "rss": memory_info.rss,
                "vms": memory_info.vms,
                "percent": process.memory_percent()
            }
        except ImportError:
            return {
                "rss": 0,
                "vms": 0,
                "percent": 0,
                "error": "psutil not available"
            }
    
    def create_gemini_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create a Gemini-based program (custom implementation).
        
        Args:
            args: Dictionary containing:
                - id: Unique program identifier
                - signature: Signature definition with inputs/outputs
                - model: Gemini model name (optional, defaults to gemini-1.5-flash)
                
        Returns:
            Dictionary with program creation status
        """
        if not GEMINI_AVAILABLE:
            raise RuntimeError("Gemini not available - cannot create Gemini programs")
        
        program_id = args.get('id')
        signature_def = args.get('signature', {})
        model_name = args.get('model', 'gemini-1.5-flash')
        
        if not program_id:
            raise ValueError("Program ID is required")
        
        if program_id in self.programs:
            raise ValueError(f"Program with ID '{program_id}' already exists")
        
        try:
            # Create Gemini model instance
            model = genai.GenerativeModel(model_name)
            
            # Store program with Gemini-specific metadata
            self.programs[program_id] = {
                'type': 'gemini',
                'model': model,
                'model_name': model_name,
                'signature': signature_def,
                'created_at': time.time(),
                'execution_count': 0,
                'last_executed': None
            }
            
            return {
                "program_id": program_id,
                "status": "created",
                "type": "gemini",
                "model_name": model_name,
                "signature": signature_def
            }
            
        except Exception as e:
            raise RuntimeError(f"Failed to create Gemini program: {str(e)}")
    
    def execute_gemini_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Execute a Gemini program with given inputs.
        
        Args:
            args: Dictionary containing:
                - program_id: ID of the program to execute
                - inputs: Input values for the program
                
        Returns:
            Dictionary containing program outputs
        """
        program_id = args.get('program_id')
        inputs = args.get('inputs', {})
        
        if not program_id:
            raise ValueError("Program ID is required")
        
        if program_id not in self.programs:
            raise ValueError(f"Program not found: {program_id}")
        
        program_info = self.programs[program_id]
        
        if program_info.get('type') != 'gemini':
            raise ValueError(f"Program {program_id} is not a Gemini program")
        
        model = program_info['model']
        signature_def = program_info['signature']
        
        try:
            # Build prompt from signature and inputs
            prompt = self._build_gemini_prompt(signature_def, inputs)
            
            # Execute with Gemini
            response = model.generate_content(prompt)
            
            # Parse response according to signature
            outputs = self._parse_gemini_response(signature_def, response.text)
            
            # Update execution statistics
            program_info['execution_count'] += 1
            program_info['last_executed'] = time.time()
            
            return {
                "program_id": program_id,
                "outputs": outputs,
                "execution_time": time.time(),
                "raw_response": response.text
            }
            
        except Exception as e:
            raise RuntimeError(f"Gemini program execution failed: {str(e)}")
    
    def _build_gemini_prompt(self, signature_def: Dict[str, Any], inputs: Dict[str, Any]) -> str:
        """Build a prompt for Gemini based on signature and inputs."""
        
        # Get signature information
        input_fields = signature_def.get('inputs', [])
        output_fields = signature_def.get('outputs', [])
        
        # Build the prompt
        prompt_parts = []
        
        # Add instruction based on signature
        if len(output_fields) == 1:
            output_field = output_fields[0]
            instruction = f"Please provide {output_field.get('description', output_field.get('name', 'an answer'))}."
        else:
            output_names = [field.get('name', 'output') for field in output_fields]
            instruction = f"Please provide the following: {', '.join(output_names)}."
        
        prompt_parts.append(instruction)
        
        # Add input information
        for field in input_fields:
            field_name = field.get('name')
            field_value = inputs.get(field_name, '')
            field_desc = field.get('description', '')
            
            if field_desc:
                prompt_parts.append(f"{field_desc}: {field_value}")
            else:
                prompt_parts.append(f"{field_name}: {field_value}")
        
        # Add output format instruction
        output_format_parts = []
        for field in output_fields:
            field_name = field.get('name')
            field_desc = field.get('description', '')
            if field_desc:
                output_format_parts.append(f"{field_name}: [your {field_desc.lower()}]")
            else:
                output_format_parts.append(f"{field_name}: [your response]")
        
        if output_format_parts:
            prompt_parts.append(f"\nPlease respond in this format:\n{chr(10).join(output_format_parts)}")
        
        return "\n\n".join(prompt_parts)
    
    def _parse_gemini_response(self, signature_def: Dict[str, Any], response_text: str) -> Dict[str, str]:
        """Parse Gemini response according to signature definition."""
        
        output_fields = signature_def.get('outputs', [])
        outputs = {}
        
        # Simple parsing - look for "field_name:" patterns
        lines = response_text.strip().split('\n')
        
        for field in output_fields:
            field_name = field.get('name')
            
            # Look for the field in the response
            field_value = ""
            for line in lines:
                if line.lower().startswith(f"{field_name.lower()}:"):
                    field_value = line.split(':', 1)[1].strip()
                    break
            
            # If not found in structured format, use the whole response for single output
            if not field_value and len(output_fields) == 1:
                field_value = response_text.strip()
            
            outputs[field_name] = field_value
        
        return outputs


def read_message() -> Optional[Dict[str, Any]]:
    """
    Read a length-prefixed message from stdin.
    
    Returns:
        Parsed JSON message or None if EOF/error
    """
    try:
        # For Erlang ports, we need to use readexactly-style approach
        # Read 4-byte length header
        length_bytes = sys.stdin.buffer.read(4)
        if len(length_bytes) == 0:  # EOF - process shutdown
            return None
        elif len(length_bytes) < 4:  # Partial read - should not happen with ports
            print(f"Partial length header read: {len(length_bytes)} bytes", file=sys.stderr)
            return None
        
        length = struct.unpack('>I', length_bytes)[0]
        
        # Read message payload
        message_bytes = sys.stdin.buffer.read(length)
        if len(message_bytes) == 0:  # EOF - process shutdown
            return None
        elif len(message_bytes) < length:  # Partial read - should not happen with ports
            print(f"Partial message read: {len(message_bytes)}/{length} bytes", file=sys.stderr)
            return None
        
        # Parse JSON
        message_str = message_bytes.decode('utf-8')
        return json.loads(message_str)
        
    except (EOFError, json.JSONDecodeError, UnicodeDecodeError) as e:
        print(f"Error reading message: {e}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Unexpected error reading message: {e}", file=sys.stderr)
        return None


def write_message(message: Dict[str, Any]) -> None:
    """
    Write a length-prefixed message to stdout.
    
    Args:
        message: Dictionary to send as JSON
    """
    try:
        # Encode message as JSON
        message_str = json.dumps(message, ensure_ascii=False)
        message_bytes = message_str.encode('utf-8')
        length = len(message_bytes)
        
        # Write length header (4 bytes, big-endian) + message
        sys.stdout.buffer.write(struct.pack('>I', length))
        sys.stdout.buffer.write(message_bytes)
        sys.stdout.buffer.flush()
        
    except BrokenPipeError:
        # Pipe was closed by the other end, exit gracefully
        sys.exit(0)
    except Exception as e:
        print(f"Error writing message: {e}", file=sys.stderr)


def main():
    """
    Main event loop for the DSPy bridge.
    
    Reads messages from stdin, processes commands, and writes responses to stdout.
    """
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='DSPy Bridge for Elixir Integration')
    parser.add_argument('--mode', choices=['standalone', 'pool-worker'], default='standalone',
                        help='Bridge operation mode')
    parser.add_argument('--worker-id', type=str, help='Worker ID for pool-worker mode')
    args = parser.parse_args()
    
    # Create bridge with specified mode
    bridge = DSPyBridge(mode=args.mode, worker_id=args.worker_id)
    
    print(f"DSPy Bridge started in {args.mode} mode", file=sys.stderr)
    if args.worker_id:
        print(f"Worker ID: {args.worker_id}", file=sys.stderr)
    print(f"DSPy available: {DSPY_AVAILABLE}", file=sys.stderr)
    
    try:
        while True:
            # Read incoming message
            message = read_message()
            if message is None:
                print("No more messages, exiting", file=sys.stderr)
                break
            
            # Extract message components
            request_id = message.get('id')
            command = message.get('command')
            args = message.get('args', {})
            
            if request_id is None or command is None:
                print(f"Invalid message format: {message}", file=sys.stderr)
                continue
            
            try:
                # Execute command
                result = bridge.handle_command(command, args)
                
                # Send success response
                response = {
                    'id': request_id,
                    'success': True,
                    'result': result,
                    'timestamp': time.time()
                }
                write_message(response)
                
            except Exception as e:
                # Send error response
                error_response = {
                    'id': request_id,
                    'success': False,
                    'error': str(e),
                    'timestamp': time.time()
                }
                write_message(error_response)
                
                # Log error details
                print(f"Command error: {e}", file=sys.stderr)
                print(traceback.format_exc(), file=sys.stderr)
    
    except KeyboardInterrupt:
        print("Bridge interrupted by user", file=sys.stderr)
    except BrokenPipeError:
        # Pipe closed, exit silently
        pass
    except Exception as e:
        print(f"Unexpected bridge error: {e}", file=sys.stderr)
        print(traceback.format_exc(), file=sys.stderr)
    finally:
        # Use try-except for final message to avoid BrokenPipeError on stderr
        try:
            print("DSPy Bridge shutting down", file=sys.stderr)
            sys.stderr.flush()
        except:
            pass


if __name__ == '__main__':
    main()

---
# Test Files
---

---
## Pool V2 Tests
File: test/pool_v2_test.exs
---

defmodule PoolV2Test do
  use ExUnit.Case
  require Logger
  
  alias DSPex.PythonBridge.{SessionPoolV2, PoolWorkerV2}
  alias DSPex.Adapters.PythonPoolV2
  
  @moduletag :layer_3
  @moduletag :pool_v2
  
  setup do
    # Stop existing pool if running
    try do
      Supervisor.terminate_child(DSPex.Supervisor, DSPex.PythonBridge.PoolSupervisor)
      Supervisor.delete_child(DSPex.Supervisor, DSPex.PythonBridge.PoolSupervisor)
    catch
      :exit, _ -> :ok
    end
    
    # Start SessionPoolV2 manually for testing
    {:ok, _pid} = SessionPoolV2.start_link(
      pool_size: 4,  # Small pool for testing
      overflow: 2,
      name: SessionPoolV2
    )
    
    # Small delay for initialization
    Process.sleep(500)
    
    on_exit(fn ->
      # Cleanup
      try do
        GenServer.stop(SessionPoolV2, :normal, 5000)
      catch
        :exit, _ -> :ok
      end
    end)
    
    :ok
  end
  
  describe "V2 Pool Architecture" do
    test "pool starts successfully with lazy workers" do
      # Check that SessionPoolV2 is running
      assert Process.whereis(SessionPoolV2) != nil
      
      # Get pool status
      status = SessionPoolV2.get_pool_status()
      assert is_map(status)
      assert status.pool_size > 0
      assert status.active_sessions == 0  # No sessions yet
      
      IO.puts("Pool V2 started with #{status.pool_size} workers")
    end
    
    test "concurrent operations execute in parallel" do
      # This is the key test - multiple clients should be able to execute simultaneously
      
      # Create multiple tasks that will execute concurrently
      tasks = for i <- 1..5 do
        Task.async(fn ->
          session_id = "concurrent_test_#{i}"
          start_time = System.monotonic_time(:millisecond)
          
          # Execute a simple ping operation
          result = SessionPoolV2.execute_in_session(session_id, :ping, %{
            test_id: i,
            timestamp: DateTime.utc_now()
          })
          
          end_time = System.monotonic_time(:millisecond)
          duration = end_time - start_time
          
          {i, result, duration}
        end)
      end
      
      # Wait for all tasks to complete
      results = Task.await_many(tasks, 10_000)
      
      # Verify all operations succeeded
      for {i, result, duration} <- results do
        assert {:ok, _response} = result
        IO.puts("Task #{i} completed in #{duration}ms")
      end
      
      # If operations were serialized, total time would be ~5x single operation
      # With true concurrency, they should complete in roughly the same time as one
      durations = Enum.map(results, fn {_, _, d} -> d end)
      avg_duration = Enum.sum(durations) / length(durations)
      max_duration = Enum.max(durations)
      
      IO.puts("Average duration: #{avg_duration}ms, Max duration: #{max_duration}ms")
      
      # Max should be less than 2x average if truly concurrent
      assert max_duration < avg_duration * 2
    end
    
    test "session isolation works correctly" do
      # Create programs in different sessions
      session1_id = "session_isolation_test_1"
      session2_id = "session_isolation_test_2"
      
      # Create adapter instances for each session
      adapter1 = PythonPoolV2.session_adapter(session1_id)
      adapter2 = PythonPoolV2.session_adapter(session2_id)
      
      # Create programs in each session
      {:ok, program1_id} = adapter1.create_program.(%{
        signature: %{
          inputs: [%{name: "input", type: "string"}],
          outputs: [%{name: "output", type: "string"}]
        }
      })
      
      {:ok, program2_id} = adapter2.create_program.(%{
        signature: %{
          inputs: [%{name: "input", type: "string"}],
          outputs: [%{name: "output", type: "string"}]
        }
      })
      
      # List programs in each session - should only see their own
      {:ok, programs1} = adapter1.list_programs.()
      {:ok, programs2} = adapter2.list_programs.()
      
      assert program1_id in programs1
      assert program1_id not in programs2
      assert program2_id in programs2
      assert program2_id not in programs1
      
      IO.puts("Session 1 programs: #{inspect(programs1)}")
      IO.puts("Session 2 programs: #{inspect(programs2)}")
    end
    
    test "error handling doesn't affect other operations" do
      # Start multiple operations, some will fail
      tasks = for i <- 1..6 do
        Task.async(fn ->
          session_id = "error_test_#{i}"
          
          result = if rem(i, 2) == 0 do
            # Even numbers: valid operation
            SessionPoolV2.execute_in_session(session_id, :ping, %{test_id: i})
          else
            # Odd numbers: invalid operation that will fail
            SessionPoolV2.execute_in_session(session_id, :invalid_command, %{test_id: i})
          end
          
          {i, result}
        end)
      end
      
      results = Task.await_many(tasks, 10_000)
      
      # Check that even operations succeeded and odd failed
      for {i, result} <- results do
        if rem(i, 2) == 0 do
          assert {:ok, _} = result
          IO.puts("Task #{i} succeeded as expected")
        else
          assert {:error, _} = result
          IO.puts("Task #{i} failed as expected")
        end
      end
    end
    
    test "pool handles worker death gracefully" do
      session_id = "worker_death_test"
      
      # First operation should succeed
      assert {:ok, _} = SessionPoolV2.execute_in_session(session_id, :ping, %{})
      
      # Simulate worker death by sending a command that causes Python to exit
      # This is a controlled test of fault tolerance
      result = SessionPoolV2.execute_in_session(session_id, :force_exit, %{exit_code: 1})
      
      # Should get an error due to port death
      assert {:error, _} = result
      
      # Pool should recover - next operation should work with a new worker
      Process.sleep(1000)  # Give pool time to spawn new worker
      
      assert {:ok, _} = SessionPoolV2.execute_in_session(session_id, :ping, %{
        after_crash: true
      })
      
      IO.puts("Pool recovered from worker death successfully")
    end
    
    test "ETS-based session tracking works" do
      # Create some sessions
      for i <- 1..3 do
        session_id = "tracking_test_#{i}"
        SessionPoolV2.track_session(session_id)
        
        # Update activity
        SessionPoolV2.update_session_activity(session_id)
      end
      
      # Get session info
      sessions = SessionPoolV2.get_session_info()
      assert length(sessions) >= 3
      
      # End a session
      SessionPoolV2.end_session("tracking_test_2")
      
      # Verify it's removed
      sessions_after = SessionPoolV2.get_session_info()
      session_ids = Enum.map(sessions_after, & &1.session_id)
      
      assert "tracking_test_1" in session_ids
      assert "tracking_test_2" not in session_ids
      assert "tracking_test_3" in session_ids
      
      IO.puts("Session tracking working correctly")
    end
  end
  
  describe "V2 Adapter Integration" do
    test "adapter works with real LM configuration" do
      if System.get_env("GEMINI_API_KEY") do
        config = %{
          model: "gemini-1.5-flash",
          api_key: System.get_env("GEMINI_API_KEY"),
          temperature: 0.5,
          provider: :google
        }
        
        assert :ok = PythonPoolV2.configure_lm(config)
        IO.puts("LM configured successfully in V2")
      else
        IO.puts("Skipping LM test - no API key")
      end
    end
    
    test "health check works" do
      assert :ok = PythonPoolV2.health_check()
    end
    
    test "stats include concurrency information" do
      {:ok, stats} = PythonPoolV2.get_stats()
      
      assert stats.adapter_type == :python_pool_v2
      assert stats.true_concurrency == true
      assert is_map(stats.pool_status)
      
      IO.puts("V2 Stats: #{inspect(stats, pretty: true)}")
    end
  end
end

---
## Pool V2 Simple Tests
File: test/pool_v2_simple_test.exs
---

defmodule PoolV2SimpleTest do
  use ExUnit.Case
  require Logger
  
  alias DSPex.PythonBridge.{SessionPoolV2, PoolWorkerV2}
  
  @moduletag :layer_3
  @moduletag :pool_v2_simple
  
  test "simple pool startup test" do
    # Start pool with debug output
    Logger.info("Starting SessionPoolV2...")
    
    {:ok, pid} = SessionPoolV2.start_link(
      pool_size: 1,  # Just one worker
      overflow: 0,
      name: :test_pool_v2
    )
    
    Logger.info("SessionPoolV2 started: #{inspect(pid)}")
    
    # Give it time to initialize
    Process.sleep(2000)
    
    # Check if it's alive
    assert Process.alive?(pid)
    
    # Try to get status using GenServer.call directly with the registered name
    status = GenServer.call(:test_pool_v2, :get_status)
    Logger.info("Pool status: #{inspect(status, pretty: true)}")
    
    # Cleanup
    GenServer.stop(pid, :normal, 5000)
  end
  
  test "simple ping test" do
    # Start pool
    {:ok, pid} = SessionPoolV2.start_link(
      pool_size: 1,
      overflow: 0,
      name: :test_pool_v2_ping
    )
    
    # Give it time to initialize
    Process.sleep(2000)
    
    # Try a simple ping
    result = SessionPoolV2.execute_anonymous(:ping, %{test: true})
    Logger.info("Ping result: #{inspect(result)}")
    
    assert {:ok, _} = result
    
    # Cleanup
    GenServer.stop(pid, :normal, 5000)
  end
end

---
# Summary
---

This document contains all relevant code and documentation for the NimblePool integration in DSPex.
The main issue is that the V2 refactoring encounters worker initialization timeouts when trying to
implement the correct NimblePool pattern where blocking operations happen in client processes.
