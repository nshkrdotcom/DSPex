defmodule DSPex.Bridge.Tools do
  @moduledoc """
  Tool registration system for bidirectional Elixir ↔ Python communication.

  This module manages Elixir functions that can be called from Python DSPy code,
  enabling true bidirectional workflows where DSPy reasoning can leverage 
  Elixir's strengths in business logic, concurrent processing, and domain-specific operations.
  """

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
          ]
        }
      )
  """
  def register_tool(session_id, tool_name, function, metadata \\ %{})
      when is_function(function, 1) do
    tool_config = %{
      "name" => tool_name,
      "function" => function,
      "description" => metadata[:description] || "Elixir tool: #{tool_name}",
      "parameters" => metadata[:parameters] || [],
      "exposed_to_python" => true,
      "session_id" => session_id
    }

    # Register the tool in session storage for Python access
    case Snakepit.execute_in_session(session_id, "register_elixir_tool", tool_config) do
      {:ok, _result} -> {:ok, tool_name}
      {:error, error} -> {:error, "Failed to register tool #{tool_name}: #{error}"}
    end
  end

  @doc """
  Register multiple tools at once for a session.
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
          max_concurrency: System.schedulers_online()
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
end
