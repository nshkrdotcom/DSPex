# Stage 1 Prompt 1: Core Signature System Implementation

## OBJECTIVE

Implement the foundational signature system for DSPy-Ash integration that enables native signature syntax `signature question: :string -> answer: :string` with compile-time processing, type validation, and JSON schema generation. This system forms the core abstraction for DSPy program definitions in Elixir.

## COMPLETE IMPLEMENTATION CONTEXT

### SIGNATURE INNOVATION ARCHITECTURE REFERENCE

From the Signature Innovation Documents (1100-1102 series), the vision is to eliminate traditional DSPy Python signature syntax in favor of native Elixir syntax:

**Traditional DSPy Python Signature:**
```python
class QA(dspy.Signature):
    """Answer questions with short factoid answers."""
    question = dspy.InputField()
    answer = dspy.OutputField(desc="often between 1 and 5 words")
```

**Native Elixir Signature Syntax (Target):**
```elixir
defmodule QA do
  use DSPex.Signature
  
  signature question: :string -> answer: :string
end
```

### COMPLETE ASH DSPY INTEGRATION ARCHITECTURE

From DSPEX_INTEGRATION_ARCHITECTURE.md:

**Core Integration Philosophy:**
- Ash framework serves as domain modeling infrastructure for ML operations
- DSPy operations mapped to Ash resources with proper lifecycle management
- Native signature syntax that compiles to both Ash resources and DSPy programs
- Adapter pattern enabling Python port initially, native Elixir implementation later
- Production-ready patterns: GraphQL APIs, background jobs, monitoring

**Technical Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                   Ash-DSPy Integration                     │
├─────────────────────────────────────────────────────────────┤
│  Native Signatures → Ash Resources → DSPy Programs         │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Signature DSL   │  │ Ash Resources   │  │ Adapters     ││
│  │ - Native syntax │  │ - Domain model  │  │ - Python     ││
│  │ - Type parsing  │  │ - Actions       │  │ - Future     ││
│  │ - Validation    │  │ - Relationships │  │   Native     ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### ASH RESOURCE PATTERNS FROM DOCUMENTATION

From ashDocs/documentation/tutorials/get-started.md:

**Basic Resource Structure:**
```elixir
defmodule Helpdesk.Support.Ticket do
  use Ash.Resource, domain: Helpdesk.Support

  actions do
    defaults [:read]
    create :open do
      accept [:subject]
    end
    update :close do
      accept []
      validate attribute_does_not_equal(:status, :closed) do
        message "Ticket is already closed"
      end
      change set_attribute(:status, :closed)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :subject, :string do
      allow_nil? false
      public? true
    end
    attribute :status, :atom do
      constraints [one_of: [:open, :closed]]
      default :open
      allow_nil? false
    end
  end
end
```

From ashDocs/documentation/topics/actions/manual-actions.md:

**Manual Action Patterns:**
```elixir
create :special_create do
  manual MyApp.DoCreate
end

defmodule MyApp.DoCreate do
  use Ash.Resource.ManualCreate

  def create(changeset, _, _) do
    record = create_the_record(changeset)
    {:ok, record}
  end
end
```

**Manual Read Patterns:**
```elixir
read :action_name do
  manual MyApp.ManualRead
end

defmodule MyApp.ManualRead do
  use Ash.Resource.ManualRead

  def read(ash_query, ecto_query, _opts, _context) do
    {:ok, query_results} | {:error, error}
  end
end
```

### EXDANTIC VALIDATION INTEGRATION

From ../../exdantic/README.md analysis:

**ExDantic Core Features:**
- Pydantic-like validation for Elixir
- Runtime schema creation and validation
- TypeAdapter pattern for custom types
- JSON schema generation
- Field validation with constraints

**Integration Points for Signature System:**
- Use ExDantic for field-level validation
- Leverage TypeAdapter for ML-specific types
- JSON schema generation for OpenAI/provider compatibility
- Runtime validation of signature inputs/outputs

### STAGE 1 FOUNDATION IMPLEMENTATION DETAILS

From STAGE_1_FOUNDATION_IMPLEMENTATION.md:

**Project Structure:**
```
lib/
├── dspex/
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
```

**Core Implementation Requirements:**
1. Signature Behavior with DSL macro for native syntax
2. Compile-time AST processing and code generation
3. Type parser supporting basic and ML-specific types
4. Runtime validation for inputs/outputs
5. JSON schema generation for provider compatibility
6. Integration with Ash resource lifecycle

### COMPLETE TYPE SYSTEM SPECIFICATION

**Basic Types:**
- `:string` - Text data, questions, responses
- `:integer` - Numeric values, counts, indices
- `:float` - Decimal numbers, probabilities, scores
- `:boolean` - Binary flags, yes/no responses
- `:atom` - Enumerated values, status indicators
- `:any` - Unconstrained values, debugging
- `:map` - Structured data, complex inputs

**ML-Specific Types:**
- `:embedding` - Vector embeddings for semantic search
- `:probability` - Values constrained 0.0-1.0
- `:confidence_score` - Model confidence metrics
- `:reasoning_chain` - Step-by-step reasoning traces

**Composite Types:**
- `{:list, inner_type}` - Arrays of values
- `{:dict, key_type, value_type}` - Key-value mappings
- `{:union, [type1, type2, ...]}` - One of multiple types

### SIGNATURE DSL MACRO SYSTEM

**DSL Requirements:**
```elixir
defmodule DSPex.Signature do
  defmacro __using__(_opts) do
    quote do
      import DSPex.Signature.DSL
      Module.register_attribute(__MODULE__, :signature_ast, accumulate: false)
      Module.register_attribute(__MODULE__, :signature_compiled, accumulate: false)
      @before_compile DSPex.Signature.Compiler
    end
  end
  
  defmodule DSL do
    defmacro signature(signature_ast) do
      quote do
        @signature_ast unquote(Macro.escape(signature_ast))
      end
    end
  end
end
```

**AST Parsing Patterns:**
```elixir
# Handle: a: type -> b: type
{inputs, [do: outputs]} when is_list(inputs) ->
  {parse_fields(inputs), parse_fields([outputs])}

# Handle: a: type, b: type -> c: type, d: type  
{:->, _, [inputs, outputs]} ->
  input_list = if is_list(inputs), do: inputs, else: [inputs]
  output_list = if is_list(outputs), do: outputs, else: [outputs]
  {parse_fields(input_list), parse_fields(output_list)}
```

### COMPILE-TIME CODE GENERATION

**Generated Functions:**
```elixir
def __signature__, do: @signature_compiled

def input_fields, do: @signature_compiled.inputs
def output_fields, do: @signature_compiled.outputs

def validate_inputs(data) do
  DSPex.Signature.Validator.validate_fields(data, input_fields())
end

def validate_outputs(data) do
  DSPex.Signature.Validator.validate_fields(data, output_fields())
end

def to_json_schema(provider \\ :openai) do
  DSPex.Signature.JsonSchema.generate(__signature__, provider)
end
```

### VALIDATION SYSTEM ARCHITECTURE

**Field Validation Logic:**
```elixir
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
```

**Type Validation Implementation:**
```elixir
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
```

### JSON SCHEMA GENERATION FOR PROVIDER COMPATIBILITY

**OpenAI Function Calling Schema:**
```elixir
defmodule DSPex.Signature.JsonSchema do
  def generate(signature, :openai) do
    %{
      type: "object",
      properties: generate_properties(signature.inputs ++ signature.outputs),
      required: get_required_fields(signature.inputs ++ signature.outputs)
    }
  end
  
  defp generate_properties(fields) do
    fields
    |> Enum.map(fn {name, type, constraints} ->
      {name, type_to_json_schema(type, constraints)}
    end)
    |> Map.new()
  end
  
  defp type_to_json_schema(:string, _), do: %{type: "string"}
  defp type_to_json_schema(:integer, _), do: %{type: "integer"}
  defp type_to_json_schema(:float, _), do: %{type: "number"}
  defp type_to_json_schema(:boolean, _), do: %{type: "boolean"}
  defp type_to_json_schema({:list, inner}, _) do
    %{type: "array", items: type_to_json_schema(inner, [])}
  end
end
```

### INTEGRATION WITH ASH RESOURCE LIFECYCLE

**Resource Generation from Signature:**
```elixir
defmodule DSPex.ML.Signature do
  use Ash.Resource,
    domain: DSPex.ML.Domain,
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
end
```

### COMPLETE TESTING PATTERNS

**Comprehensive Test Suite:**
```elixir
defmodule Stage1FoundationTest do
  use ExUnit.Case
  
  defmodule TestSignature do
    use DSPex.Signature
    
    signature question: :string -> answer: :string
  end
  
  defmodule ComplexSignature do
    use DSPex.Signature
    
    signature query: :string, context: {:list, :string} -> 
             answer: :string, confidence: :float, reasoning: {:list, :string}
  end
  
  test "basic signature compilation" do
    signature = TestSignature.__signature__()
    
    assert signature.inputs == [{:question, :string, []}]
    assert signature.outputs == [{:answer, :string, []}]
  end
  
  test "complex signature compilation" do
    signature = ComplexSignature.__signature__()
    
    assert signature.inputs == [
      {:query, :string, []},
      {:context, {:list, :string}, []}
    ]
    assert signature.outputs == [
      {:answer, :string, []},
      {:confidence, :float, []},
      {:reasoning, {:list, :string}, []}
    ]
  end
  
  test "input validation success" do
    {:ok, validated} = TestSignature.validate_inputs(%{question: "test"})
    assert validated.question == "test"
  end
  
  test "input validation failure - missing field" do
    {:error, reason} = TestSignature.validate_inputs(%{})
    assert reason =~ "Missing field: question"
  end
  
  test "input validation failure - wrong type" do
    {:error, reason} = TestSignature.validate_inputs(%{question: 123})
    assert reason =~ "Expected :string"
  end
  
  test "JSON schema generation" do
    schema = TestSignature.to_json_schema(:openai)
    
    assert schema.type == "object"
    assert schema.properties.question.type == "string"
    assert schema.properties.answer.type == "string"
    assert "question" in schema.required
    assert "answer" in schema.required
  end
end
```

### ERROR HANDLING AND DEBUGGING

**Comprehensive Error Messages:**
```elixir
defp compile_signature(ast, module) do
  case parse_signature_ast(ast) do
    {:ok, {inputs, outputs}} ->
      generate_signature_code(inputs, outputs, module)
    {:error, reason} ->
      raise """
      Invalid signature syntax in #{module}: #{reason}
      
      Expected syntax examples:
        signature question: :string -> answer: :string
        signature query: :string, context: :string -> answer: :string, confidence: :float
      
      Received: #{inspect(ast)}
      """
  end
end
```

### CONFIGURATION AND ENVIRONMENT SETUP

**Application Configuration:**
```elixir
# config/config.exs
import Config

config :dspex, :adapter, DSPex.Adapters.PythonPort

config :dspex, DSPex.Repo,
  username: "postgres",
  password: "postgres", 
  hostname: "localhost",
  database: "dspex_dev",
  pool_size: 10

config :dspex,
  ecto_repos: [DSPex.Repo]
```

**Application Supervision:**
```elixir
defmodule DSPex.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Signature registry for runtime lookup
      {Registry, keys: :unique, name: DSPex.SignatureRegistry},
      
      # Ash resources if using Postgres
      {AshPostgres.Repo, Application.get_env(:dspex, DSPex.Repo)}
    ]
    
    opts = [strategy: :one_for_one, name: DSPex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## IMPLEMENTATION TASK

Based on the complete context above, implement the core signature system with the following specific requirements:

### FILE STRUCTURE TO CREATE:
```
lib/dspex/signature/
├── signature.ex          # Core behavior and DSL
├── compiler.ex           # Compile-time processing
├── type_parser.ex        # Type system parser
├── validator.ex          # Runtime validation
└── json_schema.ex        # Provider schema generation
```

### SPECIFIC IMPLEMENTATION REQUIREMENTS:

1. **Signature Behavior (`lib/dspex/signature/signature.ex`)**:
   - Implement `__using__` macro with proper module attributes
   - Create DSL module with `signature` macro for native syntax
   - Set up compile-time hooks with `@before_compile`

2. **Signature Compiler (`lib/dspex/signature/compiler.ex`)**:
   - Implement `__before_compile__` callback
   - Parse signature AST for various syntax patterns
   - Generate signature metadata and validation functions
   - Handle error cases with helpful messages

3. **Type Parser (`lib/dspex/signature/type_parser.ex`)**:
   - Support all basic types (:string, :integer, :float, :boolean, :atom, :any, :map)
   - Support ML-specific types (:embedding, :probability, :confidence_score, :reasoning_chain)
   - Support composite types ({:list, inner}, {:dict, key, value}, {:union, types})
   - Provide clear error messages for unsupported types

4. **Runtime Validator (`lib/dspex/signature/validator.ex`)**:
   - Implement field validation with proper error handling
   - Support nested validation for composite types
   - Return validated data or descriptive errors
   - Handle edge cases (nil values, type mismatches)

5. **JSON Schema Generator (`lib/dspex/signature/json_schema.ex`)**:
   - Generate OpenAI-compatible function calling schemas
   - Support all signature types with proper JSON Schema mappings
   - Handle required fields and optional constraints
   - Extensible for other providers (Anthropic, etc.)

### QUALITY REQUIREMENTS:

- **Comprehensive Documentation**: Every module, function, and macro must have detailed @moduledoc and @doc
- **Error Handling**: All error paths must provide helpful, actionable error messages
- **Type Safety**: Use proper typespecs for all public functions
- **Testing**: Include comprehensive test cases covering all syntax variations and error conditions
- **Performance**: Compile-time processing should be efficient, runtime validation minimal overhead
- **Extensibility**: Design for easy addition of new types and providers

### INTEGRATION POINTS:

- Must integrate cleanly with Ash resource lifecycle
- Should support ExDantic validation patterns where applicable
- Must be compatible with the adapter pattern for Python bridge
- Should enable JSON schema generation for multiple providers
- Must support the native signature syntax exactly as specified

### SUCCESS CRITERIA:

1. Native signature syntax compiles successfully: `signature question: :string -> answer: :string`
2. Complex signatures work: `signature query: :string, context: {:list, :string} -> answer: :string, confidence: :float`
3. Runtime validation catches type errors and missing fields
4. JSON schema generation produces valid OpenAI function calling schemas
5. All test cases pass with comprehensive coverage
6. Error messages are helpful and actionable
7. Performance is acceptable for compile-time and runtime operations

This signature system forms the foundation for the entire DSPy-Ash integration. It must be robust, well-tested, and extensible to support the advanced features planned for later stages.