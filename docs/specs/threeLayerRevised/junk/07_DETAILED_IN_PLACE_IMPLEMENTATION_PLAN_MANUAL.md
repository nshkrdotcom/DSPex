# Detailed In-Place Implementation Plan

## Overview

## Overview
This plan implements the **Light Snakepit + Heavy Bridge** architecture by building in place without legacy support. We'll
**Strategy**: Ruthless refactoring with clear boundaries and aggressive cleanup.
## Phase 1: Purify Snakepit & Bootstrap Bridge (Week 1)
### Day 1: Audit Snakepit Domain Logic
**Objective:** Identify all ML/DSPy/gRPC domain logic within the `snakepit` application.
**Morning: Systematic Codebase Audit**
```bash
# Audit all Python files for ML/DSPy code
find ./snakepit/priv/python -name "*.py" -exec head -20 {} \; | grep -i "dspy\|ml\|torch\|tensor"
# Create kill list manifest
echo "SNAKEPIT PURIFICATION KILL LIST" > snakepit_purification_manifest.md
```
### Day 3: Prove Snakepit Generality
**Objective:** Confirm `snakepit` is completely domain-agnostic.
**Morning: Create MockAdapter Test**
```elixir
# test/support/mock_adapter.ex
### Day 4: Bootstrap SnakepitGRPCBridge Package
**Objective:** Create the new SnakepitGRPCBridge package and move domain logic.
**Morning: Create New Package Structure**
```bash
# Create the ML platform package
# Create ML platform directory structure
**Afternoon: Move Domain Logic to New Package**
# Move any domain-specific Elixir code identified in audit
# (Most will be newly written, but some might exist)
# Set up basic adapter stub that will integrate with purified Snakepit
```
```elixir
# lib/snakepit_grpc_bridge/adapter.ex
defmodule SnakepitGRPCBridge.Adapter do
@impl Snakepit.Adapter
def execute(command, args, opts) do
result = route_command(command, args, opts)
@impl Snakepit.Adapter
def init(config) do
@impl Snakepit.Adapter
def start_worker(adapter_state, worker_id) do
defp route_command(command, args, opts) do
case command do
defp collect_telemetry(command, args, result, execution_time, session_id) do
:telemetry.execute(
### Day 3: Build Variables System
**Morning: Variables Manager**
defstruct [
:sessions,           # ETS table for session data
def start_link(opts \\ []) do
GenServer.start_link(__MODULE__, opts, name: __MODULE__)
end
def init(_opts) do
# Public API
def get(session_id, identifier, default \\ nil) do
GenServer.call(__MODULE__, {:get, session_id, identifier, default})
def set(session_id, identifier, value, opts \\ []) do
GenServer.call(__MODULE__, {:set, session_id, identifier, value, opts})
end
def list(session_id) do
GenServer.call(__MODULE__, {:list, session_id})
\ No newline at end of file
GenServer.call(__MODULE__, {:delete, session_id, identifier})
end
\ No newline at end of file
def handle_call({:create, session_id, name, type, value, opts}, _from, state) do
variable_key = {session_id, name}
variable = %{
name: name,
type: type,
value: value,
created_at: DateTime.utc_now(),
metadata: opts[:metadata] || %{}
}
:ets.insert(state.variables, {variable_key, variable})
Logger.debug("Variable created", session_id: session_id, name: name, type: type)
{:reply, {:ok, variable}, state}
end
def handle_call({:get, session_id, identifier, default}, _from, state) do
variable_key = {session_id, identifier}
case :ets.lookup(state.variables, variable_key) do
[{^variable_key, variable}] ->
{:reply, {:ok, variable.value}, state}
[] ->
{:reply, {:ok, default}, state}
end
end
def handle_call({:set, session_id, identifier, value, _opts}, _from, state) do
variable_key = {session_id, identifier}
case :ets.lookup(state.variables, variable_key) do
[{^variable_key, variable}] ->
updated_variable = %{variable |
value: value,
updated_at: DateTime.utc_now()
}
:ets.insert(state.variables, {variable_key, updated_variable})
{:reply, :ok, state}
[] ->
{:reply, {:error, :variable_not_found}, state}
end
end
def handle_call({:list, session_id}, _from, state) do
pattern = {{session_id, :_}, :_}
variables = :ets.match_object(state.variables, pattern)
variable_list = Enum.map(variables, fn {{_session, name}, variable} ->
%{name: name, type: variable.type, value: variable.value}
end)
{:reply, {:ok, variable_list}, state}
end
def handle_call({:delete, session_id, identifier}, _from, state) do
variable_key = {session_id, identifier}
:ets.delete(state.variables, variable_key)
{:reply, :ok, state}
end
end
```
**Afternoon: ML Types System**
```elixir
# lib/snakepit_grpc_bridge/variables/types.ex
defmodule SnakepitGRPCBridge.Variables.Types do
@moduledoc """
Type system for ML variables with serialization support.
"""
@supported_types [
:string, :integer, :float, :boolean, :binary,
:tensor, :embedding, :model, :dataset
]
def supported_types, do: @supported_types
def validate_type(type) when type in @supported_types, do: :ok
def validate_type(type), do: {:error, {:unsupported_type, type}}
def serialize_value(value, :tensor) do
# Tensor serialization logic
{:ok, :erlang.term_to_binary(value)}
end
def serialize_value(value, :embedding) do
# Embedding serialization logic
{:ok, Jason.encode!(value)}
end
def serialize_value(value, _type) do
# Default serialization
{:ok, :erlang.term_to_binary(value)}
end
def deserialize_value(data, :tensor) do
# Tensor deserialization logic
{:ok, :erlang.binary_to_term(data)}
end
def deserialize_value(data, :embedding) do
# Embedding deserialization logic
case Jason.decode(data) do
{:ok, value} -> {:ok, value}
{:error, reason} -> {:error, {:deserialization_failed, reason}}
end
end
def deserialize_value(data, _type) do
# Default deserialization
{:ok, :erlang.binary_to_term(data)}
end
end
```
### Day 4: Build Tools System
**Morning: Tools Registry**
```elixir
# lib/snakepit_grpc_bridge/tools/registry.ex
defmodule SnakepitGRPCBridge.Tools.Registry do
use GenServer
require Logger
defstruct [
:tools,              # ETS table for registered tools
:telemetry_collector
]
def start_link(opts \\ []) do
GenServer.start_link(__MODULE__, opts, name: __MODULE__)
end
def init(_opts) do
state = %__MODULE__{
tools: :ets.new(:tools_registry, [:set, :public, :named_table]),
telemetry_collector: :ok
}
Logger.info("Tools registry started")
{:ok, state}
end
# Public API
def register_tool(session_id, name, function, metadata \\ %{}) do
GenServer.call(__MODULE__, {:register_tool, session_id, name, function, metadata})
end
def unregister_tool(session_id, name) do
GenServer.call(__MODULE__, {:unregister_tool, session_id, name})
end
def list_tools(session_id) do
GenServer.call(__MODULE__, {:list_tools, session_id})
end
def get_tool(session_id, name) do
GenServer.call(__MODULE__, {:get_tool, session_id, name})
end
# GenServer callbacks
def handle_call({:register_tool, session_id, name, function, metadata}, _from, state) do
tool_key = {session_id, name}
tool = %{
name: name,
function: function,
metadata: metadata,
registered_at: DateTime.utc_now(),
session_id: session_id
}
:ets.insert(state.tools, {tool_key, tool})
Logger.debug("Tool registered", session_id: session_id, name: name)
{:reply, :ok, state}
end
def handle_call({:unregister_tool, session_id, name}, _from, state) do
tool_key = {session_id, name}
:ets.delete(state.tools, tool_key)
Logger.debug("Tool unregistered", session_id: session_id, name: name)
{:reply, :ok, state}
end
def handle_call({:list_tools, session_id}, _from, state) do
pattern = {{session_id, :_}, :_}
tools = :ets.match_object(state.tools, pattern)
tool_list = Enum.map(tools, fn {{_session, name}, tool} ->
%{
name: name,
metadata: tool.metadata,
registered_at: tool.registered_at
}
end)
{:reply, {:ok, tool_list}, state}
end
def handle_call({:get_tool, session_id, name}, _from, state) do
tool_key = {session_id, name}
case :ets.lookup(state.tools, tool_key) do
[{^tool_key, tool}] -> {:reply, {:ok, tool}, state}
[] -> {:reply, {:error, :tool_not_found}, state}
end
end
end
```
**Afternoon: Tools Executor**
```elixir
# lib/snakepit_grpc_bridge/tools/executor.ex
defmodule SnakepitGRPCBridge.Tools.Executor do
require Logger
def execute_tool(session_id, tool_name, parameters) do
start_time = System.monotonic_time(:microsecond)
case SnakepitGRPCBridge.Tools.Registry.get_tool(session_id, tool_name) do
{:ok, tool} ->
execute_function(tool, parameters, session_id, start_time)
{:error, :tool_not_found} ->
{:error, {:tool_not_found, tool_name}}
end
end
defp execute_function(tool, parameters, session_id, start_time) do
try do
result = tool.function.(parameters)
execution_time = System.monotonic_time(:microsecond) - start_time
# Collect telemetry
collect_execution_telemetry(tool.name, parameters, result, execution_time, session_id)
{:ok, result}
rescue
exception ->
execution_time = System.monotonic_time(:microsecond) - start_time
error = Exception.message(exception)
# Collect error telemetry
collect_execution_telemetry(tool.name, parameters, {:error, error}, execution_time, session_id)
Logger.error("Tool execution failed",
tool: tool.name,
session_id: session_id,
error: error)
{:error, {:execution_failed, error}}
end
end
defp collect_execution_telemetry(tool_name, parameters, result, execution_time, session_id) do
:telemetry.execute(
[:snakepit_grpc_bridge, :tools, :execution],
%{
execution_time: execution_time,
success: match?({:ok, _}, result)
},
%{
tool_name: tool_name,
session_id: session_id,
parameters_size: :erlang.external_size(parameters)
}
)
end
end
```
### Day 5: Create Clean APIs
**Morning: Variables API**
```elixir
# lib/snakepit_grpc_bridge/api/variables.ex
defmodule SnakepitGRPCBridge.API.Variables do
@moduledoc """
Clean API for variable management operations.
"""
alias SnakepitGRPCBridge.Variables.{Manager, Types}
def create(session_id, name, type, value, opts \\ []) do
with :ok <- Types.validate_type(type),
{:ok, variable} <- Manager.create(session_id, name, type, value, opts) do
{:ok, variable}
end
end
def get(session_id, identifier, default \\ nil) do
Manager.get(session_id, identifier, default)
end
def set(session_id, identifier, value, opts \\ []) do
Manager.set(session_id, identifier, value, opts)
end
def list(session_id) do
Manager.list(session_id)
end
def delete(session_id, identifier) do
Manager.delete(session_id, identifier)
end
# ML-specific variable creation
def create_tensor(session_id, name, data, opts \\ []) do
create(session_id, name, :tensor, data, opts)
end
def create_embedding(session_id, name, vector, opts \\ []) do
create(session_id, name, :embedding, vector, opts)
end
def create_model(session_id, name, model_instance, opts \\ []) do
create(session_id, name, :model, model_instance, opts)
end
end
```
**Afternoon: Tools API**
```elixir
# lib/snakepit_grpc_bridge/api/tools.ex
defmodule SnakepitGRPCBridge.API.Tools do
@moduledoc """
Clean API for tool bridge operations.
"""
alias SnakepitGRPCBridge.Tools.{Registry, Executor}
def register_elixir_function(session_id, name, function, opts \\ []) do
metadata = %{
description: Keyword.get(opts, :description, ""),
parameters: Keyword.get(opts, :parameters, []),
returns: Keyword.get(opts, :returns, %{}),
type: :elixir_function,
registered_at: DateTime.utc_now()
}
Registry.register_tool(session_id, name, function, metadata)
end
def register_python_function(session_id, name, python_function_path, opts \\ []) do
# Placeholder for Python function registration
python_function = fn parameters ->
# This would call into Python bridge
SnakepitGRPCBridge.Python.Bridge.call_function(python_function_path, parameters)
end
metadata = %{
description: Keyword.get(opts, :description, ""),
parameters: Keyword.get(opts, :parameters, []),
type: :python_function,
python_path: python_function_path,
registered_at: DateTime.utc_now()
}
Registry.register_tool(session_id, name, python_function, metadata)
end
def call(session_id, tool_name, parameters) do
Executor.execute_tool(session_id, tool_name, parameters)
end
def list(session_id) do
Registry.list_tools(session_id)
end
def unregister(session_id, tool_name) do
Registry.unregister_tool(session_id, tool_name)
end
end
```
## Phase 2: Build DSPy System (Week 2)
### Day 6: DSPy Integration Core
**Morning: DSPy Integration Module**
```elixir
# lib/snakepit_grpc_bridge/dspy/integration.ex
defmodule SnakepitGRPCBridge.DSPy.Integration do
use GenServer
require Logger
defstruct [
:python_bridge,
:schema_cache,
:telemetry_collector
]
def start_link(opts \\ []) do
GenServer.start_link(__MODULE__, opts, name: __MODULE__)
end
def init(_opts) do
state = %__MODULE__{
python_bridge: nil,  # Will be set when Python bridge is ready
schema_cache: :ets.new(:dspy_schema_cache, [:set, :private]),
telemetry_collector: :ok
}
Logger.info("DSPy integration started")
{:ok, state}
end
# Public API
def call_dspy(class_path, method, args, kwargs, opts \\ []) do
GenServer.call(__MODULE__, {:call_dspy, class_path, method, args, kwargs, opts})
end
def discover_schema(module_path, opts \\ []) do
GenServer.call(__MODULE__, {:discover_schema, module_path, opts})
end
# GenServer callbacks
def handle_call({:call_dspy, class_path, method, args, kwargs, opts}, _from, state) do
start_time = System.monotonic_time(:microsecond)
session_id = opts[:session_id]
# This would call into Python bridge
result = execute_dspy_call(class_path, method, args, kwargs, session_id)
execution_time = System.monotonic_time(:microsecond) - start_time
collect_dspy_telemetry(class_path, method, result, execution_time, session_id)
{:reply, result, state}
end
def handle_call({:discover_schema, module_path, opts}, _from, state) do
cache_key = {module_path, opts}
case :ets.lookup(state.schema_cache, cache_key) do
[{^cache_key, cached_schema}] ->
Logger.debug("Schema cache hit", module_path: module_path)
{:reply, {:ok, cached_schema}, state}
[] ->
case discover_schema_from_python(module_path, opts) do
{:ok, schema} ->
:ets.insert(state.schema_cache, {cache_key, schema})
Logger.debug("Schema discovered and cached", module_path: module_path)
{:reply, {:ok, schema}, state}
{:error, reason} ->
{:reply, {:error, reason}, state}
end
end
end
defp execute_dspy_call(class_path, method, args, kwargs, session_id) do
# Placeholder for Python bridge call
# This would actually call into the Python bridge
Logger.debug("DSPy call", class_path: class_path, method: method, session_id: session_id)
# Mock response for now
{:ok, %{
"success" => true,
"result" => %{"mock" => "response"},
"type" => "dspy_call"
}}
end
defp discover_schema_from_python(module_path, _opts) do
# Placeholder for Python bridge schema discovery
Logger.debug("Schema discovery", module_path: module_path)
# Mock schema for now
{:ok, %{
"module" => module_path,
"classes" => %{
"Predict" => %{
"methods" => ["__init__", "__call__"],
"signature" => "input -> output"
}
}
}}
end
defp collect_dspy_telemetry(class_path, method, result, execution_time, session_id) do
:telemetry.execute(
[:snakepit_grpc_bridge, :dspy, :call],
%{
execution_time: execution_time,
success: match?({:ok, _}, result)
},
%{
class_path: class_path,
method: method,
session_id: session_id
}
)
end
end
```
**Afternoon: Enhanced DSPy Features**
```elixir
# lib/snakepit_grpc_bridge/dspy/enhanced.ex
defmodule SnakepitGRPCBridge.DSPy.Enhanced do
@moduledoc """
Enhanced DSPy features with optimization and intelligence.
"""
require Logger
def predict(session_id, signature, inputs, opts \\ []) do
start_time = System.monotonic_time(:microsecond)
# Enhanced prediction with variable integration
enhanced_inputs = integrate_session_variables(session_id, inputs)
result = SnakepitGRPCBridge.DSPy.Integration.call_dspy(
"dspy.Predict",
"__call__",
[],
Map.merge(enhanced_inputs, %{"signature" => signature}),
Keyword.put(opts, :session_id, session_id)
)
execution_time = System.monotonic_time(:microsecond) - start_time
collect_enhanced_telemetry("predict", signature, result, execution_time, session_id)
result
end
def chain_of_thought(session_id, signature, inputs, opts \\ []) do
start_time = System.monotonic_time(:microsecond)
# Enhanced chain of thought with reasoning capture
enhanced_inputs = integrate_session_variables(session_id, inputs)
result = SnakepitGRPCBridge.DSPy.Integration.call_dspy(
"dspy.ChainOfThought",
"__call__",
[],
Map.merge(enhanced_inputs, %{"signature" => signature}),
Keyword.put(opts, :session_id, session_id)
)
execution_time = System.monotonic_time(:microsecond) - start_time
collect_enhanced_telemetry("chain_of_thought", signature, result, execution_time, session_id)
result
end
defp integrate_session_variables(session_id, inputs) do
# Get relevant variables from session
case SnakepitGRPCBridge.API.Variables.list(session_id) do
{:ok, variables} ->
# Add relevant variables to inputs
variable_map = variables
|> Enum.filter(&ml_relevant_variable?/1)
|> Enum.into(%{}, fn var -> {var.name, var.value} end)
Map.merge(inputs, variable_map)
{:error, _} ->
inputs
end
end
defp ml_relevant_variable?(variable) do
# Determine if variable is relevant for ML operations
variable.name in ["temperature", "max_tokens", "model", "top_p"] or
String.starts_with?(variable.name, "ml_")
end
defp collect_enhanced_telemetry(operation, signature, result, execution_time, session_id) do
:telemetry.execute(
[:snakepit_grpc_bridge, :dspy, :enhanced],
%{
execution_time: execution_time,
success: match?({:ok, _}, result)
},
%{
operation: operation,
signature: signature,
session_id: session_id
}
)
end
end
```
### Day 7: Complete DSPy API
**Morning: DSPy API Module**
```elixir
# lib/snakepit_grpc_bridge/api/dspy.ex
defmodule SnakepitGRPCBridge.API.DSPy do
@moduledoc """
Clean API for DSPy integration operations.
"""
alias SnakepitGRPCBridge.DSPy.{Integration, Enhanced}
def call(session_id, class_path, method, kwargs, opts \\ []) do
Integration.call_dspy(class_path, method, [], kwargs,
Keyword.put(opts, :session_id, session_id))
end
def enhanced_predict(session_id, signature, inputs, opts \\ []) do
Enhanced.predict(session_id, signature, inputs, opts)
end
def enhanced_chain_of_thought(session_id, signature, inputs, opts \\ []) do
Enhanced.chain_of_thought(session_id, signature, inputs, opts)
end
def discover_schema(module_path, opts \\ []) do
Integration.discover_schema(module_path, opts)
end
def create_workflow(session_id, steps, opts \\ []) do
# Placeholder for workflow creation
workflow_id = generate_workflow_id()
workflow = %{
id: workflow_id,
session_id: session_id,
steps: steps,
created_at: DateTime.utc_now(),
metadata: opts[:metadata] || %{}
}
# Store workflow (would use proper storage)
Logger.debug("Workflow created", workflow_id: workflow_id, steps: length(steps))
{:ok, workflow}
end
def execute_workflow(session_id, workflow_id, inputs, opts \\ []) do
# Placeholder for workflow execution
Logger.debug("Executing workflow", workflow_id: workflow_id, session_id: session_id)
# Would execute workflow steps in sequence
{:ok, %{
workflow_id: workflow_id,
results: %{},
executed_at: DateTime.utc_now()
}}
end
defp generate_workflow_id do
"workflow_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
end
end
```
**Afternoon: Python Bridge Management**
```elixir
# lib/snakepit_grpc_bridge/python/bridge.ex
defmodule SnakepitGRPCBridge.Python.Bridge do
use GenServer
require Logger
defstruct [
:python_process,
:grpc_port,
:status
]
def start_link(opts \\ []) do
GenServer.start_link(__MODULE__, opts, name: __MODULE__)
end
def init(_opts) do
# Start Python bridge process
case start_python_process() do
{:ok, python_process, grpc_port} ->
state = %__MODULE__{
python_process: python_process,
grpc_port: grpc_port,
status: :ready
}
Logger.info("Python bridge started", grpc_port: grpc_port)
{:ok, state}
{:error, reason} ->
Logger.error("Failed to start Python bridge", reason: reason)
{:stop, reason}
end
end
def call_function(function_path, parameters) do
GenServer.call(__MODULE__, {:call_function, function_path, parameters})
end
def handle_call({:call_function, function_path, parameters}, _from, state) do
# Make gRPC call to Python process
result = make_grpc_call(state.grpc_port, function_path, parameters)
{:reply, result, state}
end
defp start_python_process do
# Start Python bridge server
python_script = Application.app_dir(:snakepit_grpc_bridge, "priv/python/snakepit_bridge/main.py")
case System.cmd("python3", [python_script], []) do
{_output, 0} ->
# Python process started, get gRPC port
grpc_port = 50051  # Would get actual port from Python process
{:ok, :mock_process, grpc_port}
{error, exit_code} ->
{:error, {:python_start_failed, exit_code, error}}
end
end
defp make_grpc_call(grpc_port, function_path, parameters) do
# Make actual gRPC call to Python
Logger.debug("Python gRPC call",
function_path: function_path,
grpc_port: grpc_port)
# Mock response for now
{:ok, %{"result" => "mock_python_response"}}
end
end
```
## Phase 3: Transform Snakepit Infrastructure (Week 3)
### Day 8: Clean Out Snakepit
**Morning: Remove All ML Code**
```bash
cd snakepit
# Remove all ML-specific code
rm -rf lib/snakepit/bridge/
rm -rf priv/python/
rm -rf lib/snakepit/variables/  # If exists
rm -rf lib/snakepit/tools/      # If exists
# Keep only infrastructure
# lib/snakepit/
# ├── pool/
# ├── session_helpers.ex
# └── application.ex
```
**Afternoon: Create Generic Adapter Behavior**
```elixir
# lib/snakepit/adapter.ex (NEW)
defmodule Snakepit.Adapter do
@moduledoc """
Behavior for external process adapters.
Defines the interface that bridge packages must implement to integrate
with Snakepit infrastructure.
"""
@doc """
Execute a command through the external process.
"""
@callback execute(command :: String.t(), args :: map(), opts :: keyword()) ::
{:ok, term()} | {:error, term()}
@doc """
Execute a streaming command with callback.
"""
@callback execute_stream(
command :: String.t(),
args :: map(),
callback :: (term() -> any()),
opts :: keyword()
) :: :ok | {:error, term()}
@doc """
Initialize adapter with configuration.
"""
@callback init(config :: keyword()) :: {:ok, term()} | {:error, term()}
@doc """
Clean up adapter resources.
"""
@callback terminate(reason :: term(), adapter_state :: term()) :: term()
@doc """
Start a worker process for this adapter.
"""
@callback start_worker(adapter_state :: term(), worker_id :: term()) ::
{:ok, pid()} | {:error, term()}
# Optional callbacks
@optional_callbacks [
execute_stream: 4,
init: 1,
terminate: 2,
start_worker: 2
]
@doc """
Validate that a module properly implements the Snakepit.Adapter behavior.
"""
def validate_implementation(module) do
required_callbacks = [{:execute, 3}]
missing_callbacks = Enum.filter(required_callbacks, fn {function, arity} ->
not function_exported?(module, function, arity)
end)
if Enum.empty?(missing_callbacks) do
:ok
else
{:error, missing_callbacks}
end
end
end
```
### Day 9: Refactor Pool to Use Adapters
**Morning: Update Pool Module**
```elixir
# lib/snakepit/pool/pool.ex (MAJOR REFACTOR)
defmodule Snakepit.Pool do
use GenServer
require Logger
defstruct [
:workers,
:available_workers,
:busy_workers,
:adapter_module,
:adapter_state,
:session_affinity_tracker,
:stats
]
def start_link(opts \\ []) do
GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
end
def init(opts) do
# Get adapter module from configuration
adapter_module = opts[:adapter_module] ||
Application.get_env(:snakepit, :adapter_module) ||
raise "Snakepit: adapter_module must be configured"
# Validate adapter implements required behavior
case Snakepit.Adapter.validate_implementation(adapter_module) do
:ok -> :ok
{:error, missing} ->
raise "Snakepit: adapter_module missing callbacks: #{inspect(missing)}"
end
# Initialize adapter
case adapter_module.init(opts) do
{:ok, adapter_state} ->
state = %__MODULE__{
workers: [],
available_workers: [],
busy_workers: MapSet.new(),
adapter_module: adapter_module,
adapter_state: adapter_state,
session_affinity_tracker: %{},
stats: initialize_stats()
}
case start_initial_workers(state) do
{:ok, updated_state} ->
Logger.info("Snakepit pool started",
adapter: adapter_module,
workers: length(updated_state.workers))
{:ok, updated_state}
{:error, reason} ->
{:stop, reason}
end
{:error, reason} ->
{:stop, {:adapter_init_failed, reason}}
end
end
# Public API
def execute(command, args, opts \\ []) do
GenServer.call(__MODULE__, {:execute, command, args, opts})
end
def execute_stream(command, args, callback_fn, opts \\ []) do
GenServer.call(__MODULE__, {:execute_stream, command, args, callback_fn, opts})
end
# GenServer callbacks
def handle_call({:execute, command, args, opts}, _from, state) do
start_time = System.monotonic_time(:microsecond)
session_id = opts[:session_id]
case select_optimal_worker(state, session_id) do
{:ok, worker_pid} ->
# Execute through adapter
result = execute_on_worker(worker_pid, state.adapter_module, command, args, opts)
execution_time = System.monotonic_time(:microsecond) - start_time
updated_state = update_stats(state, result, execution_time)
{:reply, result, updated_state}
{:error, reason} ->
{:reply, {:error, reason}, state}
end
end
def handle_call({:execute_stream, command, args, callback_fn, opts}, _from, state) do
if function_exported?(state.adapter_module, :execute_stream, 4) do
case select_optimal_worker(state, opts[:session_id]) do
{:ok, worker_pid} ->
result = state.adapter_module.execute_stream(command, args, callback_fn,
Keyword.put(opts, :worker_pid, worker_pid))
{:reply, result, state}
{:error, reason} ->
{:reply, {:error, reason}, state}
end
else
{:reply, {:error, :streaming_not_supported}, state}
end
end
defp select_optimal_worker(state, session_id) do
cond do
session_id && Map.has_key?(state.session_affinity_tracker, session_id) ->
worker_pid = Map.get(state.session_affinity_tracker, session_id)
if worker_pid in state.available_workers do
{:ok, worker_pid}
else
select_load_balanced_worker(state)
end
length(state.available_workers) > 0 ->
select_load_balanced_worker(state)
true ->
{:error, :no_workers_available}
end
end
defp select_load_balanced_worker(state) do
case state.available_workers do
[worker_pid | _] -> {:ok, worker_pid}
[] -> {:error, :no_workers_available}
end
end
defp execute_on_worker(worker_pid, adapter_module, command, args, opts) do
GenServer.cast(__MODULE__, {:mark_worker_busy, worker_pid})
try do
result = adapter_module.execute(command, args, Keyword.put(opts, :worker_pid, worker_pid))
GenServer.cast(__MODULE__, {:mark_worker_available, worker_pid})
result
rescue
exception ->
GenServer.cast(__MODULE__, {:mark_worker_available, worker_pid})
{:error, {:execution_exception, Exception.message(exception)}}
end
end
defp start_initial_workers(state) do
worker_count = Application.get_env(:snakepit, :pool_size, 4)
workers = for i <- 1..worker_count do
case state.adapter_module.start_worker(state.adapter_state, i) do
{:ok, worker_pid} -> worker_pid
{:error, reason} ->
Logger.error("Failed to start worker #{i}: #{inspect(reason)}")
nil
end
end
|> Enum.filter(&(&1 != nil))
if length(workers) > 0 do
updated_state = %{state |
workers: workers,
available_workers: workers
}
{:ok, updated_state}
else
{:error, :failed_to_start_workers}
end
end
# Worker status management
def handle_cast({:mark_worker_busy, worker_pid}, state) do
updated_state = %{state |
available_workers: List.delete(state.available_workers, worker_pid),
busy_workers: MapSet.put(state.busy_workers, worker_pid)
}
{:noreply, updated_state}
end
def handle_cast({:mark_worker_available, worker_pid}, state) do
updated_state = %{state |
available_workers: [worker_pid | state.available_workers],
busy_workers: MapSet.delete(state.busy_workers, worker_pid)
}
{:noreply, updated_state}
end
defp initialize_stats do
%{
total_requests: 0,
successful_requests: 0,
failed_requests: 0,
session_affinity_hits: 0
}
end
defp update_stats(state, result, _execution_time) do
updated_stats = %{state.stats |
total_requests: state.stats.total_requests + 1,
successful_requests: state.stats.successful_requests + (if match?({:ok, _}, result), do: 1, else: 0),
failed_requests: state.stats.failed_requests + (if match?({:ok, _}, result), do: 0, else: 1)
}
%{state | stats: updated_stats}
end
end
```
**Afternoon: Create Generic Session Management**
```elixir
# lib/snakepit/session.ex (SIMPLIFIED FROM session_helpers.ex)
defmodule Snakepit.Session do
@moduledoc """
Generic session management for any external process adapter.
"""
def execute_in_session(session_id, command, args, opts \\ []) do
opts_with_session = Keyword.put(opts, :session_id, session_id)
Snakepit.Pool.execute(command, args, opts_with_session)
end
def execute_in_session_stream(session_id, command, args, callback_fn, opts \\ []) do
opts_with_session = Keyword.put(opts, :session_id, session_id)
Snakepit.Pool.execute_stream(command, args, callback_fn, opts_with_session)
end
def generate_session_id do
"session_" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))
end
end
```
### Day 10: Test Generic Infrastructure
**Morning: Create Mock Adapter for Testing**
```elixir
# test/support/mock_adapter.ex
defmodule Snakepit.MockAdapter do
@behaviour Snakepit.Adapter
def execute(command, args, opts) do
# Mock implementation for testing
{:ok, %{
command: command,
args: args,
opts: opts,
executed_at: DateTime.utc_now()
}}
end
def init(_config) do
{:ok, %{started_at: DateTime.utc_now()}}
end
def start_worker(adapter_state, worker_id) do
{:ok, spawn(fn ->
Process.sleep(100)  # Mock worker process
end)}
end
end
```
**Afternoon: Comprehensive Infrastructure Tests**
```elixir
# test/snakepit/pool/pool_test.exs
defmodule Snakepit.Pool.PoolTest do
use ExUnit.Case
setup do
# Start pool with mock adapter
{:ok, _pid} = Snakepit.Pool.start_link([
adapter_module: Snakepit.MockAdapter,
name: TestPool
])
%{pool: TestPool}
end
test "executes commands through adapter", %{pool: pool} do
assert {:ok, result} = Snakepit.Pool.execute("test_command", %{data: "test"})
assert result.command == "test_command"
assert result.args == %{data: "test"}
end
test "supports session affinity" do
session_id = "test_session"
# First call establishes affinity
{:ok, _} = Snakepit.execute_in_session(session_id, "command1", %{})
# Second call should use same worker (if available)
{:ok, _} = Snakepit.execute_in_session(session_id, "command2", %{})
end
end
```
## Phase 4: Transform DSPex Consumer (Week 4)
### Day 11: Update DSPex Dependencies
**Morning: Update mix.exs**
```elixir
# dspex/mix.exs
defmodule DSPex.MixProject do
use Mix.Project
def project do
[
app: :dspex,
version: "0.2.0",
elixir: "~> 1.14",
start_permanent: Mix.env() == :prod,
deps: deps()
]
end
def application do
[
extra_applications: [:logger]
]
end
defp deps do
[
# Core dependency on ML platform (which includes snakepit)
{:snakepit_grpc_bridge, path: "../snakepit_grpc_bridge"},
# Development and testing
{:ex_doc, "~> 0.29", only: :dev, runtime: false}
]
end
end
```
**Afternoon: Remove All Implementation from DSPex**
```bash
cd dspex
# Remove all implementation - keeping only orchestration
rm -rf lib/dspex/variables/
rm -rf lib/dspex/tools/
rm -rf priv/python/
# Keep only:
# lib/dspex.ex
# lib/dspex/bridge.ex (macro only)
# lib/dspex/api.ex (high-level convenience)
```
### Day 12: Create Pure DSPex Orchestration
**Morning: Update Main DSPex Module**
```elixir
# lib/dspex.ex (COMPLETE REWRITE)
defmodule DSPex do
@moduledoc """
DSPex - Elegant Elixir interface for machine learning workflows.
Pure orchestration layer built on SnakepitGRPCBridge platform.
"""
alias SnakepitGRPCBridge.API
def predict(signature, inputs, opts \\ []) do
with_auto_session(fn session_id ->
API.DSPy.enhanced_predict(session_id, signature, inputs, opts)
end)
end
def chain_of_thought(signature, inputs, opts \\ []) do
with_auto_session(fn session_id ->
API.DSPy.enhanced_chain_of_thought(session_id, signature, inputs, opts)
end)
end
def set_variable(name, value) do
with_global_session(fn session_id ->
API.Variables.set(session_id, name, value)
end)
end
def get_variable(name, default \\ nil) do
with_global_session(fn session_id ->
API.Variables.get(session_id, name, default)
end)
end
def register_tool(name, function, opts \\ []) do
with_global_session(fn session_id ->
API.Tools.register_elixir_function(session_id, name, function, opts)
end)
end
def call_tool(name, parameters) do
with_global_session(fn session_id ->
API.Tools.call(session_id, name, parameters)
end)
end
def start_session(opts \\ []) do
session_id = DSPex.Sessions.generate_session_id()
case API.Variables.create(session_id, "_session_metadata", :map, %{
created_at: DateTime.utc_now(),
options: opts
}) do
{:ok, _} -> {:ok, session_id}
{:error, reason} -> {:error, reason}
end
end
def stop_session(session_id) do
# Clean up session through platform
:ok
end
def predict_with_session(session_id, signature, inputs, opts \\ []) do
API.DSPy.enhanced_predict(session_id, signature, inputs, opts)
end
def set_session_variable(session_id, name, value) do
API.Variables.set(session_id, name, value)
end
def create_workflow(steps, opts \\ []) do
with_auto_session(fn session_id ->
API.DSPy.create_workflow(session_id, steps, opts)
end)
end
def execute_workflow(workflow, inputs, opts \\ []) do
API.DSPy.execute_workflow(workflow.session_id, workflow.id, inputs, opts)
end
# Private helper functions
defp with_auto_session(fun) when is_function(fun, 1) do
session_id = DSPex.Sessions.generate_temp_session_id()
try do
fun.(session_id)
after
# Clean up temporary session
:ok
end
end
defp with_global_session(fun) when is_function(fun, 1) do
session_id = DSPex.Sessions.get_or_create_global_session()
fun.(session_id)
end
end
```
**Afternoon: Update defdsyp Macro**
```elixir
# lib/dspex/bridge.ex (MACRO ONLY)
defmodule DSPex.Bridge do
@moduledoc """
Code generation macros for creating DSPy wrapper modules.
Pure macro-based code generation with no implementation.
"""
defmacro defdsyp(module_name, class_path, config \\ %{}) do
quote bind_quoted: [
module_name: module_name,
class_path: class_path,
config: config
] do
@class_path class_path
@config config
@signature config[:signature] || "input -> output"
@description config[:description] || "DSPy wrapper for #{class_path}"
def create(opts \\ []) do
session_id = opts[:session_id] || DSPex.Sessions.generate_temp_session_id()
# Create through platform API
case SnakepitGRPCBridge.API.DSPy.call(
session_id,
@class_path,
"__init__",
%{signature: @signature},
opts
) do
{:ok, %{"instance_id" => instance_id}} ->
{:ok, {session_id, instance_id}}
{:error, reason} ->
{:error, reason}
end
end
def execute({session_id, instance_id}, inputs, opts \\ []) do
# Use platform enhanced execution
SnakepitGRPCBridge.API.DSPy.enhanced_predict(
session_id,
@signature,
inputs,
Keyword.merge(opts, [instance_id: instance_id])
)
end
def call(inputs, opts \\ []) do
with {:ok, instance} <- create(opts),
{:ok, result} <- execute(instance, inputs, opts) do
{:ok, result}
end
end
if @config[:enhanced_mode] do
def chain_of_thought({session_id, _instance_id}, inputs, opts \\ []) do
SnakepitGRPCBridge.API.DSPy.enhanced_chain_of_thought(
session_id,
@signature,
inputs,
opts
)
end
end
# Generate additional methods based on config
for {method_name, elixir_name} <- (@config[:methods] || %{}) do
def unquote(String.to_atom(elixir_name))({session_id, instance_id}, args \\ %{}) do
SnakepitGRPCBridge.API.DSPy.call(
session_id,
"stored.#{instance_id}",
unquote(method_name),
args
)
end
end
def __dspex_info__ do
%{
class_path: @class_path,
signature: @signature,
description: @description,
config: @config,
module: __MODULE__
}
end
end
end
@doc false
defmacro __using__(_opts) do
quote do
import DSPex.Bridge, only: [defdsyp: 2, defdsyp: 3]
end
end
end
```
### Day 13: Create High-Level APIs
**Morning: Create Convenience API**
```elixir
# lib/dspex/api.ex (NEW HIGH-LEVEL CONVENIENCE)
defmodule DSPex.API do
@moduledoc """
High-level convenience functions for common ML patterns.
"""
def ask(question, opts \\ []) do
signature = if opts[:reasoning], do: "question -> reasoning, answer", else: "question -> answer"
case DSPex.predict(signature, %{question: question}, opts) do
{:ok, result} when is_map(result) ->
answer = result["answer"] || result[:answer]
{:ok, answer}
{:error, reason} ->
{:error, reason}
end
end
def classify(text, categories, opts \\ []) do
categories_str = Enum.join(categories, ", ")
signature = "text, categories -> category"
case DSPex.predict(signature, %{
text: text,
categories: categories_str
}, opts) do
{:ok, result} when is_map(result) ->
category = result["category"] || result[:category]
{:ok, category}
{:error, reason} ->
{:error, reason}
end
end
def summarize(text, opts \\ []) do
max_length = opts[:max_length] || 150
signature = "text, max_length -> summary"
case DSPex.predict(signature, %{
text: text,
max_length: max_length
}, opts) do
{:ok, result} when is_map(result) ->
summary = result["summary"] || result[:summary]
{:ok, summary}
{:error, reason} ->
{:error, reason}
end
end
def extract_entities(text, opts \\ []) do
entity_types = opts[:types] || ["people", "organizations", "locations"]
signature = "text, entity_types -> entities"
case DSPex.predict(signature, %{
text: text,
entity_types: Enum.join(entity_types, ", ")
}, opts) do
{:ok, result} when is_map(result) ->
entities = result["entities"] || result[:entities]
{:ok, entities}
{:error, reason} ->
{:error, reason}
end
end
def generate(prompt, opts \\ []) do
style = opts[:style] || "natural"
length = opts[:length] || 150
signature = "prompt, style, length -> generated_text"
case DSPex.predict(signature, %{
prompt: prompt,
style: style,
length: length
}, opts) do
{:ok, result} when is_map(result) ->
text = result["generated_text"] || result[:generated_text]
{:ok, text}
{:error, reason} ->
{:error, reason}
end
end
def answer_with_context(question, context, opts \\ []) do
signature = "context, question -> answer"
case DSPex.predict(signature, %{
context: context,
question: question
}, opts) do
{:ok, result} when is_map(result) ->
answer = result["answer"] || result[:answer]
{:ok, answer}
{:error, reason} ->
{:error, reason}
end
end
end
```
**Afternoon: Session Utilities**
```elixir
# lib/dspex/sessions.ex (NEW)
defmodule DSPex.Sessions do
@moduledoc """
Session management utilities for DSPex.
"""
@global_session_key :dspex_global_session
@temp_session_prefix "temp_session_"
def generate_session_id do
"session_" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))
end
def generate_temp_session_id do
@temp_session_prefix <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
end
def get_or_create_global_session do
case Process.get(@global_session_key) do
nil ->
session_id = generate_session_id()
Process.put(@global_session_key, session_id)
session_id
session_id ->
session_id
end
end
def clear_global_session do
Process.delete(@global_session_key)
:ok
end
def temp_session?(session_id) do
String.starts_with?(session_id, @temp_session_prefix)
end
end
```
### Day 14: Integration Testing
**Morning: Test Full Stack Integration**
```bash
# Start bridge platform
cd snakepit_grpc_bridge
mix deps.get
mix compile
# Configure snakepit to use bridge
# config/config.exs
config :snakepit,
adapter_module: SnakepitGRPCBridge.Adapter
# Test DSPex with full stack
cd ../dspex
mix deps.get
mix compile
mix test
```
**Afternoon: End-to-End Testing**
```elixir
# test/dspex_integration_test.exs
defmodule DSPexIntegrationTest do
use ExUnit.Case
test "full stack prediction" do
# This should work through: DSPex -> SnakepitGRPCBridge -> Snakepit
assert {:ok, result} = DSPex.predict("question -> answer", %{
question: "What is Elixir?"
})
assert is_map(result)
end
test "variable management" do
# Test variables work through platform
assert :ok = DSPex.set_variable("temperature", 0.7)
assert {:ok, 0.7} = DSPex.get_variable("temperature")
end
test "tool registration and execution" do
# Test tools work through platform
assert :ok = DSPex.register_tool("test_tool", fn params ->
Map.get(params, "input", "default")
end)
assert {:ok, "test_value"} = DSPex.call_tool("test_tool", %{"input" => "test_value"})
end
test "defdsyp macro generates working modules" do
defmodule TestPredictor do
use DSPex.Bridge
defdsyp __MODULE__, "dspy.Predict", %{
signature: "test_input -> test_output"
}
end
assert {:ok, instance} = TestPredictor.create()
assert {:ok, _result} = TestPredictor.execute(instance, %{test_input: "test"})
end
end
```
## Final Configuration and Testing (Days 15-21)
### Day 15: Configure Integration
**Configure SnakepitGRPCBridge to use Snakepit:**
```elixir
# snakepit_grpc_bridge/config/config.exs
config :snakepit,
adapter_module: SnakepitGRPCBridge.Adapter,
pool_size: 4
config :snakepit_grpc_bridge,
python_executable: "python3",
grpc_port: 0,
telemetry_enabled: true
```
### Days 16-20: Comprehensive Testing
- Test each layer independently
- Test full integration
- Performance testing
- Error handling validation
- Documentation updates
### Day 21: Final Validation
**Architecture Validation:**
- ✅ Snakepit contains zero ML code
- ✅ All Python code in SnakepitGRPCBridge
- ✅ DSPex is pure orchestration
- ✅ Clean APIs work correctly
- ✅ Full stack integration functional
<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[{"content": "Create detailed implementation plan for building three-layer architecture in place (no
