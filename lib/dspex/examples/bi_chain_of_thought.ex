defmodule DSPex.Examples.BiChainOfThought do
  @moduledoc """
  Example of a bidirectional ChainOfThought wrapper that demonstrates
  the killer feature of DSPex: Python calling back into Elixir for
  business logic validation and context enrichment.
  
  This module shows how to:
  1. Use contract-based wrapping for type safety
  2. Expose Elixir tools to Python
  3. Implement real business logic integration
  4. Handle validation and context fetching
  """
  
  use DSPex.Bridge.ContractBased
  use DSPex.Bridge.Bidirectional
  
  alias DSPex.Examples.{Validators, ContextProvider}
  require Logger
  
  # Use the ChainOfThought contract
  use_contract DSPex.Contracts.ChainOfThought
  
  @impl DSPex.Bridge.Bidirectional
  def elixir_tools do
    [
      # Validation tools
      {"validate_reasoning", &Validators.validate_reasoning/1, %{
        description: "Validates that reasoning has enough steps and follows logical flow",
        parameters: [
          %{name: "reasoning", type: "string", required: true},
          %{name: "min_steps", type: "integer", required: false}
        ],
        returns: %{type: "boolean", description: "True if reasoning is valid"}
      }},
      
      {"validate_conclusion", &Validators.validate_conclusion/1, %{
        description: "Checks if conclusion logically follows from reasoning",
        parameters: [
          %{name: "reasoning", type: "string", required: true},
          %{name: "conclusion", type: "string", required: true}
        ],
        returns: %{type: "boolean", description: "True if conclusion is valid"}
      }},
      
      {"score_reasoning", &Validators.score_reasoning/1, %{
        description: "Returns a quality score for the reasoning",
        parameters: [
          %{name: "reasoning", type: "string", required: true}
        ],
        returns: %{type: "float", description: "Score between 0.0 and 1.0"}
      }},
      
      # Context tools
      {"fetch_examples", &ContextProvider.fetch_examples/1, %{
        description: "Fetches relevant examples for the given topic",
        parameters: [
          %{name: "topic", type: "string", required: true},
          %{name: "limit", type: "integer", required: false}
        ],
        returns: %{type: "array", description: "List of relevant examples"}
      }},
      
      {"fetch_rules", &ContextProvider.fetch_rules/1, %{
        description: "Fetches business rules for the domain",
        parameters: [
          %{name: "domain", type: "string", required: true}
        ],
        returns: %{type: "object", description: "Domain-specific rules"}
      }},
      
      # Enhancement tools
      {"improve_reasoning", &improve_reasoning/1, %{
        description: "Suggests improvements to reasoning based on business rules",
        parameters: [
          %{name: "reasoning", type: "string", required: true},
          %{name: "domain", type: "string", required: false}
        ],
        returns: %{type: "object", description: "Improved reasoning and suggestions"}
      }}
    ]
  end
  
  @impl DSPex.Bridge.Bidirectional
  def on_python_callback(tool_name, args, context) do
    Logger.info("Python called tool: #{tool_name}", 
      session_id: context.session_id,
      args: args
    )
    
    # Could add access control, rate limiting, etc. here
    :ok
  end
  
  @doc """
  Improves reasoning by applying business rules and best practices.
  
  This demonstrates how Elixir can enhance Python's AI-generated content
  with domain-specific knowledge.
  """
  def improve_reasoning(%{"reasoning" => reasoning} = args) do
    domain = Map.get(args, "domain", "general")
    
    # Analyze current reasoning
    steps = parse_reasoning_steps(reasoning)
    score = Validators.score_reasoning(%{"reasoning" => reasoning})
    
    # Get domain rules
    {:ok, rules} = ContextProvider.fetch_rules(%{"domain" => domain})
    
    # Apply improvements
    improvements = suggest_improvements(steps, rules, score)
    
    %{
      "original_score" => score,
      "improved_reasoning" => apply_improvements(reasoning, improvements),
      "suggestions" => improvements,
      "rules_applied" => Enum.map(improvements, & &1.rule)
    }
  end
  
  # Private functions
  
  defp parse_reasoning_steps(reasoning) do
    reasoning
    |> String.split(~r/\n+/)
    |> Enum.filter(&String.contains?(&1, ["First", "Second", "Then", "Therefore", "Because"]))
    |> Enum.with_index(1)
    |> Enum.map(fn {step, idx} -> %{number: idx, content: step} end)
  end
  
  defp suggest_improvements(steps, rules, current_score) do
    improvements = []
    
    # Check for minimum steps
    improvements = if length(steps) < rules["min_reasoning_steps"] do
      [%{
        type: :add_steps,
        rule: "minimum_steps",
        suggestion: "Add more detailed reasoning steps",
        priority: :high
      } | improvements]
    else
      improvements
    end
    
    # Check for required keywords
    improvements = if missing_keywords = check_missing_keywords(steps, rules["required_keywords"]) do
      [%{
        type: :add_keywords,
        rule: "required_keywords",
        suggestion: "Include keywords: #{Enum.join(missing_keywords, ", ")}",
        keywords: missing_keywords,
        priority: :medium
      } | improvements]
    else
      improvements
    end
    
    # Check logical flow
    improvements = if not logical_flow?(steps) do
      [%{
        type: :improve_flow,
        rule: "logical_flow",
        suggestion: "Improve logical connections between steps",
        priority: :high
      } | improvements]
    else
      improvements
    end
    
    improvements
  end
  
  defp check_missing_keywords(steps, required_keywords) when is_list(required_keywords) do
    all_text = steps |> Enum.map(& &1.content) |> Enum.join(" ")
    
    missing = Enum.filter(required_keywords, fn keyword ->
      not String.contains?(String.downcase(all_text), String.downcase(keyword))
    end)
    
    if missing == [], do: nil, else: missing
  end
  defp check_missing_keywords(_, _), do: nil
  
  defp logical_flow?(steps) do
    # Simple check for logical connectors
    connectors = ["therefore", "because", "since", "thus", "hence"]
    
    steps
    |> Enum.map(& &1.content)
    |> Enum.any?(fn step ->
      Enum.any?(connectors, &String.contains?(String.downcase(step), &1))
    end)
  end
  
  defp apply_improvements(reasoning, improvements) do
    # This is a simplified version - in reality you might use
    # more sophisticated text processing
    Enum.reduce(improvements, reasoning, fn improvement, acc ->
      case improvement.type do
        :add_steps ->
          acc <> "\n\nAdditionally, we should consider more detailed analysis of each factor."
          
        :add_keywords ->
          keywords_text = Enum.join(improvement.keywords, " and ")
          acc <> "\n\nThis reasoning takes into account #{keywords_text}."
          
        :improve_flow ->
          # Add logical connectors
          acc
          |> String.replace("Second,", "Furthermore,")
          |> String.replace("Third,", "Therefore,")
          
        _ ->
          acc
      end
    end)
  end
end