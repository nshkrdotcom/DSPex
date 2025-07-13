# Stage 2 Prompt 1: Native Signature Compilation System

## OBJECTIVE

Implement a complete native Elixir signature compilation system that replaces Python-based signature parsing with high-performance native compilation, deep ExDantic integration for type safety, multi-provider JSON schema generation, and intelligent ETS-based caching. This system must provide 100% DSPy signature compatibility while delivering 10x performance improvements through native Elixir compilation and optimization.

## COMPLETE IMPLEMENTATION CONTEXT

### SIGNATURE COMPILATION ARCHITECTURE OVERVIEW

From Stage 2 Technical Specification:

```
┌─────────────────────────────────────────────────────────────┐
│              Native Signature Compilation System           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Native Parser   │  │ ExDantic        │  │ Schema       ││
│  │ - AST Analysis  │  │ Integration     │  │ Generation   ││
│  │ - Type Inference│  │ - Type Adapters │  │ - OpenAI     ││
│  │ - Validation    │  │ - Validators    │  │ - Anthropic  ││
│  │ - Optimization  │  │ - Coercion      │  │ - Generic    ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ ETS Caching     │  │ Compile-time    │  │ Runtime      ││
│  │ - Hot Signatures│  │ Optimization    │  │ Validation   ││
│  │ - LRU Eviction  │  │ - Code Gen      │  │ - Type Check ││
│  │ - Statistics    │  │ - Inlining      │  │ - Coercion   ││
│  │ - Compression   │  │ - Analysis      │  │ - Error Fmt  ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### DSPY SIGNATURE ANALYSIS

From comprehensive DSPy source code analysis (signatures/signature.py):

**DSPy Signature Core Patterns:**

```python
# DSPy uses metaclass-based signature definition
class SignatureMeta(type):
    def __new__(mcs, name, bases, namespace, **kwargs):
        # Extract field definitions from class attributes
        fields = {}
        for key, value in namespace.items():
            if isinstance(value, Field):
                fields[key] = value
        
        # Create signature configuration
        signature_config = {
            'name': name,
            'fields': fields,
            'instructions': namespace.get('__doc__', ''),
            'field_order': list(fields.keys())
        }
        
        # Store compiled signature
        namespace['_signature'] = signature_config
        return super().__new__(mcs, name, bases, namespace)

class Signature(metaclass=SignatureMeta):
    """Base signature class with field definitions."""
    
    def __init__(self, **kwargs):
        self._inputs = {}
        self._outputs = {}
        
        # Process field definitions
        for name, field in self._signature['fields'].items():
            if isinstance(field, InputField):
                self._inputs[name] = field
            elif isinstance(field, OutputField):
                self._outputs[name] = field

# Field definition patterns
class Field:
    def __init__(self, desc=None, format=None, **kwargs):
        self.desc = desc
        self.format = format
        self.kwargs = kwargs

class InputField(Field):
    pass

class OutputField(Field):
    pass

# Example signature usage
class QASignature(Signature):
    """Answer questions with reasoning."""
    question: str = InputField(desc="The question to answer")
    answer: str = OutputField(desc="The answer with reasoning")
```

**Key DSPy Signature Features:**
1. **Metaclass Processing** - Automatic field extraction and signature compilation
2. **Field Types** - InputField and OutputField with descriptions and constraints  
3. **String Parsing** - Type annotations converted to internal representation
4. **Instruction Integration** - Docstrings become system prompts
5. **Dynamic Field Access** - Runtime field validation and access

### EXDANTIC DEEP INTEGRATION ANALYSIS

From comprehensive ExDantic research:

**ExDantic Core Capabilities for Signature Integration:**

```elixir
# ExDantic schema creation patterns
schema = Exdantic.create_model([
  {:question, %{type: :string, constraints: [min_length: 1, max_length: 1000]}},
  {:answer, %{type: :string, constraints: [min_length: 10]}}
], %{
  title: "QASignature",
  description: "Answer questions with reasoning",
  provider_optimizations: %{
    openai: %{function_calling: true, structured_output: true},
    anthropic: %{tool_calling: true}
  }
})

# Advanced validation with custom validators
validator_config = %{
  field_validators: [
    {:question, &validate_question_format/1},
    {:answer, &validate_answer_quality/1}
  ],
  model_validators: [
    &validate_qa_consistency/1
  ],
  computed_fields: [
    {:confidence, %{type: :float, compute: &compute_answer_confidence/1}}
  ]
}

# JSON schema generation for providers
openai_schema = Exdantic.JsonSchema.generate_openai_function_schema(schema)
anthropic_schema = Exdantic.JsonSchema.generate_anthropic_tool_schema(schema)
```

**ExDantic Integration Benefits:**
1. **Runtime Schema Creation** - Dynamic schema compilation and caching
2. **Advanced Validation** - Field and model validators with custom logic
3. **Provider Optimization** - Automatic schema generation for different providers
4. **Type Coercion** - Intelligent type conversion and validation
5. **Error Formatting** - Human-readable validation error messages
6. **Performance Optimization** - Compiled validators and caching

### COMPREHENSIVE NATIVE SIGNATURE SYSTEM

**Core Signature Behavior with Native Compilation:**

```elixir
defmodule DSPex.Signature.Native do
  @moduledoc """
  Native Elixir signature compilation system with ExDantic integration.
  Provides 100% DSPy compatibility with 10x performance improvements.
  """
  
  defmacro __using__(opts) do
    quote do
      import DSPex.Signature.Native
      import DSPex.Signature.DSL
      
      # Module attributes for signature compilation
      Module.register_attribute(__MODULE__, :signature_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :signature_config, accumulate: false)
      Module.register_attribute(__MODULE__, :signature_metadata, accumulate: false)
      
      @before_compile DSPex.Signature.Native
    end
  end
  
  @doc """
  Define signature with native syntax compatible with DSPy.
  
  Examples:
    signature question: :string -> answer: :string
    signature query: :string, context: :list -> answer: :string, confidence: :float
  """
  defmacro signature(definition) do
    quote do
      @signature_config DSPex.Signature.Parser.parse_signature_definition(
        unquote(Macro.escape(definition)),
        __MODULE__
      )
    end
  end
  
  @doc """
  Define input field with validation and metadata.
  """
  defmacro input_field(name, type, opts \\ []) do
    quote do
      @signature_fields {:input, unquote(name), unquote(type), unquote(opts)}
    end
  end
  
  @doc """
  Define output field with validation and metadata.
  """
  defmacro output_field(name, type, opts \\ []) do
    quote do
      @signature_fields {:output, unquote(name), unquote(type), unquote(opts)}
    end
  end
  
  defmacro __before_compile__(env) do
    signature_config = Module.get_attribute(env.module, :signature_config)
    signature_fields = Module.get_attribute(env.module, :signature_fields)
    
    case {signature_config, signature_fields} do
      {nil, []} ->
        raise CompileError, 
          description: "No signature defined in #{env.module}. Use `signature` macro or field definitions.",
          file: env.file,
          line: env.line
      
      {config, fields} when config != nil ->
        # Compile signature from macro definition
        compile_signature_from_config(config, env)
      
      {nil, fields} when fields != [] ->
        # Compile signature from field definitions
        compile_signature_from_fields(fields, env)
    end
  end
  
  defp compile_signature_from_config(config, env) do
    # Parse and validate signature configuration
    {input_fields, output_fields} = extract_fields_from_config(config)
    
    # Generate compilation metadata
    compilation_metadata = %{
      module: env.module,
      file: env.file,
      line: env.line,
      compiled_at: System.system_time(:second),
      signature_hash: generate_signature_hash(config, input_fields, output_fields)
    }
    
    quote do
      # Store compiled signature
      @signature_compiled %{
        module: unquote(env.module),
        name: unquote(config.name || to_string(env.module)),
        description: unquote(config.description || Module.get_attribute(env.module, :moduledoc)),
        input_fields: unquote(Macro.escape(input_fields)),
        output_fields: unquote(Macro.escape(output_fields)),
        metadata: unquote(Macro.escape(compilation_metadata)),
        hash: unquote(compilation_metadata.signature_hash)
      }
      
      # Generate field access functions
      unquote(generate_field_functions(input_fields, output_fields))
      
      # Generate validation functions
      unquote(generate_validation_functions(input_fields, output_fields))
      
      # Generate schema functions
      unquote(generate_schema_functions(input_fields, output_fields))
      
      # Generate ExDantic integration
      unquote(generate_exdantic_integration(input_fields, output_fields, config))
      
      # Register signature for caching
      def __signature__, do: @signature_compiled
      
      # DSPy compatibility functions
      def input_fields, do: unquote(Macro.escape(input_fields))
      def output_fields, do: unquote(Macro.escape(output_fields))
      def signature_hash, do: unquote(compilation_metadata.signature_hash)
    end
  end
  
  defp generate_field_functions(input_fields, output_fields) do
    all_fields = input_fields ++ output_fields
    
    Enum.map(all_fields, fn field ->
      field_name = field.name
      
      quote do
        def unquote(:"get_#{field_name}_field")() do
          unquote(Macro.escape(field))
        end
        
        def unquote(:"validate_#{field_name}")(value) do
          DSPex.Signature.Validation.validate_field_value(
            value, 
            unquote(Macro.escape(field))
          )
        end
      end
    end)
  end
  
  defp generate_validation_functions(input_fields, output_fields) do
    quote do
      def validate_inputs(inputs) when is_map(inputs) do
        DSPex.Signature.Validation.validate_inputs(
          inputs,
          unquote(Macro.escape(input_fields))
        )
      end
      
      def validate_outputs(outputs) when is_map(outputs) do
        DSPex.Signature.Validation.validate_outputs(
          outputs,
          unquote(Macro.escape(output_fields))
        )
      end
      
      def validate_signature_data(inputs, outputs) do
        with {:ok, validated_inputs} <- validate_inputs(inputs),
             {:ok, validated_outputs} <- validate_outputs(outputs) do
          {:ok, {validated_inputs, validated_outputs}}
        else
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end
  
  defp generate_schema_functions(input_fields, output_fields) do
    quote do
      def generate_json_schema(provider \\ :generic) do
        DSPex.Signature.SchemaGenerator.generate_schema(
          unquote(Macro.escape(input_fields)),
          unquote(Macro.escape(output_fields)),
          provider
        )
      end
      
      def generate_openai_function_schema() do
        generate_json_schema(:openai)
      end
      
      def generate_anthropic_tool_schema() do
        generate_json_schema(:anthropic)
      end
      
      def get_provider_schemas() do
        %{
          openai: generate_openai_function_schema(),
          anthropic: generate_anthropic_tool_schema(),
          generic: generate_json_schema(:generic)
        }
      end
    end
  end
  
  defp generate_exdantic_integration(input_fields, output_fields, config) do
    quote do
      def create_exdantic_schemas() do
        input_schema = DSPex.Signature.ExDanticCompiler.create_input_schema(
          unquote(Macro.escape(input_fields)),
          unquote(Macro.escape(config))
        )
        
        output_schema = DSPex.Signature.ExDanticCompiler.create_output_schema(
          unquote(Macro.escape(output_fields)),
          unquote(Macro.escape(config))
        )
        
        {input_schema, output_schema}
      end
      
      def validate_with_exdantic(inputs, outputs) do
        {input_schema, output_schema} = create_exdantic_schemas()
        
        with {:ok, validated_inputs} <- Exdantic.validate(input_schema, inputs),
             {:ok, validated_outputs} <- Exdantic.validate(output_schema, outputs) do
          {:ok, {validated_inputs, validated_outputs}}
        else
          {:error, validation_errors} -> {:error, validation_errors}
        end
      end
    end
  end
end
```

### SIGNATURE PARSER WITH ADVANCED AST ANALYSIS

**Native Signature Parsing Engine:**

```elixir
defmodule DSPex.Signature.Parser do
  @moduledoc """
  Advanced signature parsing with AST analysis and type inference.
  """
  
  alias DSPex.Types.Registry
  
  def parse_signature_definition(ast, module) do
    case ast do
      # Pattern: signature name: inputs -> outputs
      {:signature, _, [{:"::", _, [name_ast, definition_ast]}]} ->
        parse_named_signature(name_ast, definition_ast, module)
      
      # Pattern: signature inputs -> outputs  
      {:signature, _, [definition_ast]} ->
        parse_anonymous_signature(definition_ast, module)
      
      # Invalid pattern
      _ ->
        raise ArgumentError, "Invalid signature definition: #{Macro.to_string(ast)}"
    end
  end
  
  defp parse_named_signature(name_ast, definition_ast, module) do
    name = extract_signature_name(name_ast)
    {inputs, outputs} = parse_field_definition(definition_ast)
    
    %{
      name: name,
      description: get_module_description(module),
      inputs: inputs,
      outputs: outputs,
      module: module
    }
  end
  
  defp parse_anonymous_signature(definition_ast, module) do
    {inputs, outputs} = parse_field_definition(definition_ast)
    
    %{
      name: infer_signature_name(module),
      description: get_module_description(module),
      inputs: inputs,
      outputs: outputs,
      module: module
    }
  end
  
  defp parse_field_definition(ast) do
    case ast do
      # Pattern: inputs -> outputs
      {:"->",[context: context], [inputs_ast, outputs_ast]} ->
        inputs = parse_field_list(inputs_ast, :input)
        outputs = parse_field_list(outputs_ast, :output)
        {inputs, outputs}
      
      # Invalid pattern
      _ ->
        raise ArgumentError, "Invalid field definition: #{Macro.to_string(ast)}"
    end
  end
  
  defp parse_field_list(ast, field_type) do
    case ast do
      # Single field
      {field_name, _, nil} when is_atom(field_name) ->
        [create_field(field_name, :any, field_type, [])]
      
      # Typed field: name: type
      {:"::", _, [{field_name, _, nil}, type_ast]} when is_atom(field_name) ->
        type = parse_type_expression(type_ast)
        [create_field(field_name, type, field_type, [])]
      
      # Multiple fields: {field1, field2, ...}
      {:{}, _, field_asts} ->
        Enum.map(field_asts, fn field_ast ->
          parse_single_field(field_ast, field_type)
        end)
      
      # Tuple with two fields: {field1, field2}
      {field1_ast, field2_ast} ->
        [
          parse_single_field(field1_ast, field_type),
          parse_single_field(field2_ast, field_type)
        ]
      
      # List of fields
      fields when is_list(fields) ->
        Enum.map(fields, fn field_ast ->
          parse_single_field(field_ast, field_type)
        end)
      
      # Invalid pattern
      _ ->
        raise ArgumentError, "Invalid field list: #{Macro.to_string(ast)}"
    end
  end
  
  defp parse_single_field(ast, field_type) do
    case ast do
      # Simple field name
      {field_name, _, nil} when is_atom(field_name) ->
        create_field(field_name, :any, field_type, [])
      
      # Typed field: name: type
      {:"::", _, [{field_name, _, nil}, type_ast]} when is_atom(field_name) ->
        type = parse_type_expression(type_ast)
        create_field(field_name, type, field_type, [])
      
      # Field with options: name: type, opt1: val1
      {:"::", _, [{field_name, _, nil}, {type_ast, opts_ast}]} when is_atom(field_name) ->
        type = parse_type_expression(type_ast)
        opts = parse_field_options(opts_ast)
        create_field(field_name, type, field_type, opts)
      
      _ ->
        raise ArgumentError, "Invalid field definition: #{Macro.to_string(ast)}"
    end
  end
  
  defp parse_type_expression(type_ast) do
    case type_ast do
      # Basic types
      type when type in [:string, :integer, :float, :boolean, :atom, :binary, :any] ->
        type
      
      # List type: list(inner_type) or [inner_type]
      {:list, _, [inner_type_ast]} ->
        inner_type = parse_type_expression(inner_type_ast)
        {:list, inner_type}
      
      [inner_type_ast] ->
        inner_type = parse_type_expression(inner_type_ast)
        {:list, inner_type}
      
      # Map type
      :map ->
        :map
      
      # Tuple type: {type1, type2, ...}
      {:{}, _, type_asts} ->
        types = Enum.map(type_asts, &parse_type_expression/1)
        {:tuple, types}
      
      # Union type: type1 | type2
      {:|, _, [type1_ast, type2_ast]} ->
        type1 = parse_type_expression(type1_ast)
        type2 = parse_type_expression(type2_ast)
        {:union, [type1, type2]}
      
      # Optional type: optional(type)
      {:optional, _, [inner_type_ast]} ->
        inner_type = parse_type_expression(inner_type_ast)
        {:optional, inner_type}
      
      # Custom ML types
      ml_type when ml_type in [
        :reasoning_chain, :confidence_score, :embedding, :prompt_template,
        :function_call, :tool_result, :model_output, :token_usage
      ] ->
        ml_type
      
      # Module reference for custom types
      {{:., _, [module, type]}, _, []} ->
        {:custom, module, type}
      
      # Unknown type - treat as custom
      type when is_atom(type) ->
        {:custom, type}
      
      _ ->
        raise ArgumentError, "Unsupported type expression: #{Macro.to_string(type_ast)}"
    end
  end
  
  defp parse_field_options(opts_ast) do
    # Parse field options like desc: "description", min_length: 10
    case opts_ast do
      opts when is_list(opts) ->
        Enum.map(opts, fn
          {key, value} when is_atom(key) -> {key, value}
          _ -> raise ArgumentError, "Invalid field option format"
        end)
      
      _ ->
        []
    end
  end
  
  defp create_field(name, type, field_type, opts) do
    %{
      name: name,
      type: type,
      field_type: field_type,
      description: Keyword.get(opts, :desc, Keyword.get(opts, :description)),
      constraints: extract_constraints(opts),
      metadata: extract_metadata(opts)
    }
  end
  
  defp extract_constraints(opts) do
    constraint_keys = [:min_length, :max_length, :min, :max, :pattern, :format, :required]
    
    opts
    |> Keyword.take(constraint_keys)
    |> Enum.into(%{})
  end
  
  defp extract_metadata(opts) do
    metadata_keys = [:provider_hints, :quality_metrics, :cost_weight]
    
    opts
    |> Keyword.take(metadata_keys)
    |> Enum.into(%{})
  end
  
  defp extract_signature_name(ast) do
    case ast do
      {name, _, nil} when is_atom(name) -> to_string(name)
      name when is_atom(name) -> to_string(name)
      name when is_binary(name) -> name
      _ -> raise ArgumentError, "Invalid signature name: #{Macro.to_string(ast)}"
    end
  end
  
  defp infer_signature_name(module) do
    module
    |> to_string()
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
  end
  
  defp get_module_description(module) do
    case Module.get_attribute(module, :moduledoc) do
      {_, description} when is_binary(description) -> description
      nil -> nil
      _ -> nil
    end
  end
end
```

### EXDANTIC COMPILER INTEGRATION

**Deep ExDantic Integration for Signature Compilation:**

```elixir
defmodule DSPex.Signature.ExDanticCompiler do
  @moduledoc """
  ExDantic integration for signature compilation with advanced validation.
  """
  
  alias Exdantic.{Schema, TypeAdapter, Config}
  alias DSPex.Types.{MLTypes, Conversion, Validation}
  
  def create_input_schema(input_fields, config \\ %{}) do
    # Build ExDantic field definitions
    field_definitions = Enum.map(input_fields, fn field ->
      {field.name, build_field_definition(field, :input)}
    end)
    
    # Create schema configuration
    schema_config = %{
      title: "#{config[:name] || "Signature"}InputSchema",
      description: "Input validation for #{config[:name] || "signature"}",
      strict: config[:strict_validation] || false,
      extra: config[:allow_extra_fields] || false,
      validation_alias: config[:validation_alias] || %{},
      field_validators: build_field_validators(input_fields),
      model_validators: build_model_validators(input_fields, :input)
    }
    
    case Exdantic.create_model(field_definitions, schema_config) do
      {:ok, schema} ->
        enhance_schema_for_ml(schema, input_fields, :input)
      
      {:error, reason} ->
        {:error, {:schema_creation_failed, reason}}
    end
  end
  
  def create_output_schema(output_fields, config \\ %{}) do
    # Build ExDantic field definitions
    field_definitions = Enum.map(output_fields, fn field ->
      {field.name, build_field_definition(field, :output)}
    end)
    
    # Create schema configuration with output-specific features
    schema_config = %{
      title: "#{config[:name] || "Signature"}OutputSchema",
      description: "Output validation for #{config[:name] || "signature"}",
      strict: config[:strict_validation] || true,  # Stricter for outputs
      extra: false,  # No extra fields in outputs
      validation_alias: config[:validation_alias] || %{},
      field_validators: build_field_validators(output_fields),
      model_validators: build_model_validators(output_fields, :output),
      computed_fields: build_computed_fields(output_fields)
    }
    
    case Exdantic.create_model(field_definitions, schema_config) do
      {:ok, schema} ->
        enhance_schema_for_ml(schema, output_fields, :output)
      
      {:error, reason} ->
        {:error, {:schema_creation_failed, reason}}
    end
  end
  
  defp build_field_definition(field, direction) do
    base_type = convert_to_exdantic_type(field.type)
    
    %{
      type: base_type,
      description: field.description,
      constraints: build_exdantic_constraints(field.constraints),
      default: get_field_default(field, direction),
      validators: get_field_validators(field),
      metadata: %{
        ml_field: true,
        direction: direction,
        original_type: field.type,
        dspy_compatible: true
      }
    }
  end
  
  defp convert_to_exdantic_type(type) do
    case type do
      # Basic types
      :string -> :string
      :integer -> :integer  
      :float -> :float
      :boolean -> :boolean
      :atom -> :atom
      :binary -> :binary
      :any -> :any
      :map -> :map
      
      # Composite types
      {:list, inner_type} ->
        {:list, convert_to_exdantic_type(inner_type)}
      
      {:tuple, types} ->
        {:tuple, Enum.map(types, &convert_to_exdantic_type/1)}
      
      {:union, types} ->
        {:union, Enum.map(types, &convert_to_exdantic_type/1)}
      
      {:optional, inner_type} ->
        {:optional, convert_to_exdantic_type(inner_type)}
      
      # ML-specific types
      :reasoning_chain ->
        {:list, :reasoning_step}
      
      :confidence_score ->
        {:float, constraints: [min: 0.0, max: 1.0]}
      
      :embedding ->
        {:list, :float}
      
      :prompt_template ->
        :string
      
      :function_call ->
        :map
      
      :tool_result ->
        :map
      
      :model_output ->
        :map
      
      :token_usage ->
        :map
      
      # Custom types
      {:custom, module, type} ->
        {:custom, module, type}
      
      {:custom, type} ->
        {:custom, type}
      
      # Fallback
      _ ->
        :any
    end
  end
  
  defp build_exdantic_constraints(constraints) do
    # Convert DSPy constraints to ExDantic format
    Enum.reduce(constraints, [], fn {key, value}, acc ->
      case key do
        :min_length -> [{:min_length, value} | acc]
        :max_length -> [{:max_length, value} | acc]
        :min -> [{:min, value} | acc]
        :max -> [{:max, value} | acc]
        :pattern -> [{:regex, value} | acc]
        :format -> [{:format, value} | acc]
        _ -> acc
      end
    end)
  end
  
  defp build_field_validators(fields) do
    Enum.reduce(fields, %{}, fn field, acc ->
      validators = get_ml_validators_for_type(field.type)
      
      if validators != [] do
        Map.put(acc, field.name, validators)
      else
        acc
      end
    end)
  end
  
  defp get_ml_validators_for_type(type) do
    case type do
      :reasoning_chain ->
        [&validate_reasoning_chain/1]
      
      :confidence_score ->
        [&validate_confidence_score/1]
      
      :embedding ->
        [&validate_embedding/1]
      
      :prompt_template ->
        [&validate_prompt_template/1]
      
      :function_call ->
        [&validate_function_call/1]
      
      _ ->
        []
    end
  end
  
  defp build_model_validators(fields, direction) do
    base_validators = []
    
    # Add direction-specific validators
    direction_validators = case direction do
      :input ->
        [&validate_input_completeness/1]
      
      :output ->
        [&validate_output_quality/1, &validate_output_consistency/1]
    end
    
    # Add field relationship validators
    relationship_validators = build_relationship_validators(fields)
    
    base_validators ++ direction_validators ++ relationship_validators
  end
  
  defp build_computed_fields(output_fields) do
    # Build computed fields for quality metrics and metadata
    Enum.reduce(output_fields, [], fn field, acc ->
      computed_fields = case field.type do
        :reasoning_chain ->
          [
            {:reasoning_quality, %{
              type: :map,
              compute: &compute_reasoning_quality/1,
              description: "Quality metrics for reasoning chain"
            }}
          ]
        
        :confidence_score ->
          [
            {:confidence_calibrated, %{
              type: :float,
              compute: &calibrate_confidence/1,
              description: "Calibrated confidence score"
            }}
          ]
        
        _ ->
          []
      end
      
      acc ++ computed_fields
    end)
  end
  
  defp enhance_schema_for_ml(schema, fields, direction) do
    # Add ML-specific enhancements to the schema
    enhanced_schema = %{
      schema |
      ml_enhanced: true,
      direction: direction,
      field_metadata: build_field_metadata(fields),
      provider_optimizations: build_provider_optimizations(fields),
      quality_metrics: build_quality_metrics(fields)
    }
    
    {:ok, enhanced_schema}
  end
  
  defp build_field_metadata(fields) do
    Enum.reduce(fields, %{}, fn field, acc ->
      metadata = %{
        type: field.type,
        constraints: field.constraints,
        ml_category: classify_ml_field(field.type),
        performance_hints: get_performance_hints(field.type)
      }
      
      Map.put(acc, field.name, metadata)
    end)
  end
  
  defp classify_ml_field(type) do
    case type do
      t when t in [:reasoning_chain, :confidence_score] -> :reasoning
      t when t in [:embedding, :similarity_score] -> :vector
      t when t in [:function_call, :tool_result] -> :function
      t when t in [:prompt_template] -> :prompt
      t when t in [:token_usage, :model_output] -> :model
      _ -> :general
    end
  end
  
  # ML-specific validator functions
  defp validate_reasoning_chain(reasoning_steps) when is_list(reasoning_steps) do
    case validate_reasoning_structure(reasoning_steps) do
      :ok ->
        case validate_reasoning_consistency(reasoning_steps) do
          :ok -> {:ok, reasoning_steps}
          {:error, reason} -> {:error, {:reasoning_inconsistency, reason}}
        end
      
      {:error, reason} ->
        {:error, {:invalid_reasoning_structure, reason}}
    end
  end
  
  defp validate_confidence_score(score) when is_number(score) do
    cond do
      score < 0.0 ->
        {:error, :confidence_below_minimum}
      
      score > 1.0 ->
        {:error, :confidence_above_maximum}
      
      true ->
        {:ok, Float.round(score, 3)}
    end
  end
  
  defp validate_embedding(embedding) when is_list(embedding) do
    cond do
      length(embedding) == 0 ->
        {:error, :empty_embedding}
      
      not Enum.all?(embedding, &is_number/1) ->
        {:error, :non_numeric_embedding}
      
      true ->
        # Check magnitude
        magnitude = calculate_embedding_magnitude(embedding)
        
        if magnitude > 0 do
          {:ok, embedding}
        else
          {:error, :zero_magnitude_embedding}
        end
    end
  end
  
  defp validate_prompt_template(template) when is_binary(template) do
    case parse_template_variables(template) do
      {:ok, variables} ->
        if valid_template_syntax?(template, variables) do
          {:ok, template}
        else
          {:error, :invalid_template_syntax}
        end
      
      {:error, reason} ->
        {:error, {:template_parse_error, reason}}
    end
  end
  
  defp validate_function_call(function_call) when is_map(function_call) do
    required_fields = [:function_name, :arguments]
    
    case validate_required_fields(function_call, required_fields) do
      :ok ->
        case validate_function_call_format(function_call) do
          :ok -> {:ok, function_call}
          {:error, reason} -> {:error, reason}
        end
      
      {:error, missing_fields} ->
        {:error, {:missing_required_fields, missing_fields}}
    end
  end
  
  # Quality computation functions
  defp compute_reasoning_quality(data) do
    reasoning_chain = Map.get(data, :reasoning_chain, [])
    
    %{
      step_count: length(reasoning_chain),
      logical_consistency: assess_logical_consistency(reasoning_chain),
      evidence_strength: assess_evidence_strength(reasoning_chain),
      clarity_score: assess_clarity(reasoning_chain),
      overall_quality: calculate_overall_quality(reasoning_chain)
    }
  end
  
  defp calibrate_confidence(data) do
    confidence = Map.get(data, :confidence, 0.5)
    
    # Apply calibration based on historical performance
    calibration_factor = get_calibration_factor(data)
    calibrated = confidence * calibration_factor
    
    # Ensure bounds
    max(0.0, min(1.0, calibrated))
  end
  
  # Helper functions
  defp calculate_embedding_magnitude(embedding) do
    embedding
    |> Enum.map(&(&1 * &1))
    |> Enum.sum()
    |> :math.sqrt()
  end
  
  defp parse_template_variables(template) do
    try do
      variables = Regex.scan(~r/\{\{(\w+)\}\}/, template)
      |> Enum.map(fn [_, var] -> var end)
      |> Enum.uniq()
      
      {:ok, variables}
    rescue
      _ -> {:error, :regex_parse_error}
    end
  end
  
  defp valid_template_syntax?(template, variables) do
    # Check for balanced braces and valid variable names
    brace_count = template
    |> String.graphemes()
    |> Enum.reduce({0, true}, fn
      "{", {count, valid} -> {count + 1, valid}
      "}", {count, valid} when count > 0 -> {count - 1, valid}
      "}", {0, _valid} -> {0, false}
      _, {count, valid} -> {count, valid}
    end)
    
    case brace_count do
      {0, true} -> true
      _ -> false
    end
  end
end
```

### HIGH-PERFORMANCE ETS CACHING SYSTEM

**Intelligent Signature Caching with Performance Optimization:**

```elixir
defmodule DSPex.Signature.Cache do
  @moduledoc """
  High-performance ETS-based signature caching with intelligent eviction.
  """
  
  use GenServer
  
  @table_name :signature_cache
  @hot_signatures_table :hot_signatures
  @compilation_locks_table :compilation_locks
  @stats_table :cache_stats
  
  # Cache configuration
  @default_max_size 10_000
  @default_eviction_strategy :lru
  @maintenance_interval 300_000  # 5 minutes
  @stats_update_interval 60_000   # 1 minute
  
  defstruct [
    :max_size,
    :current_size,
    :eviction_strategy,
    :hit_count,
    :miss_count,
    :eviction_count,
    :compilation_count,
    :memory_usage,
    :last_maintenance
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    # Create ETS tables optimized for concurrent access
    :ets.new(@table_name, [
      :named_table,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true},
      {:decentralized_counters, true}
    ])
    
    :ets.new(@hot_signatures_table, [
      :named_table,
      :public,
      :ordered_set,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    :ets.new(@compilation_locks_table, [
      :named_table,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    :ets.new(@stats_table, [
      :named_table,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    state = %__MODULE__{
      max_size: Keyword.get(opts, :max_size, @default_max_size),
      current_size: 0,
      eviction_strategy: Keyword.get(opts, :eviction_strategy, @default_eviction_strategy),
      hit_count: 0,
      miss_count: 0,
      eviction_count: 0,
      compilation_count: 0,
      memory_usage: 0,
      last_maintenance: System.monotonic_time(:second)
    }
    
    # Initialize stats table
    initialize_stats_table()
    
    # Schedule periodic maintenance
    :timer.send_interval(@maintenance_interval, :maintenance)
    :timer.send_interval(@stats_update_interval, :update_stats)
    
    {:ok, state}
  end
  
  @doc """
  Get compiled signature with high-performance lookup.
  Returns {:ok, compiled} | {:error, :not_cached} | {:error, :compiling}
  """
  def get_compiled(signature_hash) when is_binary(signature_hash) do
    start_time = System.monotonic_time(:microsecond)
    
    result = case :ets.lookup(@table_name, signature_hash) do
      [{^signature_hash, compiled, access_count, last_access, _size}] ->
        # Update access statistics atomically
        new_access = access_count + 1
        new_last_access = System.monotonic_time(:millisecond)
        
        :ets.update_element(@table_name, signature_hash, [
          {3, new_access},
          {4, new_last_access}
        ])
        
        # Update hot signatures tracking for LRU/LFU
        update_hot_signatures(signature_hash, new_access, new_last_access)
        
        # Record cache hit
        record_cache_hit(System.monotonic_time(:microsecond) - start_time)
        
        {:ok, compiled}
      
      [] ->
        # Check if compilation is in progress
        case :ets.lookup(@compilation_locks_table, signature_hash) do
          [{^signature_hash, _lock_ref, _timestamp}] ->
            record_cache_miss(:compiling)
            {:error, :compiling}
          
          [] ->
            record_cache_miss(:not_cached)
            {:error, :not_cached}
        end
    end
    
    result
  end
  
  @doc """
  Store compiled signature with intelligent caching.
  """
  def store_compiled(signature_hash, compiled) when is_binary(signature_hash) do
    GenServer.call(__MODULE__, {:store_compiled, signature_hash, compiled})
  end
  
  @doc """
  Acquire compilation lock to prevent duplicate work.
  """
  def acquire_compilation_lock(signature_hash) when is_binary(signature_hash) do
    lock_ref = make_ref()
    timestamp = System.monotonic_time(:millisecond)
    
    case :ets.insert_new(@compilation_locks_table, {signature_hash, lock_ref, timestamp}) do
      true ->
        {:ok, lock_ref}
      
      false ->
        {:error, :already_locked}
    end
  end
  
  @doc """
  Release compilation lock.
  """
  def release_compilation_lock(signature_hash, lock_ref) when is_binary(signature_hash) do
    case :ets.lookup(@compilation_locks_table, signature_hash) do
      [{^signature_hash, ^lock_ref, _timestamp}] ->
        :ets.delete(@compilation_locks_table, signature_hash)
        :ok
      
      _ ->
        {:error, :invalid_lock}
    end
  end
  
  @doc """
  Get cache statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Clear cache (for testing or maintenance).
  """
  def clear_cache do
    GenServer.call(__MODULE__, :clear_cache)
  end
  
  def handle_call({:store_compiled, signature_hash, compiled}, _from, state) do
    compiled_size = estimate_memory_size(compiled)
    current_time = System.monotonic_time(:millisecond)
    
    # Check if we need to evict entries
    new_state = maybe_evict_entries(state, compiled_size)
    
    # Store the compiled signature
    :ets.insert(@table_name, {signature_hash, compiled, 1, current_time, compiled_size})
    
    # Update hot signatures tracking
    update_hot_signatures(signature_hash, 1, current_time)
    
    # Update state
    updated_state = %{new_state |
      current_size: new_state.current_size + 1,
      compilation_count: new_state.compilation_count + 1,
      memory_usage: new_state.memory_usage + compiled_size
    }
    
    {:reply, :ok, updated_state}
  end
  
  def handle_call(:get_stats, _from, state) do
    total_requests = state.hit_count + state.miss_count
    hit_rate = if total_requests > 0, do: state.hit_count / total_requests, else: 0.0
    
    stats = %{
      hit_count: state.hit_count,
      miss_count: state.miss_count,
      hit_rate: hit_rate,
      eviction_count: state.eviction_count,
      compilation_count: state.compilation_count,
      current_size: state.current_size,
      max_size: state.max_size,
      memory_usage: state.memory_usage,
      cache_efficiency: calculate_cache_efficiency(state)
    }
    
    {:reply, stats, state}
  end
  
  def handle_call(:clear_cache, _from, state) do
    :ets.delete_all_objects(@table_name)
    :ets.delete_all_objects(@hot_signatures_table)
    :ets.delete_all_objects(@compilation_locks_table)
    
    cleared_state = %{state |
      current_size: 0,
      memory_usage: 0
    }
    
    {:reply, :ok, cleared_state}
  end
  
  def handle_info(:maintenance, state) do
    # Perform cache maintenance
    new_state = perform_cache_maintenance(state)
    {:noreply, new_state}
  end
  
  def handle_info(:update_stats, state) do
    # Update statistics in ETS table
    update_stats_table(state)
    {:noreply, state}
  end
  
  # Private functions
  
  defp maybe_evict_entries(state, needed_size) do
    available_space = state.max_size - state.current_size
    memory_pressure = state.memory_usage + needed_size
    
    cond do
      available_space <= 0 ->
        # Cache is full, evict entries
        evict_entries(state, 1)
      
      memory_pressure > get_memory_threshold() ->
        # Memory pressure, evict based on size
        evict_by_memory_pressure(state, needed_size)
      
      true ->
        state
    end
  end
  
  defp evict_entries(state, min_evictions) do
    eviction_count = max(min_evictions, div(state.max_size, 20))  # Evict at least 5%
    
    case state.eviction_strategy do
      :lru ->
        evict_lru_entries(eviction_count)
      
      :lfu ->
        evict_lfu_entries(eviction_count)
      
      :random ->
        evict_random_entries(eviction_count)
      
      :ttl ->
        evict_expired_entries()
    end
    
    %{state |
      current_size: max(0, state.current_size - eviction_count),
      eviction_count: state.eviction_count + eviction_count
    }
  end
  
  defp evict_lru_entries(count) do
    # Find least recently used entries
    oldest_entries = :ets.select(@hot_signatures_table, [
      {{'$1', '$2', '$3'}, [], [['$1', '$2']]}
    ])
    |> Enum.sort()
    |> Enum.take(count)
    
    Enum.each(oldest_entries, fn [_timestamp, signature_hash] ->
      :ets.delete(@table_name, signature_hash)
      :ets.match_delete(@hot_signatures_table, {'_', signature_hash, '_'})
    end)
  end
  
  defp evict_lfu_entries(count) do
    # Find least frequently used entries
    least_used_entries = :ets.select(@hot_signatures_table, [
      {{'$1', '$2', '$3'}, [], [['$3', '$2']]}
    ])
    |> Enum.sort()
    |> Enum.take(count)
    
    Enum.each(least_used_entries, fn [_access_count, signature_hash] ->
      :ets.delete(@table_name, signature_hash)
      :ets.match_delete(@hot_signatures_table, {'_', signature_hash, '_'})
    end)
  end
  
  defp evict_random_entries(count) do
    # Get random entries to evict
    all_keys = :ets.select(@table_name, [
      {{'$1', '_', '_', '_', '_'}, [], ['$1']}
    ])
    
    random_keys = all_keys
    |> Enum.shuffle()
    |> Enum.take(count)
    
    Enum.each(random_keys, fn signature_hash ->
      :ets.delete(@table_name, signature_hash)
      :ets.match_delete(@hot_signatures_table, {'_', signature_hash, '_'})
    end)
  end
  
  defp evict_by_memory_pressure(state, needed_size) do
    # Evict entries based on memory usage
    target_freed = needed_size * 2  # Free twice what we need
    
    large_entries = :ets.select(@table_name, [
      {{'$1', '_', '_', '_', '$5'}, [{'>', '$5', 1000}], [['$1', '$5']]}
    ])
    |> Enum.sort_by(fn [_hash, size] -> size end, :desc)
    
    {evicted_hashes, _freed_memory} = Enum.reduce_while(large_entries, {[], 0}, fn [hash, size], {hashes, freed} ->
      if freed >= target_freed do
        {:halt, {hashes, freed}}
      else
        {:cont, {[hash | hashes], freed + size}}
      end
    end)
    
    Enum.each(evicted_hashes, fn signature_hash ->
      :ets.delete(@table_name, signature_hash)
      :ets.match_delete(@hot_signatures_table, {'_', signature_hash, '_'})
    end)
    
    %{state | eviction_count: state.eviction_count + length(evicted_hashes)}
  end
  
  defp update_hot_signatures(signature_hash, access_count, last_access) do
    # Remove old entry if exists
    :ets.match_delete(@hot_signatures_table, {'_', signature_hash, '_'})
    
    # Insert new entry
    :ets.insert(@hot_signatures_table, {last_access, signature_hash, access_count})
  end
  
  defp record_cache_hit(access_time_us) do
    :ets.update_counter(@stats_table, :hits, 1, {:hits, 0})
    :ets.insert(@stats_table, {:last_hit_time, access_time_us})
  end
  
  defp record_cache_miss(reason) do
    :ets.update_counter(@stats_table, :misses, 1, {:misses, 0})
    :ets.update_counter(@stats_table, reason, 1, {reason, 0})
  end
  
  defp estimate_memory_size(compiled_signature) do
    # Rough estimation of memory usage
    :erlang.external_size(compiled_signature)
  end
  
  defp get_memory_threshold do
    # Get system memory and calculate threshold
    total_memory = :erlang.memory(:total)
    div(total_memory, 10)  # Use max 10% of total memory
  end
  
  defp perform_cache_maintenance(state) do
    current_time = System.monotonic_time(:second)
    
    # Clean up expired compilation locks
    cleanup_expired_locks(current_time)
    
    # Update memory usage calculation
    actual_memory = calculate_actual_memory_usage()
    
    # Perform garbage collection if needed
    if actual_memory > get_memory_threshold() do
      :erlang.garbage_collect()
    end
    
    %{state |
      memory_usage: actual_memory,
      last_maintenance: current_time
    }
  end
  
  defp cleanup_expired_locks(current_time) do
    expired_threshold = current_time - 300_000  # 5 minutes
    
    expired_locks = :ets.select(@compilation_locks_table, [
      {{'$1', '$2', '$3'}, [{'<', '$3', expired_threshold}], ['$1']}
    ])
    
    Enum.each(expired_locks, fn signature_hash ->
      :ets.delete(@compilation_locks_table, signature_hash)
    end)
  end
  
  defp calculate_actual_memory_usage do
    :ets.info(@table_name, :memory) * :erlang.system_info(:wordsize) +
    :ets.info(@hot_signatures_table, :memory) * :erlang.system_info(:wordsize) +
    :ets.info(@compilation_locks_table, :memory) * :erlang.system_info(:wordsize)
  end
  
  defp calculate_cache_efficiency(state) do
    total_requests = state.hit_count + state.miss_count
    
    if total_requests > 0 do
      hit_rate = state.hit_count / total_requests
      utilization = state.current_size / state.max_size
      
      # Weighted efficiency score
      hit_rate * 0.7 + utilization * 0.3
    else
      0.0
    end
  end
  
  defp initialize_stats_table do
    :ets.insert(@stats_table, [
      {:hits, 0},
      {:misses, 0},
      {:not_cached, 0},
      {:compiling, 0},
      {:last_hit_time, 0}
    ])
  end
  
  defp update_stats_table(state) do
    stats = [
      {:current_size, state.current_size},
      {:memory_usage, state.memory_usage},
      {:eviction_count, state.eviction_count},
      {:compilation_count, state.compilation_count}
    ]
    
    Enum.each(stats, fn stat ->
      :ets.insert(@stats_table, stat)
    end)
  end
end
```

### MULTI-PROVIDER SCHEMA GENERATION

**Provider-Specific Schema Generation System:**

```elixir
defmodule DSPex.Signature.SchemaGenerator do
  @moduledoc """
  Multi-provider JSON schema generation with optimization for different ML providers.
  """
  
  alias DSPex.Types.Conversion
  
  def generate_schema(input_fields, output_fields, provider \\ :generic) do
    case provider do
      :openai ->
        generate_openai_schemas(input_fields, output_fields)
      
      :anthropic ->
        generate_anthropic_schemas(input_fields, output_fields)
      
      :google ->
        generate_google_schemas(input_fields, output_fields)
      
      :generic ->
        generate_generic_schemas(input_fields, output_fields)
      
      _ ->
        {:error, {:unsupported_provider, provider}}
    end
  end
  
  defp generate_openai_schemas(input_fields, output_fields) do
    # Generate OpenAI-specific schemas
    function_calling_schema = generate_openai_function_calling(input_fields, output_fields)
    structured_output_schema = generate_openai_structured_output(output_fields)
    json_mode_schema = generate_openai_json_mode(output_fields)
    
    %{
      function_calling: function_calling_schema,
      structured_output: structured_output_schema,
      json_mode: json_mode_schema,
      provider: :openai
    }
  end
  
  defp generate_openai_function_calling(input_fields, output_fields) do
    # OpenAI function calling format
    function_schema = %{
      name: "execute_signature",
      description: "Execute the ML signature with provided inputs",
      parameters: %{
        type: "object",
        properties: build_openai_properties(input_fields),
        required: get_required_fields(input_fields)
      }
    }
    
    # Response schema for validation
    response_schema = %{
      type: "object",
      properties: build_openai_properties(output_fields),
      required: get_required_fields(output_fields)
    }
    
    %{
      function: function_schema,
      response: response_schema
    }
  end
  
  defp generate_openai_structured_output(output_fields) do
    # OpenAI structured output format (beta feature)
    %{
      type: "json_schema",
      json_schema: %{
        name: "signature_response",
        strict: true,
        schema: %{
          type: "object",
          properties: build_openai_properties(output_fields),
          required: get_required_fields(output_fields),
          additionalProperties: false
        }
      }
    }
  end
  
  defp generate_openai_json_mode(output_fields) do
    # Simple JSON schema for JSON mode
    %{
      type: "object",
      properties: build_openai_properties(output_fields),
      required: get_required_fields(output_fields)
    }
  end
  
  defp build_openai_properties(fields) do
    Enum.reduce(fields, %{}, fn field, acc ->
      property_schema = build_openai_property_schema(field)
      Map.put(acc, field.name, property_schema)
    end)
  end
  
  defp build_openai_property_schema(field) do
    base_schema = convert_type_to_openai_schema(field.type)
    
    # Add description if available
    schema_with_description = if field.description do
      Map.put(base_schema, :description, field.description)
    else
      base_schema
    end
    
    # Add constraints
    add_openai_constraints(schema_with_description, field.constraints)
  end
  
  defp convert_type_to_openai_schema(type) do
    case type do
      :string ->
        %{type: "string"}
      
      :integer ->
        %{type: "integer"}
      
      :float ->
        %{type: "number"}
      
      :boolean ->
        %{type: "boolean"}
      
      :any ->
        %{}  # No type restriction
      
      {:list, inner_type} ->
        %{
          type: "array",
          items: convert_type_to_openai_schema(inner_type)
        }
      
      :map ->
        %{type: "object"}
      
      {:optional, inner_type} ->
        # Optional types are handled at the required field level
        convert_type_to_openai_schema(inner_type)
      
      {:union, types} ->
        %{
          anyOf: Enum.map(types, &convert_type_to_openai_schema/1)
        }
      
      # ML-specific types
      :reasoning_chain ->
        %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              step: %{type: "string"},
              reasoning: %{type: "string"},
              confidence: %{type: "number", minimum: 0, maximum: 1}
            },
            required: ["step", "reasoning"]
          }
        }
      
      :confidence_score ->
        %{type: "number", minimum: 0, maximum: 1}
      
      :embedding ->
        %{type: "array", items: %{type: "number"}}
      
      :function_call ->
        %{
          type: "object",
          properties: %{
            function_name: %{type: "string"},
            arguments: %{type: "object"}
          },
          required: ["function_name", "arguments"]
        }
      
      # Fallback
      _ ->
        %{type: "string"}
    end
  end
  
  defp add_openai_constraints(schema, constraints) do
    Enum.reduce(constraints, schema, fn {key, value}, acc ->
      case key do
        :min_length -> Map.put(acc, :minLength, value)
        :max_length -> Map.put(acc, :maxLength, value)
        :min -> Map.put(acc, :minimum, value)
        :max -> Map.put(acc, :maximum, value)
        :pattern -> Map.put(acc, :pattern, value)
        _ -> acc
      end
    end)
  end
  
  defp generate_anthropic_schemas(input_fields, output_fields) do
    # Generate Anthropic-specific schemas
    tool_schema = generate_anthropic_tool_calling(input_fields, output_fields)
    structured_schema = generate_anthropic_structured(output_fields)
    
    %{
      tool_calling: tool_schema,
      structured_output: structured_schema,
      provider: :anthropic
    }
  end
  
  defp generate_anthropic_tool_calling(input_fields, output_fields) do
    # Anthropic tool calling format
    %{
      name: "execute_signature",
      description: "Execute the ML signature with provided inputs",
      input_schema: %{
        type: "object",
        properties: build_anthropic_properties(input_fields),
        required: get_required_fields(input_fields)
      }
    }
  end
  
  defp generate_anthropic_structured(output_fields) do
    # Anthropic structured output
    %{
      type: "object",
      properties: build_anthropic_properties(output_fields),
      required: get_required_fields(output_fields)
    }
  end
  
  defp build_anthropic_properties(fields) do
    # Similar to OpenAI but with Anthropic-specific optimizations
    Enum.reduce(fields, %{}, fn field, acc ->
      property_schema = build_anthropic_property_schema(field)
      Map.put(acc, field.name, property_schema)
    end)
  end
  
  defp build_anthropic_property_schema(field) do
    base_schema = convert_type_to_anthropic_schema(field.type)
    
    # Add description and constraints
    schema_with_description = if field.description do
      Map.put(base_schema, :description, field.description)
    else
      base_schema
    end
    
    add_anthropic_constraints(schema_with_description, field.constraints)
  end
  
  defp convert_type_to_anthropic_schema(type) do
    # Anthropic uses similar schema format to OpenAI
    convert_type_to_openai_schema(type)
  end
  
  defp add_anthropic_constraints(schema, constraints) do
    # Anthropic constraint handling
    add_openai_constraints(schema, constraints)
  end
  
  defp get_required_fields(fields) do
    fields
    |> Enum.reject(fn field ->
      match?({:optional, _}, field.type) or
      Map.get(field.constraints, :required, true) == false
    end)
    |> Enum.map(fn field -> field.name end)
  end
end
```

## IMPLEMENTATION REQUIREMENTS

### SUCCESS CRITERIA

**Stage 2 Native Signature Compilation Must Achieve:**

1. **100% DSPy Compatibility** - All DSPy signature patterns supported natively
2. **10x Performance Improvement** - Sub-millisecond compilation times with caching
3. **ExDantic Deep Integration** - Seamless validation and type safety
4. **Multi-Provider Support** - Optimized schemas for OpenAI, Anthropic, Google, etc.
5. **Production Readiness** - Comprehensive error handling, monitoring, and optimization

### PERFORMANCE TARGETS

**Compilation Performance:**
- **<1ms average** signature compilation time with caching
- **<100ms** cold compilation time for complex signatures
- **>95% cache hit rate** under normal operation
- **>10,000 signatures** cacheable simultaneously
- **<500MB memory** usage for full cache

### COMPATIBILITY REQUIREMENTS

**DSPy Signature Compatibility:**
- All DSPy field types and annotations supported
- Compatible signature definition syntax
- Equivalent validation behavior
- Same error message formats
- Identical runtime behavior

### INTEGRATION POINTS

**Component Integration:**
- Deep ExDantic integration for validation
- ETS caching with intelligent eviction
- Multi-provider schema generation
- Telemetry and monitoring integration
- Stage 1 compatibility and migration support

## EXPECTED DELIVERABLES

### PRIMARY DELIVERABLES

1. **Native Signature Behavior** - Complete `DSPex.Signature.Native` module with DSL
2. **Advanced Parser** - `DSPex.Signature.Parser` with AST analysis and type inference
3. **ExDantic Compiler** - Deep integration with advanced validation features
4. **High-Performance Cache** - ETS-based caching with intelligent management
5. **Schema Generator** - Multi-provider JSON schema generation system

### VERIFICATION AND VALIDATION

**Signature System Verified:**
- All DSPy signature patterns compile correctly
- Type inference works for complex signatures
- Validation provides clear error messages
- Caching delivers performance improvements
- Multi-provider schemas generate correctly

**Performance Validated:**
- Compilation times meet performance targets
- Cache efficiency exceeds requirements
- Memory usage stays within bounds
- Concurrent access performs optimally
- Error recovery works reliably

This comprehensive signature compilation system provides the foundational infrastructure for the entire Stage 2 native implementation, delivering superior performance while maintaining complete DSPy compatibility.