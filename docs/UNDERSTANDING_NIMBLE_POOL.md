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
