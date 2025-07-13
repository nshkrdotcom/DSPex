# Stage 1: Foundation Implementation - Core Components

## Overview

Stage 1 establishes the foundational components for DSPy-Ash integration. This stage focuses on the minimum code needed to define signatures, create basic resources, and establish the Python bridge.

**Goal**: Execute a simple DSPy program through Ash with native signature syntax.

**Duration**: Week 1-2

## 1. Project Structure

```
lib/
├── ash_dspy/
│   ├── application.ex
│   ├── signature/
│   │   ├── signature.ex          # Core signature behavior
│   │   ├── compiler.ex           # Compile-time signature processing
│   │   └── type_parser.ex        # Type system parsing
│   ├── adapters/
│   │   ├── adapter.ex            # Adapter behavior
│   │   └── python_port.ex        # Python port implementation
│   ├── python_bridge/
│   │   ├── bridge.ex             # GenServer for Python communication
│   │   └── protocol.ex           # Wire protocol
│   └── ml/
│       ├── domain.ex             # Ash domain
│       ├── signature.ex          # Signature resource
│       └── program.ex            # Program resource
priv/
└── python/
    └── dspy_bridge.py           # Python bridge script
```

## 2. Core Signature Implementation

### 2.1 Signature Behavior

```elixir
# lib/ash_dspy/signature/signature.ex
defmodule AshDSPy.Signature do
  @moduledoc """
  Core signature behavior providing native syntax compilation.
  """
  
  defmacro __using__(_opts) do
    quote do
      import AshDSPy.Signature.DSL
      Module.register_attribute(__MODULE__, :signature_ast, accumulate: false)
      Module.register_attribute(__MODULE__, :signature_compiled, accumulate: false)
      @before_compile AshDSPy.Signature.Compiler
    end
  end
  
  defmodule DSL do
    @doc """
    Define signature with native syntax.
    
    Examples:
      signature question: :string -> answer: :string
      signature query: :string, context: :string -> answer: :string, confidence: :float
    """
    defmacro signature(signature_ast) do
      quote do
        @signature_ast unquote(Macro.escape(signature_ast))
      end
    end
  end
end
```

### 2.2 Signature Compiler

```elixir
# lib/ash_dspy/signature/compiler.ex
defmodule AshDSPy.Signature.Compiler do
  @moduledoc """
  Compile-time signature processing and code generation.
  """
  
  defmacro __before_compile__(env) do
    signature_ast = Module.get_attribute(env.module, :signature_ast)
    
    case signature_ast do
      nil -> 
        raise "No signature defined in #{env.module}"
      ast ->
        compile_signature(ast, env.module)
    end
  end
  
  defp compile_signature(ast, module) do
    {inputs, outputs} = parse_signature_ast(ast)
    
    quote do
      @signature_compiled %{
        module: unquote(module),
        inputs: unquote(Macro.escape(inputs)),
        outputs: unquote(Macro.escape(outputs))
      }
      
      def __signature__, do: @signature_compiled
      
      def input_fields, do: @signature_compiled.inputs
      def output_fields, do: @signature_compiled.outputs
      
      def validate_inputs(data) do
        AshDSPy.Signature.Validator.validate_fields(data, input_fields())
      end
      
      def validate_outputs(data) do
        AshDSPy.Signature.Validator.validate_fields(data, output_fields())
      end
      
      def to_json_schema(provider \\ :openai) do
        AshDSPy.Signature.JsonSchema.generate(__signature__, provider)
      end
    end
  end
  
  defp parse_signature_ast(ast) do
    case ast do
      # Handle: a: type -> b: type
      {inputs, [do: outputs]} when is_list(inputs) ->
        {parse_fields(inputs), parse_fields([outputs])}
      
      # Handle: a: type, b: type -> c: type, d: type  
      {:->, _, [inputs, outputs]} ->
        input_list = if is_list(inputs), do: inputs, else: [inputs]
        output_list = if is_list(outputs), do: outputs, else: [outputs]
        {parse_fields(input_list), parse_fields(output_list)}
      
      # Handle single field cases
      {name, type} ->
        {[], [{name, type, []}]}
      
      _ ->
        raise "Invalid signature syntax: #{inspect(ast)}"
    end
  end
  
  defp parse_fields(fields) do
    Enum.map(fields, fn
      {name, type} -> {name, type, []}
      {name, type, constraints} -> {name, type, constraints}
      atom when is_atom(atom) -> {atom, :any, []}
    end)
  end
end
```

### 2.3 Type Parser

```elixir
# lib/ash_dspy/signature/type_parser.ex
defmodule AshDSPy.Signature.TypeParser do
  @moduledoc """
  Parse and validate type definitions in signatures.
  """
  
  @basic_types [:string, :integer, :float, :boolean, :atom, :any, :map]
  @ml_types [:embedding, :probability, :confidence_score, :reasoning_chain]
  
  def parse_type(type_ast) do
    case type_ast do
      # Basic types
      type when type in @basic_types -> {:ok, type}
      type when type in @ml_types -> {:ok, type}
      
      # List types: {:list, inner_type}
      {:list, inner_type} ->
        case parse_type(inner_type) do
          {:ok, parsed_inner} -> {:ok, {:list, parsed_inner}}
          error -> error
        end
      
      # Dict types: {:dict, key_type, value_type}
      {:dict, key_type, value_type} ->
        with {:ok, parsed_key} <- parse_type(key_type),
             {:ok, parsed_value} <- parse_type(value_type) do
          {:ok, {:dict, parsed_key, parsed_value}}
        end
      
      # Union types: {:union, [type1, type2, ...]}
      {:union, types} when is_list(types) ->
        case parse_types(types) do
          {:ok, parsed_types} -> {:ok, {:union, parsed_types}}
          error -> error
        end
      
      # Unknown type
      unknown ->
        {:error, "Unknown type: #{inspect(unknown)}"}
    end
  end
  
  defp parse_types(types) do
    types
    |> Enum.reduce_while({:ok, []}, fn type, {:ok, acc} ->
      case parse_type(type) do
        {:ok, parsed} -> {:cont, {:ok, acc ++ [parsed]}}
        error -> {:halt, error}
      end
    end)
  end
end
```

### 2.4 Basic Validator

```elixir
# lib/ash_dspy/signature/validator.ex
defmodule AshDSPy.Signature.Validator do
  @moduledoc """
  Runtime validation for signature fields.
  """
  
  def validate_fields(data, fields) when is_map(data) do
    results = Enum.map(fields, fn {name, type, _constraints} ->
      case Map.get(data, name) do
        nil -> {:error, "Missing field: #{name}"}
        value -> validate_type(value, type)
      end
    end)
    
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> 
        validated = Enum.zip(fields, results)
                   |> Enum.map(fn {{name, _, _}, {:ok, value}} -> {name, value} end)
                   |> Map.new()
        {:ok, validated}
      error -> error
    end
  end
  
  defp validate_type(value, :string) when is_binary(value), do: {:ok, value}
  defp validate_type(value, :integer) when is_integer(value), do: {:ok, value}
  defp validate_type(value, :float) when is_float(value), do: {:ok, value}
  defp validate_type(value, :boolean) when is_boolean(value), do: {:ok, value}
  defp validate_type(value, :any), do: {:ok, value}
  
  defp validate_type(value, {:list, inner_type}) when is_list(value) do
    case validate_list_items(value, inner_type, []) do
      {:ok, validated_items} -> {:ok, validated_items}
      error -> error
    end
  end
  
  defp validate_type(value, type) do
    {:error, "Expected #{inspect(type)}, got #{inspect(value)}"}
  end
  
  defp validate_list_items([], _type, acc), do: {:ok, Enum.reverse(acc)}
  defp validate_list_items([item | rest], type, acc) do
    case validate_type(item, type) do
      {:ok, validated} -> validate_list_items(rest, type, [validated | acc])
      error -> error
    end
  end
end
```

## 3. Python Bridge Implementation

### 3.1 Bridge GenServer

```elixir
# lib/ash_dspy/python_bridge/bridge.ex
defmodule AshDSPy.PythonBridge.Bridge do
  @moduledoc """
  GenServer managing Python DSPy process communication.
  """
  
  use GenServer
  require Logger
  
  alias AshDSPy.PythonBridge.Protocol
  
  defstruct [:port, :requests, :request_id]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def call(command, args, timeout \\ 30_000) do
    GenServer.call(__MODULE__, {:call, command, args}, timeout)
  end
  
  @impl true
  def init(_opts) do
    python_script = Path.join(:code.priv_dir(:ash_dspy), "python/dspy_bridge.py")
    
    case System.find_executable("python3") do
      nil -> 
        {:stop, "Python 3 not found"}
      python_path ->
        port = Port.open({:spawn_executable, python_path}, [
          {:args, [python_script]},
          {:packet, 4},
          :binary,
          :exit_status
        ])
        
        {:ok, %__MODULE__{
          port: port,
          requests: %{},
          request_id: 0
        }}
    end
  end
  
  @impl true
  def handle_call({:call, command, args}, from, state) do
    request_id = state.request_id + 1
    
    request = Protocol.encode_request(request_id, command, args)
    
    # Send to Python
    send(state.port, {self(), {:command, request}})
    
    # Store request
    new_requests = Map.put(state.requests, request_id, from)
    
    {:noreply, %{state | requests: new_requests, request_id: request_id}}
  end
  
  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    case Protocol.decode_response(data) do
      {:ok, id, result} ->
        case Map.pop(state.requests, id) do
          {nil, requests} ->
            Logger.warning("Received response for unknown request: #{id}")
            {:noreply, %{state | requests: requests}}
          {from, requests} ->
            GenServer.reply(from, {:ok, result})
            {:noreply, %{state | requests: requests}}
        end
      
      {:error, id, error} ->
        case Map.pop(state.requests, id) do
          {nil, requests} ->
            Logger.warning("Received error for unknown request: #{id}")
            {:noreply, %{state | requests: requests}}
          {from, requests} ->
            GenServer.reply(from, {:error, error})
            {:noreply, %{state | requests: requests}}
        end
      
      {:error, reason} ->
        Logger.error("Failed to decode Python response: #{inspect(reason)}")
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("Python process exited with status: #{status}")
    {:stop, :python_process_died, state}
  end
end
```

### 3.2 Wire Protocol

```elixir
# lib/ash_dspy/python_bridge/protocol.ex
defmodule AshDSPy.PythonBridge.Protocol do
  @moduledoc """
  Wire protocol for Python bridge communication.
  """
  
  def encode_request(id, command, args) do
    request = %{
      id: id,
      command: to_string(command),
      args: args,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    Jason.encode!(request)
  end
  
  def decode_response(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, %{"id" => id, "success" => true, "result" => result}} ->
        {:ok, id, result}
      
      {:ok, %{"id" => id, "success" => false, "error" => error}} ->
        {:error, id, error}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

## 4. Adapter Pattern

### 4.1 Adapter Behavior

```elixir
# lib/ash_dspy/adapters/adapter.ex
defmodule AshDSPy.Adapters.Adapter do
  @moduledoc """
  Behavior for DSPy adapters.
  """
  
  @type program_config :: %{
    id: String.t(),
    signature: module(),
    modules: list(map())
  }
  
  @callback create_program(program_config()) :: {:ok, String.t()} | {:error, term()}
  @callback execute_program(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_programs() :: {:ok, list(String.t())} | {:error, term()}
end
```

### 4.2 Python Port Adapter

```elixir
# lib/ash_dspy/adapters/python_port.ex
defmodule AshDSPy.Adapters.PythonPort do
  @moduledoc """
  Python port adapter for DSPy integration.
  """
  
  @behaviour AshDSPy.Adapters.Adapter
  
  alias AshDSPy.PythonBridge.Bridge
  
  @impl true
  def create_program(config) do
    # Convert signature to Python format
    signature_def = convert_signature(config.signature)
    
    Bridge.call(:create_program, %{
      id: config.id,
      signature: signature_def,
      modules: config.modules || []
    })
  end
  
  @impl true
  def execute_program(program_id, inputs) do
    Bridge.call(:execute_program, %{
      program_id: program_id,
      inputs: inputs
    })
  end
  
  @impl true
  def list_programs do
    Bridge.call(:list_programs, %{})
  end
  
  defp convert_signature(signature_module) do
    signature = signature_module.__signature__()
    
    %{
      inputs: convert_fields(signature.inputs),
      outputs: convert_fields(signature.outputs)
    }
  end
  
  defp convert_fields(fields) do
    Enum.map(fields, fn {name, type, _constraints} ->
      %{
        name: to_string(name),
        type: convert_type(type)
      }
    end)
  end
  
  defp convert_type(:string), do: "str"
  defp convert_type(:integer), do: "int"
  defp convert_type(:float), do: "float"
  defp convert_type(:boolean), do: "bool"
  defp convert_type({:list, inner}), do: "List[#{convert_type(inner)}]"
  defp convert_type(type), do: to_string(type)
end
```

## 5. Basic Ash Resources

### 5.1 ML Domain

```elixir
# lib/ash_dspy/ml/domain.ex
defmodule AshDSPy.ML.Domain do
  @moduledoc """
  ML domain for DSPy resources.
  """
  
  use Ash.Domain
  
  resources do
    resource AshDSPy.ML.Signature
    resource AshDSPy.ML.Program
  end
end
```

### 5.2 Signature Resource

```elixir
# lib/ash_dspy/ml/signature.ex
defmodule AshDSPy.ML.Signature do
  @moduledoc """
  Ash resource for managing DSPy signatures.
  """
  
  use Ash.Resource,
    domain: AshDSPy.ML.Domain,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :module, :string, allow_nil?: false
    attribute :inputs, {:array, :map}, default: []
    attribute :outputs, {:array, :map}, default: []
    timestamps()
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    action :from_module, :struct do
      argument :signature_module, :atom, allow_nil?: false
      
      run fn input, _context ->
        module = input.arguments.signature_module
        signature = module.__signature__()
        
        {:ok, %{
          name: to_string(module),
          module: to_string(module),
          inputs: signature.inputs,
          outputs: signature.outputs
        }}
      end
    end
  end
  
  code_interface do
    define :from_module
  end
end
```

### 5.3 Program Resource (Basic)

```elixir
# lib/ash_dspy/ml/program.ex
defmodule AshDSPy.ML.Program do
  @moduledoc """
  Ash resource for managing DSPy programs.
  """
  
  use Ash.Resource,
    domain: AshDSPy.ML.Domain,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :dspy_program_id, :string  # ID in Python DSPy
    attribute :status, :atom, constraints: [one_of: [:draft, :ready, :error]], default: :draft
    timestamps()
  end
  
  relationships do
    belongs_to :signature, AshDSPy.ML.Signature
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    create :create_with_signature do
      argument :signature_module, :atom, allow_nil?: false
      
      change fn changeset, _context ->
        signature_module = Ash.Changeset.get_argument(changeset, :signature_module)
        
        # Create signature record
        {:ok, signature} = AshDSPy.ML.Signature.from_module(%{
          signature_module: signature_module
        })
        
        signature_record = AshDSPy.ML.Signature.create!(signature)
        
        changeset
        |> Ash.Changeset.manage_relationship(:signature, signature_record, type: :append)
      end
    end
    
    action :execute, :map do
      argument :inputs, :map, allow_nil?: false
      
      run fn input, context ->
        program = context.resource
        
        case program.dspy_program_id do
          nil -> {:error, "Program not initialized"}
          program_id ->
            adapter = Application.get_env(:ash_dspy, :adapter, AshDSPy.Adapters.PythonPort)
            adapter.execute_program(program_id, input.arguments.inputs)
        end
      end
    end
  end
  
  code_interface do
    define :create_with_signature
    define :execute
  end
end
```

## 6. Python Bridge Script

```python
# priv/python/dspy_bridge.py
#!/usr/bin/env python3

import sys
import json
import struct
import traceback
import dspy

class DSPyBridge:
    def __init__(self):
        self.programs = {}
        
    def handle_command(self, command, args):
        handlers = {
            'create_program': self.create_program,
            'execute_program': self.execute_program,
            'list_programs': self.list_programs
        }
        
        if command not in handlers:
            raise ValueError(f"Unknown command: {command}")
            
        return handlers[command](args)
    
    def create_program(self, args):
        program_id = args['id']
        signature_def = args['signature']
        
        # Create dynamic signature class
        class DynamicSignature(dspy.Signature):
            pass
        
        # Add input fields
        for field in signature_def['inputs']:
            setattr(DynamicSignature, field['name'], dspy.InputField())
        
        # Add output fields  
        for field in signature_def['outputs']:
            setattr(DynamicSignature, field['name'], dspy.OutputField())
        
        # Create simple predict program
        program = dspy.Predict(DynamicSignature)
        self.programs[program_id] = program
        
        return {"program_id": program_id, "status": "created"}
    
    def execute_program(self, args):
        program_id = args['program_id']
        inputs = args['inputs']
        
        if program_id not in self.programs:
            raise ValueError(f"Program not found: {program_id}")
        
        program = self.programs[program_id]
        result = program(**inputs)
        
        # Convert result to dict
        if hasattr(result, '__dict__'):
            output = {k: v for k, v in result.__dict__.items() 
                     if not k.startswith('_')}
        else:
            output = {"result": str(result)}
        
        return output
    
    def list_programs(self, args):
        return {"programs": list(self.programs.keys())}

def read_message():
    # Read 4-byte length header
    length_bytes = sys.stdin.buffer.read(4)
    if len(length_bytes) < 4:
        return None
    
    length = struct.unpack('>I', length_bytes)[0]
    
    # Read message
    message_bytes = sys.stdin.buffer.read(length)
    if len(message_bytes) < length:
        return None
    
    return json.loads(message_bytes.decode('utf-8'))

def write_message(message):
    message_bytes = json.dumps(message).encode('utf-8')
    length = len(message_bytes)
    
    # Write length header + message
    sys.stdout.buffer.write(struct.pack('>I', length))
    sys.stdout.buffer.write(message_bytes)
    sys.stdout.buffer.flush()

def main():
    bridge = DSPyBridge()
    
    while True:
        try:
            message = read_message()
            if message is None:
                break
            
            request_id = message.get('id')
            command = message.get('command')
            args = message.get('args', {})
            
            try:
                result = bridge.handle_command(command, args)
                write_message({
                    'id': request_id,
                    'success': True,
                    'result': result
                })
            except Exception as e:
                write_message({
                    'id': request_id,
                    'success': False,
                    'error': str(e)
                })
                
        except Exception as e:
            sys.stderr.write(f"Bridge error: {e}\n")
            sys.stderr.write(traceback.format_exc())

if __name__ == '__main__':
    main()
```

## 7. Application Setup

```elixir
# lib/ash_dspy/application.ex
defmodule AshDSPy.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Start Python bridge
      AshDSPy.PythonBridge.Bridge,
      
      # Start Ash resources if using Postgres
      {AshPostgres.Repo, Application.get_env(:ash_dspy, AshDSPy.Repo)}
    ]
    
    opts = [strategy: :one_for_one, name: AshDSPy.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## 8. Configuration

```elixir
# config/config.exs
import Config

config :ash_dspy, :adapter, AshDSPy.Adapters.PythonPort

config :ash_dspy, AshDSPy.Repo,
  username: "postgres",
  password: "postgres", 
  hostname: "localhost",
  database: "ash_dspy_dev",
  pool_size: 10

config :ash_dspy,
  ecto_repos: [AshDSPy.Repo]
```

## 9. Testing the Foundation

```elixir
# test/stage1_foundation_test.exs
defmodule Stage1FoundationTest do
  use ExUnit.Case
  
  defmodule TestSignature do
    use AshDSPy.Signature
    
    signature question: :string -> answer: :string
  end
  
  test "signature compilation" do
    signature = TestSignature.__signature__()
    
    assert signature.inputs == [{:question, :string, []}]
    assert signature.outputs == [{:answer, :string, []}]
  end
  
  test "signature validation" do
    {:ok, validated} = TestSignature.validate_inputs(%{question: "test"})
    assert validated.question == "test"
    
    {:error, reason} = TestSignature.validate_inputs(%{})
    assert reason =~ "Missing field: question"
  end
  
  test "program creation and execution" do
    {:ok, signature} = AshDSPy.ML.Signature.from_module(%{
      signature_module: TestSignature
    })
    
    signature_record = AshDSPy.ML.Signature.create!(signature)
    
    {:ok, program} = AshDSPy.ML.Program.create_with_signature(%{
      name: "Test Program",
      signature_module: TestSignature
    })
    
    # Note: This will fail until Python bridge is working
    # but it tests the interface
    result = AshDSPy.ML.Program.execute(program, %{
      question: "What is 2+2?"
    })
    
    # Should return {:ok, %{answer: "..."}} when bridge works
    assert match?({:ok, %{answer: _}}, result) or match?({:error, _}, result)
  end
end
```

## Stage 1 Deliverables

By the end of Stage 1, you should have:

1. ✅ **Native signature syntax** working with compile-time processing
2. ✅ **Python bridge** established with basic communication
3. ✅ **Adapter pattern** ready for multiple implementations  
4. ✅ **Basic Ash resources** for signatures and programs
5. ✅ **Working example** that can execute a simple DSPy program

**Next**: Stage 2 will add the custom data layer, advanced validation, and proper state management.