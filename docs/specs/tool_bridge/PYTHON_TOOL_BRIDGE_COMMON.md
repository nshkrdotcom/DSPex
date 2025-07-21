Integrating the Elixir-Python Tool Bridge across all four potential communication protocols (JSON, MessagePack, gRPC unary, and gRPC streaming) requires careful design. The core RPC logic remains the same, but the transport layer for the request and response packets changes.

Here is a detailed breakdown of how the Tool Bridge will be implemented for each of the four bridges, highlighting the differences and shared components.

### 1. Core Principles (Common to All Bridges)

The fundamental workflow is identical across all protocols:

1.  **Elixir-Side Registration**: `DSPex.ToolRegistry` securely maps an Elixir function (`MFA`) to a unique `tool_id`. This is protocol-agnostic.
2.  **Python-Side Proxy**: A Python `RPCProxyTool` class is instantiated with the `tool_id`. This class is what `dspy.Tool` wraps.
3.  **RPC Invocation**: When `dspy.ReAct` calls the tool, the `RPCProxyTool`'s `__call__` method is invoked.
4.  **Transport**: This is where the protocols differ. The `RPCProxyTool` sends an `rpc_call` request to Elixir and waits for an `rpc_response`.
5.  **Elixir-Side Dispatch**: The Elixir worker receives the `rpc_call`, looks up the `MFA` using the `tool_id`, executes it, and sends the `rpc_response` back.

The primary difference lies in **Step 4: Transport**. How does the Python `RPCProxyTool` send its request and receive its response?

---

### 2. Implementation for Stdin/Stdout Bridges (JSON & MessagePack)

These two bridges use the same underlying transport mechanism: the process's standard input/output streams. The only difference is the serialization format.

**2.1. Python-Side (`enhanced_bridge.py`)**

The implementation is nearly identical for both, managed by the `ProtocolHandler` class.

*   **`RPCProxyTool` Class:**
    ```python
    # enhanced_bridge.py

    class RPCProxyTool:
        def __init__(self, tool_id, protocol_handler):
            self.tool_id = tool_id
            self.protocol_handler = protocol_handler
            # A thread-safe way to store responses for this specific tool instance
            self.response_queue = queue.Queue()

        def __call__(self, *args, **kwargs):
            rpc_id = f"rpc_{uuid.uuid4().hex}"
            
            request = {
                "type": "rpc_call",
                "rpc_id": rpc_id,
                "tool_id": self.tool_id,
                "args": list(args),  # Ensure args are serializable
                "kwargs": kwargs
            }

            # The key change: register a response waiter *before* sending
            self.protocol_handler.register_rpc_waiter(rpc_id, self.response_queue)
            
            # Send the request over stdout
            self.protocol_handler.write_message(request)

            try:
                # Block and wait for the response to be put in our queue
                # The main loop will handle reading from stdin and routing to us
                response = self.response_queue.get(timeout=30) # 30-second timeout for the tool call
            finally:
                # Always clean up the waiter
                self.protocol_handler.unregister_rpc_waiter(rpc_id)
            
            if response.get("status") == "ok":
                return response.get("result")
            else:
                error_info = response.get("error", {})
                raise RuntimeError(f"Elixir tool call failed: {error_info.get('message', 'Unknown error')}")

    ```

*   **`ProtocolHandler` Class (Modification):**
    The main loop needs to be able to distinguish between a final response to the original `execute` command and an intermediate RPC response.

    ```python
    # enhanced_bridge.py -> ProtocolHandler

    class ProtocolHandler:
        def __init__(self, command_handler):
            # ... existing init ...
            self.rpc_waiters = {}
            self.rpc_lock = threading.Lock()

        def register_rpc_waiter(self, rpc_id, queue):
            with self.rpc_lock:
                self.rpc_waiters[rpc_id] = queue
        
        def unregister_rpc_waiter(self, rpc_id):
            with self.rpc_lock:
                self.rpc_waiters.pop(rpc_id, None)

        def run(self):
            # ... existing main loop ...
            while not self.shutdown_requested:
                message = self.read_message()
                if not message: break

                # --- START of MODIFICATION ---
                if message.get("type") == "rpc_response":
                    rpc_id = message.get("rpc_id")
                    with self.rpc_lock:
                        waiter_queue = self.rpc_waiters.get(rpc_id)
                    
                    if waiter_queue:
                        waiter_queue.put(message)
                    else:
                        # Log error: received an RPC response for a call that is no longer waiting
                        safe_print(f"Warning: Received unsolicited RPC response for {rpc_id}")
                else:
                    # This is a standard command/response message, handle as before
                    request_id = message.get("id")
                    # ... rest of the existing command processing logic ...
                # --- END of MODIFICATION ---
    ```

**2.2. Elixir-Side (`Snakepit.Pool.Worker`)**

The worker needs to be able to handle incoming `rpc_call` messages and send `rpc_response` messages.

```elixir
# lib/snakepit/pool/worker.ex

def handle_info({port, {:data, data}}, %{port: port} = state) do
  # ... (use state.protocol_format for decoding)
  case Protocol.decode_message(data, format: state.protocol_format) do
    # --- START of MODIFICATION ---
    %{"type" => "rpc_call", "rpc_id" => rpc_id, "tool_id" => tool_id, "args" => args} = rpc_req ->
      kwargs = Map.get(rpc_req, "kwargs", %{})
      
      # Execute the tool and send response back immediately
      Task.Supervisor.async_nolink(Snakepit.TaskSupervisor, fn ->
        response = execute_elixir_tool(tool_id, args, kwargs)
        
        response_packet = %{
          "type" => "rpc_response",
          "rpc_id" => rpc_id
        } |> Map.merge(response)

        encoded_response = Protocol.encode_message(response_packet, format: state.protocol_format)
        Port.command(state.port, encoded_response)
      end)
      
      {:noreply, state} # Continue waiting for the final response from dspy.ReAct

    # --- END of MODIFICATION ---

    %{"id" => request_id, "success" => true, "result" => result} ->
      handle_response(request_id, {:ok, result}, state)
    
    # ... other existing message handlers ...
  end
end

defp execute_elixir_tool(tool_id, args, kwargs) do
  try do
    with {:ok, {module, fun, _arity}} <- DSPex.ToolRegistry.lookup(tool_id) do
      # In Elixir, we can treat kwargs as the last map argument if applicable
      final_args = if map_size(kwargs) > 0, do: args ++ [kwargs], else: args
      result = apply(module, fun, final_args)
      %{"status" => "ok", "result" => result}
    end
  catch
    kind, reason ->
      stacktrace = System.stacktrace()
      %{"status" => "error", "error" => %{
        "type" => Atom.to_string(kind),
        "message" => Exception.message(reason),
        "stacktrace" => Exception.format(kind, reason, stacktrace)
      }}
  end
end
```

---

### 3. Implementation for gRPC Bridge (Non-Streaming/Unary)

The gRPC bridge uses a separate communication channel, making the RPC callback cleaner. We will add a new RPC method to our Protobuf definition.

**3.1. Protobuf Definition (`snakepit.proto`)**

Add a new service method for the tool callback.

```protobuf
// snakepit.proto

service SnakepitBridge {
  // ... existing methods (Execute, ExecuteStream, etc.) ...
  
  // NEW RPC method for tool callbacks
  rpc ToolCall(ToolCallRequest) returns (ToolCallResponse) {}
}

message ToolCallRequest {
  string rpc_id = 1;
  string tool_id = 2;
  // Using JSON strings to represent flexible args/kwargs
  string args_json = 3;
  string kwargs_json = 4;
}

message ToolCallResponse {
  string rpc_id = 1;
  bool success = 2;
  bytes result = 3; // Use bytes to send back any JSON-serializable result
  string error_message = 4;
}
```
After updating, regenerate the Elixir and Python gRPC files (`make proto-elixir`, `make proto-python`).

**3.2. Python-Side (`grpc_bridge.py`)**

*   **`RPCProxyTool` Class:**
    ```python
    # grpc_bridge.py

    class RPCProxyTool:
        def __init__(self, tool_id, grpc_channel):
            self.tool_id = tool_id
            self.stub = snakepit_pb2_grpc.SnakepitBridgeStub(grpc_channel)

        def __call__(self, *args, **kwargs):
            rpc_id = f"rpc_{uuid.uuid4().hex}"
            
            request = snakepit_pb2.ToolCallRequest(
                rpc_id=rpc_id,
                tool_id=self.tool_id,
                args_json=json.dumps(list(args)),
                kwargs_json=json.dumps(kwargs)
            )

            # This is a synchronous gRPC call back to the Elixir host
            response = self.stub.ToolCall(request, timeout=30)
            
            if response.success:
                # The result is bytes, so we need to decode it
                return json.loads(response.result.decode('utf-8'))
            else:
                raise RuntimeError(f"Elixir tool call failed: {response.error_message}")
    ```

*   **`SnakepitBridgeServicer` (Modification):**
    The main `Execute` method, when creating `dspy.ReAct`, needs access to the gRPC channel to pass to the `RPCProxyTool`. The servicer can get this from the gRPC context.

**3.3. Elixir-Side (`Snakepit.GRPCWorker` and a new gRPC Service)**

We need a separate gRPC **server** running in the Elixir worker process to receive the callback. This is a significant architectural addition. A simpler approach is to reuse the existing Elixir -> Python channel for a reverse call, but that requires a more complex bidirectional streaming setup.

A more pragmatic approach for unary gRPC: **The Python gRPC bridge will need to expose its own gRPC server endpoint for Elixir to call into.** This is complex.

**A much simpler, elegant solution:** Instead of a reverse gRPC call, we can **leverage the gRPC server's stdout stream**, which is already connected to the Elixir worker's port via `use_stdio`. We can send our RPC messages over that channel.

This means the **gRPC implementation will reuse the JSON/MessagePack logic**. The `RPCProxyTool` will simply call `protocol_handler.write_message()` and the main gRPC service loop will check for incoming `rpc_response` messages on stdin. This unifies the logic and avoids complex reverse gRPC setups.

---

### 4. Implementation for gRPC Bridge (Streaming)

This is the most complex scenario. A tool call is a synchronous request-response action happening *inside* a larger streaming operation.

**The Challenge:** A gRPC service method can either be unary (returns one response) or streaming (returns a stream of responses). It cannot block to make a synchronous callback and then continue streaming.

**The Solution: Multiplexing over the Stream**

We will multiplex our RPC messages over the *same gRPC stream* that `dspy.ReAct` is using to yield its own results.

**4.1. Protobuf Definition (`snakepit.proto`)**

We modify the `StreamResponse` to be a versatile message that can carry either a data chunk *or* an RPC call.

```protobuf
// snakepit.proto

message StreamResponse {
  string request_id = 1;
  int32 chunk_index = 2;
  
  oneof payload {
    StreamChunk chunk = 3;
    ToolCallRequest rpc_call = 4; // Python asks Elixir to run a tool
  }
}

message StreamChunk {
  bytes data = 1;
  bool is_final = 2;
  string error = 3;
}

message ToolCallRequest { ... } // Same as before

// Elixir will respond to the ToolCallRequest via the Python worker's port (stdio)
// using the same rpc_response format as the JSON/MessagePack bridges.
```

**4.2. Python-Side (`grpc_bridge.py`)**

*   **`RPCProxyTool`:**
    It will now send a `StreamResponse` containing a `ToolCallRequest` and wait for the response on `stdin`. This elegantly reuses the logic from the JSON/MessagePack bridges.

*   **`SnakepitBridgeServicer.ExecuteStream`:**
    When the `dspy.ReAct` generator yields an `RPCProxyTool`'s special RPC request object, the servicer will wrap it in a `StreamResponse` protobuf message and `yield` it to Elixir.

**4.3. Elixir-Side (`Snakepit.GRPCWorker`)**

The `execute_stream` logic in the worker will now have to handle two types of payloads from the stream:
1.  **`StreamChunk`**: A regular data chunk from `dspy.ReAct`. This is passed to the user's callback function.
2.  **`ToolCallRequest`**: An RPC request. The worker will execute the tool and send the `rpc_response` back to the Python process's `stdin` port, just like in the JSON/MessagePack implementation.

This design cleverly uses the gRPC stream for Python -> Elixir communication and the existing stdio port for the reverse Elixir -> Python channel, neatly solving the synchronous-call-inside-a-stream problem.

### Summary Table

| Protocol | Python->Elixir RPC Transport | Elixir->Python RPC Transport | Key Implementation Detail |
| :--- | :--- | :--- | :--- |
| **JSON** | `stdout` Port | `stdin` Port | `ProtocolHandler` multiplexes standard responses and RPC responses on `stdin`. |
| **MessagePack** | `stdout` Port | `stdin` Port | Same as JSON, but with `msgpack` serialization for better performance. |
| **gRPC Unary** | `stdout` Port | `stdin` Port | **Reuses the stdio port mechanism.** Avoids complex reverse gRPC setup. Main gRPC channel is for the final result only. |
| **gRPC Stream** | gRPC Stream (multiplexed) | `stdin` Port | `StreamResponse` protobuf is extended to carry either data chunks or RPC requests. The `stdin` port is used for the synchronous tool response. |
