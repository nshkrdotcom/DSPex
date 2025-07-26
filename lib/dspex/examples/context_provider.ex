defmodule DSPex.Examples.ContextProvider do
  @moduledoc """
  Provides context and examples that Python can request during reasoning.
  
  This demonstrates how Elixir can serve as a knowledge base and rule engine
  that enhances AI reasoning with domain-specific information.
  """
  
  @doc """
  Fetches relevant examples for a given topic.
  """
  def fetch_examples(%{"topic" => topic} = args) do
    limit = Map.get(args, "limit", 3)
    
    examples = get_examples_for_topic(topic)
    |> Enum.take(limit)
    |> Enum.map(&format_example/1)
    
    {:ok, examples}
  end
  
  @doc """
  Fetches business rules for a specific domain.
  """
  def fetch_rules(%{"domain" => domain}) do
    rules = case domain do
      "medical" -> medical_rules()
      "financial" -> financial_rules()
      "legal" -> legal_rules()
      "technical" -> technical_rules()
      _ -> general_rules()
    end
    
    {:ok, rules}
  end
  
  @doc """
  Provides contextual hints based on the question type.
  """
  def get_reasoning_hints(%{"question" => question} = args) do
    question_type = Map.get(args, "type", classify_question(question))
    
    hints = case question_type do
      "analytical" -> analytical_hints()
      "comparative" -> comparative_hints()
      "causal" -> causal_hints()
      "evaluative" -> evaluative_hints()
      _ -> general_hints()
    end
    
    %{
      "question_type" => question_type,
      "hints" => hints,
      "suggested_structure" => suggest_structure(question_type)
    }
  end
  
  # Private functions - Examples database
  
  defp get_examples_for_topic("medical") do
    [
      %{
        question: "What are the symptoms of diabetes?",
        reasoning: """
        First, let's understand that diabetes is a metabolic disorder affecting blood sugar regulation.
        
        Second, the symptoms vary between Type 1 and Type 2 diabetes, though they share common features.
        
        Common symptoms include:
        - Frequent urination (polyuria) due to excess glucose in blood
        - Increased thirst (polydipsia) as the body tries to compensate for fluid loss
        - Unexplained weight loss, particularly in Type 1 diabetes
        - Fatigue due to cells not getting enough glucose
        - Blurred vision from fluid changes in the eye
        
        Therefore, diabetes symptoms primarily result from high blood glucose affecting multiple body systems.
        """,
        answer: "The main symptoms of diabetes include frequent urination, excessive thirst, unexplained weight loss, fatigue, and blurred vision."
      },
      %{
        question: "How do vaccines work?",
        reasoning: """
        First, vaccines introduce a harmless form of a pathogen to the immune system.
        
        Second, this exposure triggers an immune response without causing the actual disease.
        
        The immune system then:
        - Recognizes the foreign antigens
        - Produces antibodies specific to those antigens
        - Creates memory cells that remember the pathogen
        
        Therefore, when exposed to the real pathogen later, the immune system can quickly recognize and neutralize it.
        """,
        answer: "Vaccines work by training the immune system to recognize and fight specific pathogens through controlled exposure to harmless versions of the disease-causing agent."
      }
    ]
  end
  
  defp get_examples_for_topic("technical") do
    [
      %{
        question: "How does a binary search algorithm work?",
        reasoning: """
        First, binary search requires a sorted array as input.
        
        Second, it works by repeatedly dividing the search space in half:
        1. Compare the target with the middle element
        2. If equal, the search is complete
        3. If target is smaller, search the left half
        4. If target is larger, search the right half
        
        This process continues until the element is found or the search space is empty.
        
        Therefore, binary search achieves O(log n) time complexity by eliminating half of the remaining elements in each step.
        """,
        answer: "Binary search efficiently finds elements in sorted arrays by repeatedly dividing the search space in half, achieving O(log n) time complexity."
      }
    ]
  end
  
  defp get_examples_for_topic(_) do
    # Default examples for general topics
    [
      %{
        question: "What causes climate change?",
        reasoning: """
        First, climate change is primarily driven by increased greenhouse gases in the atmosphere.
        
        Second, human activities are the main source:
        - Burning fossil fuels releases CO2
        - Deforestation reduces CO2 absorption
        - Industrial processes emit various greenhouse gases
        
        These gases trap heat in the atmosphere, leading to global temperature rise.
        
        Therefore, climate change is caused by human activities that increase atmospheric greenhouse gas concentrations.
        """,
        answer: "Climate change is primarily caused by human activities that increase greenhouse gases in the atmosphere, particularly through fossil fuel combustion and deforestation."
      }
    ]
  end
  
  defp format_example(example) do
    %{
      "question" => example.question,
      "reasoning" => example.reasoning,
      "answer" => example.answer,
      "quality_score" => 0.9  # In real system, this would be calculated
    }
  end
  
  # Domain-specific rules
  
  defp medical_rules do
    %{
      "min_reasoning_steps" => 3,
      "required_keywords" => ["symptoms", "diagnosis", "treatment", "patient"],
      "required_sections" => ["clinical presentation", "differential diagnosis", "management"],
      "citation_required" => true,
      "evidence_based" => true,
      "contraindications_check" => true
    }
  end
  
  defp financial_rules do
    %{
      "min_reasoning_steps" => 4,
      "required_keywords" => ["risk", "return", "analysis", "market"],
      "required_sections" => ["market analysis", "risk assessment", "recommendations"],
      "disclaimer_required" => true,
      "regulatory_compliance" => true,
      "quantitative_analysis" => true
    }
  end
  
  defp legal_rules do
    %{
      "min_reasoning_steps" => 5,
      "required_keywords" => ["law", "statute", "precedent", "jurisdiction"],
      "required_sections" => ["legal framework", "case analysis", "conclusion"],
      "citation_format" => "bluebook",
      "jurisdiction_specific" => true,
      "precedent_required" => true
    }
  end
  
  defp technical_rules do
    %{
      "min_reasoning_steps" => 3,
      "required_keywords" => ["algorithm", "complexity", "implementation", "performance"],
      "required_sections" => ["problem analysis", "solution approach", "complexity analysis"],
      "code_examples" => true,
      "big_o_notation" => true,
      "edge_cases" => true
    }
  end
  
  defp general_rules do
    %{
      "min_reasoning_steps" => 2,
      "required_keywords" => [],
      "required_sections" => ["analysis", "conclusion"],
      "evidence_preferred" => true,
      "logical_flow" => true
    }
  end
  
  # Question classification
  
  defp classify_question(question) do
    cond do
      String.contains?(question, ["compare", "difference", "versus", "vs"]) -> "comparative"
      String.contains?(question, ["why", "cause", "reason", "because"]) -> "causal"
      String.contains?(question, ["evaluate", "assess", "judge", "best"]) -> "evaluative"
      String.contains?(question, ["analyze", "explain", "how", "what"]) -> "analytical"
      true -> "general"
    end
  end
  
  # Reasoning hints
  
  defp analytical_hints do
    [
      "Break down the topic into component parts",
      "Examine relationships between elements",
      "Consider multiple perspectives",
      "Use specific examples to illustrate points"
    ]
  end
  
  defp comparative_hints do
    [
      "Identify key similarities and differences",
      "Use consistent criteria for comparison",
      "Consider context and conditions",
      "Conclude with meaningful insights"
    ]
  end
  
  defp causal_hints do
    [
      "Identify direct and indirect causes",
      "Consider temporal relationships",
      "Distinguish correlation from causation",
      "Address potential confounding factors"
    ]
  end
  
  defp evaluative_hints do
    [
      "Establish clear evaluation criteria",
      "Consider pros and cons",
      "Weigh evidence objectively",
      "Justify your assessment"
    ]
  end
  
  defp general_hints do
    [
      "Start with a clear thesis",
      "Support claims with evidence",
      "Address counterarguments",
      "End with a strong conclusion"
    ]
  end
  
  defp suggest_structure(question_type) do
    case question_type do
      "analytical" ->
        ["Introduction", "Component Analysis", "Relationships", "Examples", "Conclusion"]
        
      "comparative" ->
        ["Introduction", "Criteria", "Similarities", "Differences", "Evaluation", "Conclusion"]
        
      "causal" ->
        ["Introduction", "Direct Causes", "Indirect Factors", "Evidence", "Alternative Explanations", "Conclusion"]
        
      "evaluative" ->
        ["Introduction", "Criteria", "Strengths", "Weaknesses", "Overall Assessment", "Recommendations"]
        
      _ ->
        ["Introduction", "Main Points", "Supporting Evidence", "Conclusion"]
    end
  end
end