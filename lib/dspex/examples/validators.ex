defmodule DSPex.Examples.Validators do
  @moduledoc """
  Business logic validators that can be called from Python.
  
  These demonstrate how Elixir can provide domain-specific validation
  that enhances AI-generated content with business rules and constraints.
  """
  
  @doc """
  Validates that reasoning has enough steps and follows logical structure.
  """
  def validate_reasoning(%{"reasoning" => reasoning} = args) do
    min_steps = Map.get(args, "min_steps", 3)
    
    steps = count_reasoning_steps(reasoning)
    has_structure = has_logical_structure?(reasoning)
    has_conclusion = String.contains?(reasoning, ["therefore", "thus", "in conclusion"])
    
    steps >= min_steps and has_structure and has_conclusion
  end
  
  @doc """
  Checks if a conclusion logically follows from the reasoning.
  """
  def validate_conclusion(%{"reasoning" => reasoning, "conclusion" => conclusion}) do
    # Extract key points from reasoning
    key_points = extract_key_points(reasoning)
    
    # Check if conclusion references key points
    conclusion_words = String.downcase(conclusion) |> String.split()
    
    referenced_points = Enum.count(key_points, fn point ->
      point_words = String.downcase(point) |> String.split()
      Enum.any?(point_words, &(&1 in conclusion_words))
    end)
    
    # At least half of key points should be referenced
    referenced_points >= length(key_points) / 2
  end
  
  @doc """
  Scores reasoning quality on a scale of 0.0 to 1.0.
  """
  def score_reasoning(%{"reasoning" => reasoning}) do
    scores = [
      length_score(reasoning),
      structure_score(reasoning),
      clarity_score(reasoning),
      evidence_score(reasoning)
    ]
    
    # Return average score
    Enum.sum(scores) / length(scores)
  end
  
  @doc """
  Domain-specific validation for medical reasoning.
  """
  def validate_medical_reasoning(%{"reasoning" => reasoning} = args) do
    required_elements = [
      "symptoms",
      "diagnosis", 
      "treatment",
      "evidence",
      "differential"
    ]
    
    # Check for required medical elements
    has_elements = Enum.all?(required_elements, fn element ->
      String.contains?(String.downcase(reasoning), element)
    end)
    
    # Check for medical terminology
    has_medical_terms = contains_medical_terms?(reasoning)
    
    # Validate against medical rules if provided
    passes_rules = case Map.get(args, "rules") do
      nil -> true
      rules -> validate_against_medical_rules(reasoning, rules)
    end
    
    has_elements and has_medical_terms and passes_rules
  end
  
  # Private helper functions
  
  defp count_reasoning_steps(reasoning) do
    reasoning
    |> String.split(~r/\n+/)
    |> Enum.count(fn line ->
      Regex.match?(~r/^(First|Second|Third|Next|Then|Finally|Therefore)/i, line)
    end)
  end
  
  defp has_logical_structure?(reasoning) do
    # Check for introduction, body, and conclusion markers
    has_intro = Regex.match?(~r/(To answer|Let's consider|We need to)/i, reasoning)
    has_body = Regex.match?(~r/(First|Second|Additionally|Furthermore)/i, reasoning)
    has_conclusion = Regex.match?(~r/(Therefore|Thus|In conclusion|So)/i, reasoning)
    
    has_intro and has_body and has_conclusion
  end
  
  defp extract_key_points(reasoning) do
    reasoning
    |> String.split(~r/[.!?]/)
    |> Enum.filter(fn sentence ->
      # Key points often contain these markers
      Regex.match?(~r/(important|key|main|primary|essential|critical)/i, sentence)
    end)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
  
  defp length_score(reasoning) do
    word_count = reasoning |> String.split() |> length()
    
    cond do
      word_count < 50 -> 0.2
      word_count < 100 -> 0.5
      word_count < 200 -> 0.8
      true -> 1.0
    end
  end
  
  defp structure_score(reasoning) do
    markers = [
      ~r/^First/im,
      ~r/^Second/im,
      ~r/^(Therefore|Thus|In conclusion)/im
    ]
    
    matched = Enum.count(markers, &Regex.match?(&1, reasoning))
    matched / length(markers)
  end
  
  defp clarity_score(reasoning) do
    # Simple clarity check: average sentence length
    sentences = String.split(reasoning, ~r/[.!?]/)
    word_counts = Enum.map(sentences, &length(String.split(&1)))
    avg_length = Enum.sum(word_counts) / length(sentences)
    
    cond do
      avg_length < 10 -> 0.5  # Too short
      avg_length < 25 -> 1.0  # Good
      avg_length < 40 -> 0.7  # Getting long
      true -> 0.4             # Too long
    end
  end
  
  defp evidence_score(reasoning) do
    evidence_markers = [
      "because",
      "since",
      "evidence",
      "research",
      "studies",
      "data",
      "according to",
      "based on"
    ]
    
    found = Enum.count(evidence_markers, fn marker ->
      String.contains?(String.downcase(reasoning), marker)
    end)
    
    min(found / 3, 1.0)  # Expect at least 3 evidence markers
  end
  
  defp contains_medical_terms?(text) do
    medical_terms = [
      "diagnosis",
      "symptoms",
      "treatment",
      "patient",
      "clinical",
      "therapy",
      "medication",
      "prognosis"
    ]
    
    found = Enum.count(medical_terms, fn term ->
      String.contains?(String.downcase(text), term)
    end)
    
    found >= 3  # At least 3 medical terms
  end
  
  defp validate_against_medical_rules(reasoning, rules) do
    # This would implement specific medical rule validation
    # For demo purposes, we'll do a simple check
    Enum.all?(rules, fn {rule_type, rule_value} ->
      case rule_type do
        "required_sections" ->
          Enum.all?(rule_value, &String.contains?(reasoning, &1))
          
        "forbidden_terms" ->
          not Enum.any?(rule_value, &String.contains?(reasoning, &1))
          
        _ ->
          true
      end
    end)
  end
end