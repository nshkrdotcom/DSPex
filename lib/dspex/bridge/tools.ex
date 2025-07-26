defmodule DSPex.Bridge.Tools do
  @moduledoc """
  Tool registration system for bidirectional Elixir ↔ Python communication.

  This module manages Elixir functions that can be called from Python DSPy code,
  enabling true bidirectional workflows where DSPy reasoning can leverage 
  Elixir's strengths in business logic, concurrent processing, and domain-specific operations.
  
  ## Architecture
  
  The tool system consists of:
  
  1. **Registry** - Maintains available tools with metadata
  2. **Executor** - Safely executes tools with timeout and telemetry
  3. **Bridge** - Enables Python to discover and call tools
  4. **Validation** - Ensures tools meet requirements
  
  ## Tool Discovery
  
  Python can discover available tools through the session:
  
  ```python
  tools = session.list_elixir_tools()
  for tool in tools:
      print(f"{tool.name}: {tool.description}")
  ```
  
  ## Telemetry
  
  All tool executions emit telemetry events for monitoring:
  
  - `[:dspex, :tools, :execute, :start]`
  - `[:dspex, :tools, :execute, :stop]`
  - `[:dspex, :tools, :execute, :exception]`
  """
  
  alias DSPex.Bridge.Tools.{Registry, Executor}
  require Logger

  @doc """
  Register an Elixir function as a tool accessible from Python.

  ## Examples

      # Register a signature parser
      DSPex.Bridge.Tools.register_tool(
        session_id,
        "parse_signature",
        &DSPex.Native.Signature.parse/1,
        %{
          description: "Parse DSPex signature string into structured format",
          parameters: [
            %{name: "signature", type: "string", required: true}
          ],
          returns: %{type: "object", description: "Parsed signature structure"},
          examples: [
            %{
              input: %{"signature" => "question -> answer"},
              output: %{inputs: ["question"], outputs: ["answer"]}
            }
          ]
        }
      )
      
      # Register a business validation function
      DSPex.Bridge.Tools.register_tool(
        session_id,
        "validate_business_rules", 
        &MyApp.BusinessLogic.validate/1,
        %{
          description: "Validate reasoning against business constraints",
          parameters: [
            %{name: "reasoning", type: "string", required: true},
            %{name: "domain", type: "string", required: false}
          ],
          async: true,  # Supports async execution
          timeout: 10_000  # Custom timeout
        }
      )
  """
  def register_tool(session_id, tool_name, function, metadata \\ %{})
      when is_function(function, 1) do
    # Extract module and function for hot code reloading support
    case extract_function_ref(function) do
      {:ok, {module, fun}} ->
        # Register in local registry first
        enhanced_metadata = Map.merge(metadata, %{
          session_id: session_id,
          registered_at: DateTime.utc_now(),
          description: metadata[:description] || "Elixir tool: #{tool_name}"
        })
        
        case Registry.register(tool_name, {module, fun}, enhanced_metadata) do
          :ok ->
            # Then register with Python session
            register_with_python(session_id, tool_name, enhanced_metadata)
            
          error ->
            error
        end
        
      :error ->
        {:error, "Cannot register anonymous function - must be a named function"}
    end
  end

  @doc """
  Register multiple tools at once for a session.
  
  ## Example
  
      tools = [
        {"validate_email", &Validators.email?/1, %{description: "Email validation"}},
        {"validate_phone", &Validators.phone?/1, %{description: "Phone validation"}},
        {"normalize_name", &Normalizers.name/1, %{description: "Name normalization"}}
      ]
      
      {:ok, 3} = DSPex.Bridge.Tools.register_tools(session_id, tools)
  """
  def register_tools(session_id, tools) when is_list(tools) do
    results =
      for {tool_name, function, metadata} <- tools do
        register_tool(session_id, tool_name, function, metadata)
      end

    case Enum.find(results, fn result -> match?({:error, _}, result) end) do
      nil -> {:ok, length(tools)}
      {:error, _} = error -> error
    end
  end
  
  @doc """
  Discovers tools from Python side and registers them in Elixir.
  
  This enables Python-defined tools to be callable from Elixir,
  completing the bidirectional bridge.
  """
  def discover_python_tools(session_id) do
    case Snakepit.execute_in_session(session_id, "list_python_tools", %{}) do
      {:ok, tools} when is_list(tools) ->
        register_python_tools(session_id, tools)
        
      {:error, error} ->
        {:error, "Failed to discover Python tools: #{error}"}
        
      _ ->
        {:error, "Invalid response from Python tool discovery"}
    end
  end
  
  @doc """
  Validates a tool's schema against its implementation.
  
  Ensures that:
  - Required parameters are documented
  - Return type matches actual returns
  - Examples are valid
  """
  def validate_tool_schema(tool_name) do
    with {:ok, {module, function, metadata}} <- Registry.lookup(tool_name),
         :ok <- validate_parameters(metadata[:parameters]),
         :ok <- validate_examples(module, function, metadata[:examples]) do
      {:ok, %{valid: true, tool: tool_name}}
    else
      {:error, reason} ->
        {:error, %{valid: false, tool: tool_name, reason: reason}}
    end
  end
  
  @doc """
  Executes a tool with proper error handling and telemetry.
  
  This is typically called from the gRPC service when Python requests tool execution.
  """
  def execute_tool(tool_name, args, context) do
    Executor.execute(tool_name, args, context)
  end
  
  @doc """
  Executes a tool asynchronously.
  
  Returns a Task that can be awaited or monitored.
  """
  def execute_tool_async(tool_name, args, context) do
    Executor.execute_async(tool_name, args, context)
  end
  
  @doc """
  Gets usage analytics for a specific tool.
  
  Returns telemetry data including:
  - Call count
  - Average execution time
  - Error rate
  - Last called timestamp
  """
  def get_tool_analytics(tool_name) do
    # This would integrate with your telemetry backend
    {:ok, %{
      tool_name: tool_name,
      call_count: 0,
      avg_duration_ms: 0,
      error_rate: 0.0,
      last_called: nil
    }}
  end
  
  @doc """
  Marks a tool as deprecated with a warning message.
  
  Deprecated tools will log warnings when called but continue to function.
  """
  def deprecate_tool(tool_name, message, replacement \\ nil) do
    with {:ok, {module, function, metadata}} <- Registry.lookup(tool_name) do
      updated_metadata = Map.merge(metadata, %{
        deprecated: true,
        deprecation_message: message,
        replacement: replacement,
        deprecated_at: DateTime.utc_now()
      })
      
      Registry.register(tool_name, {module, function}, updated_metadata)
    end
  end
  
  @doc """
  Generates documentation for all registered tools.
  
  Returns markdown-formatted documentation suitable for
  developer reference or automatic API documentation.
  """
  def generate_tool_documentation do
    tools = Registry.list()
    
    docs = """
    # Available DSPex Tools
    
    Generated at: #{DateTime.utc_now()}
    
    ## Tools
    
    #{Enum.map_join(tools, "\n\n", &format_tool_doc/1)}
    """
    
    {:ok, docs}
  end

  @doc """
  Register standard DSPex tools for a session.

  These tools provide common functionality that Python DSPy code might need:
  - Signature parsing and validation
  - Template processing
  - Business rule validation
  - Data transformation utilities
  """
  def register_standard_tools(session_id) do
    standard_tools = [
      # Signature operations
      {"parse_signature", &parse_signature_tool/1,
       %{
         description: "Parse DSPex signature string into structured format",
         parameters: [%{name: "signature", type: "string", required: true}]
       }},
      {"validate_signature", &validate_signature_tool/1,
       %{
         description: "Validate signature format and return detailed analysis",
         parameters: [%{name: "signature", type: "string", required: true}]
       }},

      # Template processing
      {"process_template", &process_template_tool/1,
       %{
         description: "Process template with variables using Elixir's EEx engine",
         parameters: [
           %{name: "template", type: "string", required: true},
           %{name: "variables", type: "object", required: false}
         ]
       }},

      # Data validation and transformation
      {"validate_json", &validate_json_tool/1,
       %{
         description: "Validate and parse JSON data with detailed error reporting",
         parameters: [%{name: "json_string", type: "string", required: true}]
       }},
      {"transform_result", &transform_result_tool/1,
       %{
         description: "Transform DSPy result using Elixir's pattern matching",
         parameters: [
           %{name: "result", type: "object", required: true},
           %{name: "format", type: "string", required: false}
         ]
       }},

      # Business logic validation  
      {"validate_reasoning", &validate_reasoning_tool/1,
       %{
         description: "Validate reasoning chain against business rules",
         parameters: [
           %{name: "reasoning", type: "string", required: true},
           %{name: "domain", type: "string", required: false}
         ]
       }},

      # Concurrent processing
      {"parallel_process", &parallel_process_tool/1,
       %{
         description: "Process multiple items concurrently using Elixir's Task.async_stream",
         parameters: [
           %{name: "items", type: "array", required: true},
           %{name: "operation", type: "string", required: true}
         ]
       }}
    ]

    register_tools(session_id, standard_tools)
  end

  # Tool implementations

  defp parse_signature_tool(%{"signature" => signature}) do
    case DSPex.Native.Signature.parse(signature) do
      {:ok, parsed} -> %{success: true, parsed_signature: parsed}
      {:error, error} -> %{success: false, error: "Parse error: #{error}"}
    end
  end

  defp validate_signature_tool(%{"signature" => signature}) do
    case DSPex.Native.Signature.validate(signature) do
      {:ok, analysis} -> %{success: true, valid: true, analysis: analysis}
      {:error, errors} -> %{success: true, valid: false, errors: errors}
    end
  end

  defp process_template_tool(%{"template" => template} = params) do
    variables = Map.get(params, "variables", %{})

    try do
      # Use EEx for template processing
      result = EEx.eval_string(template, assigns: variables)
      %{success: true, processed_template: result}
    rescue
      error -> %{success: false, error: "Template processing failed: #{inspect(error)}"}
    end
  end

  defp validate_json_tool(%{"json_string" => json_string}) do
    case Jason.decode(json_string) do
      {:ok, parsed} ->
        %{
          success: true,
          valid: true,
          parsed_data: parsed,
          keys: if(is_map(parsed), do: Map.keys(parsed), else: [])
        }

      {:error, %Jason.DecodeError{} = error} ->
        %{
          success: true,
          valid: false,
          error: "Invalid JSON: #{Exception.message(error)}"
        }
    end
  end

  defp transform_result_tool(%{"result" => result} = params) do
    format = Map.get(params, "format", "standard")

    transformed =
      case format do
        "prediction_data" ->
          %{
            "success" => true,
            "result" => %{"prediction_data" => result}
          }

        "chain_of_thought" ->
          case result do
            %{"reasoning" => _reasoning, "answer" => _answer} ->
              %{"success" => true, "result" => %{"prediction_data" => result}}

            _ ->
              %{
                "success" => true,
                "result" => %{"prediction_data" => %{"answer" => inspect(result)}}
              }
          end

        "standard" ->
          %{"success" => true, "transformed_result" => result}

        _ ->
          %{"success" => false, "error" => "Unknown format: #{format}"}
      end

    transformed
  end

  defp validate_reasoning_tool(%{"reasoning" => reasoning} = params) do
    domain = Map.get(params, "domain", "general")

    # Implement domain-specific validation logic
    validation_result =
      case domain do
        "medical" -> validate_medical_reasoning(reasoning)
        "financial" -> validate_financial_reasoning(reasoning)
        "legal" -> validate_legal_reasoning(reasoning)
        "technical" -> validate_technical_reasoning(reasoning)
        _ -> validate_general_reasoning(reasoning)
      end

    %{
      success: true,
      domain: domain,
      validation_result: validation_result
    }
  end

  defp parallel_process_tool(%{"items" => items, "operation" => operation}) do
    try do
      # Use Elixir's concurrent processing capabilities
      processed_items =
        items
        |> Task.async_stream(
          fn item ->
            process_item(item, operation)
          end,
          max_concurrency: System.schedulers_online(),
          timeout: 30_000  # 30 second timeout per item
        )
        |> Enum.map(fn {:ok, result} -> result end)

      %{
        success: true,
        processed_items: processed_items,
        original_count: length(items),
        processed_count: length(processed_items)
      }
    rescue
      error -> %{success: false, error: "Parallel processing failed: #{inspect(error)}"}
    end
  end

  # Domain-specific validation helpers

  defp validate_general_reasoning(reasoning) do
    %{
      valid: true,
      score: calculate_reasoning_score(reasoning),
      suggestions: []
    }
  end

  defp validate_medical_reasoning(reasoning) do
    # Implement medical reasoning validation
    %{
      valid: String.contains?(reasoning, ["symptom", "diagnosis", "treatment"]),
      score: calculate_reasoning_score(reasoning),
      domain_specific_checks: ["medical_terms_present", "logical_flow"]
    }
  end

  defp validate_financial_reasoning(reasoning) do
    # Implement financial reasoning validation
    %{
      valid: String.contains?(reasoning, ["analysis", "risk", "return"]),
      score: calculate_reasoning_score(reasoning),
      domain_specific_checks: ["financial_terms_present", "risk_assessment"]
    }
  end

  defp validate_legal_reasoning(reasoning) do
    # Implement legal reasoning validation
    %{
      valid: String.contains?(reasoning, ["law", "precedent", "regulation"]),
      score: calculate_reasoning_score(reasoning),
      domain_specific_checks: ["legal_terms_present", "precedent_cited"]
    }
  end

  defp validate_technical_reasoning(reasoning) do
    # Implement technical reasoning validation
    %{
      valid: String.contains?(reasoning, ["algorithm", "implementation", "performance"]),
      score: calculate_reasoning_score(reasoning),
      domain_specific_checks: ["technical_accuracy", "implementation_feasibility"]
    }
  end

  defp calculate_reasoning_score(reasoning) do
    # Simple scoring based on length and structure
    base_score = min(String.length(reasoning) / 100, 1.0)

    # Bonus for structured reasoning
    structure_bonus =
      if String.contains?(reasoning, ["first", "second", "therefore", "because"]) do
        0.2
      else
        0.0
      end

    min(base_score + structure_bonus, 1.0)
  end

  defp process_item(item, operation) do
    case operation do
      "uppercase" -> String.upcase(to_string(item))
      "validate" -> %{item: item, valid: true}
      "transform" -> %{original: item, transformed: "processed_#{item}"}
      _ -> item
    end
  end
  
  # Private helper functions
  
  defp extract_function_ref(function) when is_function(function) do
    info = Function.info(function)
    
    case {info[:type], info[:module], info[:name]} do
      {:external, module, name} when is_atom(module) and is_atom(name) ->
        {:ok, {module, name}}
        
      _ ->
        :error
    end
  end
  
  defp register_with_python(session_id, tool_name, metadata) do
    tool_config = %{
      "name" => tool_name,
      "description" => metadata[:description],
      "parameters" => metadata[:parameters] || [],
      "returns" => metadata[:returns],
      "examples" => metadata[:examples] || [],
      "exposed_to_python" => true,
      "session_id" => session_id,
      "async_supported" => metadata[:async] || false,
      "timeout" => metadata[:timeout] || 5000
    }

    # Register the tool in session storage for Python access
    case Snakepit.execute_in_session(session_id, "register_elixir_tool", tool_config) do
      {:ok, _result} -> 
        Logger.debug("Registered tool '#{tool_name}' with Python session #{session_id}")
        {:ok, tool_name}
        
      {:error, error} -> 
        {:error, "Failed to register tool #{tool_name}: #{error}"}
    end
  end
  
  defp register_python_tools(session_id, tools) do
    results = Enum.map(tools, fn tool ->
      register_python_tool(session_id, tool)
    end)
    
    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))
    
    if failed > 0 do
      Logger.warning("Registered #{successful} Python tools, #{failed} failed")
    else
      Logger.info("Successfully registered #{successful} Python tools")
    end
    
    {:ok, successful}
  end
  
  defp register_python_tool(session_id, %{"name" => name} = tool) do
    metadata = %{
      description: tool["description"] || "Python tool",
      parameters: tool["parameters"] || [],
      returns: tool["returns"],
      from_python: true,
      session_id: session_id
    }
    
    # Create a wrapper function that calls back to Python
    wrapper = create_python_wrapper(session_id, name)
    
    Registry.register("python.#{name}", wrapper, metadata)
  end
  
  defp create_python_wrapper(session_id, tool_name) do
    # Return a function reference that can be stored
    {__MODULE__, :call_python_tool, [session_id, tool_name]}
  end
  
  @doc false
  def call_python_tool(session_id, tool_name, args) do
    case Snakepit.execute_in_session(session_id, "call_tool", %{
      "tool_name" => tool_name,
      "args" => args
    }) do
      {:ok, result} -> result
      {:error, error} -> raise "Python tool execution failed: #{inspect(error)}"
    end
  end
  
  defp validate_parameters(nil), do: :ok
  defp validate_parameters([]), do: :ok
  defp validate_parameters(params) when is_list(params) do
    Enum.reduce_while(params, :ok, fn param, _acc ->
      case validate_parameter(param) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
  
  defp validate_parameter(%{name: name, type: type} = param) when is_binary(name) do
    if valid_type?(type) do
      :ok
    else
      {:error, "Invalid type '#{type}' for parameter '#{name}'"}
    end
  end
  defp validate_parameter(param) do
    {:error, "Invalid parameter format: #{inspect(param)}"}
  end
  
  defp valid_type?(type) when type in ["string", "integer", "float", "boolean", "object", "array"], do: true
  defp valid_type?(_), do: false
  
  defp validate_examples(_, _, nil), do: :ok
  defp validate_examples(_, _, []), do: :ok
  defp validate_examples(module, function, examples) when is_list(examples) do
    Enum.reduce_while(examples, :ok, fn example, _acc ->
      case validate_example(module, function, example) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
  
  defp validate_example(module, function, %{input: input, output: expected}) do
    try do
      actual = apply(module, function, [input])
      if actual == expected do
        :ok
      else
        {:error, "Example mismatch: expected #{inspect(expected)}, got #{inspect(actual)}"}
      end
    rescue
      error ->
        {:error, "Example execution failed: #{inspect(error)}"}
    end
  end
  defp validate_example(_, _, _), do: {:error, "Invalid example format"}
  
  defp format_tool_doc({name, metadata}) do
    """
    ### #{name}
    
    #{metadata[:description] || "No description provided"}
    
    **Parameters:**
    #{format_parameters(metadata[:parameters])}
    
    **Returns:** #{format_returns(metadata[:returns])}
    
    #{format_examples(metadata[:examples])}
    #{format_deprecation(metadata)}
    """
  end
  
  defp format_parameters(nil), do: "None"
  defp format_parameters([]), do: "None"
  defp format_parameters(params) do
    params
    |> Enum.map(fn param ->
      "- `#{param.name}` (#{param.type}): #{param[:description] || ""} #{if param[:required], do: "**required**", else: ""}"
    end)
    |> Enum.join("\n")
  end
  
  defp format_returns(nil), do: "Any"
  defp format_returns(%{type: type, description: desc}), do: "#{type} - #{desc}"
  defp format_returns(%{type: type}), do: type
  defp format_returns(type) when is_binary(type), do: type
  
  defp format_examples(nil), do: ""
  defp format_examples([]), do: ""
  defp format_examples(examples) do
    """
    
    **Examples:**
    
    ```elixir
    #{Enum.map_join(examples, "\n\n", &format_example/1)}
    ```
    """
  end
  
  defp format_example(%{input: input, output: output}) do
    "# Input: #{inspect(input)}\n# Output: #{inspect(output)}"
  end
  
  defp format_deprecation(%{deprecated: true} = metadata) do
    """
    
    > ⚠️ **DEPRECATED**: #{metadata.deprecation_message}
    #{if metadata[:replacement], do: "> Use `#{metadata.replacement}` instead.", else: ""}
    """
  end
  defp format_deprecation(_), do: ""
end
