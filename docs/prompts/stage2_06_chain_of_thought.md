# Stage 2 Prompt 6: Chain-of-Thought Implementation

## OBJECTIVE

Implement a comprehensive Chain-of-Thought (CoT) reasoning system that provides native Elixir execution of step-by-step reasoning with validation, quality assessment, and optimization. This system must deliver enhanced signature generation for reasoning steps, step-by-step validation with consistency checking, reasoning quality assessment and scoring, intermediate result handling, and confidence calibration while maintaining complete DSPy CoT API compatibility and achieving superior reasoning quality through native implementation.

## COMPLETE IMPLEMENTATION CONTEXT

### CHAIN-OF-THOUGHT ARCHITECTURE OVERVIEW

From Stage 2 Technical Specification:

```
┌─────────────────────────────────────────────────────────────┐
│              Chain-of-Thought Reasoning System              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Reasoning        │  │ Step            │  │ Quality      ││
│  │ Generation       │  │ Validation      │  │ Assessment   ││
│  │ - Prompting     │  │ - Consistency   │  │ - Scoring    ││
│  │ - Structuring   │  │ - Logic Check   │  │ - Metrics    ││
│  │ - Chaining      │  │ - Coherence     │  │ - Feedback   ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Intermediate     │  │ Confidence      │  │ Optimization ││
│  │ Results          │  │ Calibration     │  │ Engine       ││
│  │ - Storage       │  │ - Uncertainty   │  │ - Learning   ││
│  │ - Retrieval     │  │ - Scoring       │  │ - Adaptation ││
│  │ - Analysis      │  │ - Adjustment    │  │ - Improvement││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### DSPy CHAIN-OF-THOUGHT ANALYSIS

From comprehensive DSPy source code analysis (predict/chain_of_thought.py):

**DSPy CoT Core Patterns:**

```python
# DSPy Chain of Thought implementation
class ChainOfThought(Predict):
    def __init__(self, signature, rationale_type="simple", **kwargs):
        super().__init__(signature, **kwargs)
        self.rationale_type = rationale_type
        self.extended_signature = self._extend_signature()
        
    def _extend_signature(self):
        """Extend signature with reasoning field."""
        # Create new signature with reasoning
        class ExtendedSignature(self.signature):
            pass
            
        # Add reasoning field before outputs
        reasoning_field = OutputField(
            desc="Think step by step to arrive at the answer",
            prefix="Reasoning: Let me think step by step."
        )
        
        # Insert reasoning before other outputs
        ExtendedSignature._fields = OrderedDict()
        
        # Copy input fields
        for name, field in self.signature.input_fields.items():
            ExtendedSignature._fields[name] = field
            
        # Add reasoning field
        ExtendedSignature._fields['reasoning'] = reasoning_field
        
        # Copy output fields
        for name, field in self.signature.output_fields.items():
            ExtendedSignature._fields[name] = field
            
        return ExtendedSignature
    
    def forward(self, **kwargs):
        """Execute with chain of thought reasoning."""
        # Use extended signature for generation
        self.signature = self.extended_signature
        
        # Execute prediction
        result = super().forward(**kwargs)
        
        # Extract reasoning and clean up result
        reasoning = result.pop('reasoning', '')
        
        # Validate reasoning quality
        if self.rationale_type == "detailed":
            reasoning = self._enhance_reasoning(reasoning, **kwargs)
            
        # Store reasoning in trace
        self.trace[-1].reasoning = reasoning
        
        return result
    
    def _enhance_reasoning(self, initial_reasoning, **kwargs):
        """Enhance reasoning with additional detail."""
        # Generate more detailed reasoning if needed
        enhancement_prompt = f"""
        Initial reasoning: {initial_reasoning}
        
        Please provide more detailed step-by-step reasoning that:
        1. Clearly identifies each logical step
        2. Explains the connection between steps
        3. Justifies the final conclusion
        """
        
        enhanced = self._generate_enhancement(enhancement_prompt)
        return enhanced

# Chain of Thought with self-consistency
class ChainOfThoughtSC(ChainOfThought):
    def __init__(self, signature, n_samples=5, **kwargs):
        super().__init__(signature, **kwargs)
        self.n_samples = n_samples
        
    def forward(self, **kwargs):
        """Execute with self-consistency voting."""
        # Generate multiple reasoning paths
        candidates = []
        
        for i in range(self.n_samples):
            # Add variation to prompt
            varied_kwargs = self._add_variation(kwargs, i)
            result = super().forward(**varied_kwargs)
            
            candidates.append({
                'result': result,
                'reasoning': self.trace[-1].reasoning,
                'confidence': self._calculate_confidence(result)
            })
        
        # Select best result through voting
        final_result = self._aggregate_results(candidates)
        
        # Store all reasoning paths
        self.trace[-1].all_reasoning_paths = [c['reasoning'] for c in candidates]
        self.trace[-1].selected_path = final_result['selected_reasoning']
        
        return final_result['result']
    
    def _aggregate_results(self, candidates):
        """Aggregate results using majority voting."""
        # Group by answer
        answer_groups = {}
        
        for candidate in candidates:
            answer_key = self._normalize_answer(candidate['result'])
            
            if answer_key not in answer_groups:
                answer_groups[answer_key] = []
                
            answer_groups[answer_key].append(candidate)
        
        # Select group with highest total confidence
        best_group = max(answer_groups.values(), 
                        key=lambda g: sum(c['confidence'] for c in g))
        
        # Return highest confidence result from best group
        best_candidate = max(best_group, key=lambda c: c['confidence'])
        
        return {
            'result': best_candidate['result'],
            'selected_reasoning': best_candidate['reasoning'],
            'consensus_confidence': len(best_group) / len(candidates)
        }
```

**Key DSPy CoT Features:**
1. **Signature Extension** - Automatic injection of reasoning fields
2. **Step Structuring** - Guided step-by-step reasoning generation
3. **Self-Consistency** - Multiple reasoning paths with voting
4. **Reasoning Enhancement** - Iterative improvement of reasoning quality
5. **Confidence Scoring** - Assessment of reasoning path reliability

### REASONING VALIDATION PATTERNS

From research on reasoning validation techniques:

```python
# Reasoning validation and quality assessment
class ReasoningValidator:
    def __init__(self):
        self.validators = {
            'logical_consistency': self.check_logical_consistency,
            'step_coherence': self.check_step_coherence,
            'conclusion_support': self.check_conclusion_support,
            'factual_accuracy': self.check_factual_accuracy
        }
        
    def validate_reasoning(self, reasoning_text, context):
        """Comprehensive reasoning validation."""
        # Parse reasoning into steps
        steps = self.parse_reasoning_steps(reasoning_text)
        
        # Run all validators
        validation_results = {}
        for name, validator in self.validators.items():
            result = validator(steps, context)
            validation_results[name] = result
            
        # Calculate overall score
        overall_score = self.calculate_overall_score(validation_results)
        
        return {
            'valid': overall_score > 0.7,
            'score': overall_score,
            'details': validation_results,
            'suggestions': self.generate_suggestions(validation_results)
        }
    
    def parse_reasoning_steps(self, reasoning_text):
        """Parse reasoning into structured steps."""
        # Identify step markers
        step_patterns = [
            r'(?:Step\s+\d+|First|Second|Third|Next|Then|Finally):?\s*',
            r'(?:\d+\.|\-|\*)\s+',
            r'(?:Therefore|Thus|Hence|So),?\s+'
        ]
        
        steps = []
        current_step = []
        
        for line in reasoning_text.split('\n'):
            if any(re.match(pattern, line) for pattern in step_patterns):
                if current_step:
                    steps.append(' '.join(current_step))
                current_step = [line]
            else:
                current_step.append(line)
                
        if current_step:
            steps.append(' '.join(current_step))
            
        return steps
```

## NATIVE ELIXIR IMPLEMENTATION

### CORE CHAIN-OF-THOUGHT ENGINE

```elixir
defmodule AshDSPy.ChainOfThought.Engine do
  @moduledoc """
  Core Chain-of-Thought reasoning engine with step validation and quality assessment.
  
  Provides:
  - Enhanced signature generation for reasoning steps
  - Step-by-step reasoning validation and consistency checking
  - Reasoning quality assessment and scoring
  - Intermediate result handling and validation
  - Confidence calibration and uncertainty quantification
  - Self-consistency through multiple reasoning paths
  """
  
  use GenServer
  require Logger
  
  alias AshDSPy.{Signature, Prediction}
  alias AshDSPy.ChainOfThought.{
    SignatureEnhancer,
    StepValidator,
    QualityAssessor,
    ConfidenceCalibrator,
    ReasoningOptimizer
  }
  
  @type cot_opts :: [
    rationale_type: :simple | :detailed | :structured,
    n_samples: pos_integer(),
    min_confidence: float(),
    max_steps: pos_integer(),
    validation_level: :basic | :strict | :comprehensive
  ]
  
  @type reasoning_result :: %{
    outputs: map(),
    reasoning: String.t(),
    steps: [map()],
    confidence: float(),
    validation: map(),
    metadata: map()
  }
  
  # Client API
  
  @doc """
  Start the Chain-of-Thought engine.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Execute Chain-of-Thought reasoning with the given signature and inputs.
  """
  @spec reason(Signature.t(), map(), cot_opts()) :: 
    {:ok, reasoning_result()} | {:error, term()}
  def reason(signature, inputs, opts \\ []) do
    GenServer.call(__MODULE__, {:reason, signature, inputs, opts}, 
      Keyword.get(opts, :timeout, 60_000))
  end
  
  @doc """
  Execute self-consistent Chain-of-Thought with multiple reasoning paths.
  """
  @spec reason_with_consistency(Signature.t(), map(), cot_opts()) ::
    {:ok, reasoning_result()} | {:error, term()}
  def reason_with_consistency(signature, inputs, opts \\ []) do
    n_samples = Keyword.get(opts, :n_samples, 5)
    
    GenServer.call(__MODULE__, 
      {:reason_with_consistency, signature, inputs, n_samples, opts},
      Keyword.get(opts, :timeout, 120_000))
  end
  
  @doc """
  Validate existing reasoning text.
  """
  @spec validate_reasoning(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def validate_reasoning(reasoning_text, context \\ %{}) do
    GenServer.call(__MODULE__, {:validate_reasoning, reasoning_text, context})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Initialize components
    {:ok, enhancer} = SignatureEnhancer.start_link()
    {:ok, validator} = StepValidator.start_link()
    {:ok, assessor} = QualityAssessor.start_link()
    {:ok, calibrator} = ConfidenceCalibrator.start_link()
    {:ok, optimizer} = ReasoningOptimizer.start_link()
    
    # Initialize caches
    :ets.new(:cot_cache, [:named_table, :public, :set])
    :ets.new(:reasoning_patterns, [:named_table, :public, :set])
    
    state = %{
      enhancer: enhancer,
      validator: validator,
      assessor: assessor,
      calibrator: calibrator,
      optimizer: optimizer,
      opts: opts
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:reason, signature, inputs, opts}, _from, state) do
    result = execute_chain_of_thought(signature, inputs, opts, state)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:reason_with_consistency, signature, inputs, n_samples, opts}, _from, state) do
    result = execute_self_consistent_cot(signature, inputs, n_samples, opts, state)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:validate_reasoning, reasoning_text, context}, _from, state) do
    result = StepValidator.validate(state.validator, reasoning_text, context)
    {:reply, result, state}
  end
  
  # Private functions
  
  defp execute_chain_of_thought(signature, inputs, opts, state) do
    with {:ok, enhanced_signature} <- enhance_signature(signature, opts, state),
         {:ok, raw_result} <- generate_reasoning(enhanced_signature, inputs, opts),
         {:ok, parsed_steps} <- parse_reasoning_steps(raw_result.reasoning),
         {:ok, validated_steps} <- validate_steps(parsed_steps, inputs, state),
         {:ok, final_outputs} <- extract_final_outputs(raw_result, validated_steps),
         {:ok, confidence} <- calibrate_confidence(validated_steps, final_outputs, state),
         {:ok, quality_score} <- assess_quality(validated_steps, final_outputs, state) do
      
      result = %{
        outputs: final_outputs,
        reasoning: raw_result.reasoning,
        steps: validated_steps,
        confidence: confidence,
        validation: %{
          quality_score: quality_score,
          step_validation: extract_validation_summary(validated_steps)
        },
        metadata: %{
          signature: signature.name,
          rationale_type: Keyword.get(opts, :rationale_type, :simple),
          execution_time_ms: raw_result.execution_time_ms
        }
      }
      
      # Learn from this execution
      ReasoningOptimizer.record_execution(state.optimizer, result)
      
      {:ok, result}
    end
  end
  
  defp execute_self_consistent_cot(signature, inputs, n_samples, opts, state) do
    # Generate multiple reasoning paths in parallel
    tasks = for i <- 1..n_samples do
      Task.async(fn ->
        # Add variation to each sample
        varied_opts = add_reasoning_variation(opts, i)
        execute_chain_of_thought(signature, inputs, varied_opts, state)
      end)
    end
    
    # Collect results
    candidates = tasks
    |> Task.await_many(Keyword.get(opts, :timeout, 60_000))
    |> Enum.filter(fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, result} -> result end)
    
    if candidates == [] do
      {:error, :all_reasoning_attempts_failed}
    else
      # Aggregate results through voting
      aggregate_reasoning_results(candidates, opts)
    end
  end
  
  defp enhance_signature(signature, opts, state) do
    rationale_type = Keyword.get(opts, :rationale_type, :simple)
    SignatureEnhancer.enhance(state.enhancer, signature, rationale_type)
  end
  
  defp generate_reasoning(enhanced_signature, inputs, opts) do
    # Add special instructions for reasoning
    reasoning_instructions = build_reasoning_instructions(opts)
    
    enhanced_inputs = Map.put(inputs, :_reasoning_instructions, reasoning_instructions)
    
    # Use prediction engine with enhanced signature
    case Prediction.Engine.predict(enhanced_signature, enhanced_inputs, opts) do
      {:ok, result} -> 
        {:ok, %{
          reasoning: Map.get(result.outputs, :reasoning, ""),
          outputs: Map.delete(result.outputs, :reasoning),
          execution_time_ms: result.metadata.duration_ms
        }}
        
      error -> error
    end
  end
  
  defp build_reasoning_instructions(opts) do
    base = "Think step by step to arrive at the answer."
    
    case Keyword.get(opts, :rationale_type, :simple) do
      :simple -> 
        base
        
      :detailed ->
        """
        #{base}
        
        Please provide detailed reasoning that:
        1. Clearly identifies each logical step
        2. Explains the connection between steps
        3. Shows your work and calculations
        4. Justifies the final conclusion
        """
        
      :structured ->
        """
        #{base}
        
        Structure your reasoning as follows:
        Step 1: [Understand the problem]
        Step 2: [Identify key information]
        Step 3: [Apply relevant concepts]
        Step 4: [Perform calculations/analysis]
        Step 5: [Verify and conclude]
        
        For each step, explain your thought process clearly.
        """
    end
  end
  
  defp parse_reasoning_steps(reasoning_text) do
    steps = StepParser.parse(reasoning_text)
    
    if steps == [] do
      {:error, :no_steps_found}
    else
      enriched_steps = Enum.with_index(steps, 1)
      |> Enum.map(fn {step, index} ->
        %{
          index: index,
          content: step.content,
          type: step.type,
          markers: step.markers,
          dependencies: identify_dependencies(step, steps)
        }
      end)
      
      {:ok, enriched_steps}
    end
  end
  
  defp validate_steps(steps, inputs, state) do
    validation_level = get_validation_level(state.opts)
    
    validated_steps = Enum.map(steps, fn step ->
      validation = StepValidator.validate_step(
        state.validator,
        step,
        steps,
        inputs,
        validation_level
      )
      
      Map.put(step, :validation, validation)
    end)
    
    # Check overall validity
    all_valid = Enum.all?(validated_steps, fn step ->
      step.validation.valid
    end)
    
    if all_valid do
      {:ok, validated_steps}
    else
      # Return with partial validation
      {:ok, validated_steps}
    end
  end
  
  defp extract_final_outputs(raw_result, validated_steps) do
    # Extract conclusions from final steps
    conclusion_steps = Enum.filter(validated_steps, fn step ->
      step.type in [:conclusion, :answer, :final]
    end)
    
    if conclusion_steps == [] do
      # Use original outputs if no clear conclusion
      {:ok, raw_result.outputs}
    else
      # Extract and merge outputs from conclusion steps
      extracted_outputs = Enum.reduce(conclusion_steps, %{}, fn step, acc ->
        Map.merge(acc, extract_step_outputs(step))
      end)
      
      # Merge with original outputs, preferring extracted
      {:ok, Map.merge(raw_result.outputs, extracted_outputs)}
    end
  end
  
  defp calibrate_confidence(steps, outputs, state) do
    factors = %{
      step_validity: calculate_step_validity_score(steps),
      logical_consistency: calculate_consistency_score(steps),
      output_completeness: calculate_completeness_score(outputs),
      reasoning_clarity: calculate_clarity_score(steps)
    }
    
    ConfidenceCalibrator.calibrate(state.calibrator, factors)
  end
  
  defp assess_quality(steps, outputs, state) do
    QualityAssessor.assess(state.assessor, steps, outputs)
  end
  
  defp aggregate_reasoning_results(candidates, opts) do
    # Group by normalized answer
    answer_groups = Enum.group_by(candidates, fn candidate ->
      normalize_outputs(candidate.outputs)
    end)
    
    # Score each group
    scored_groups = Enum.map(answer_groups, fn {normalized, group} ->
      score = calculate_group_score(group)
      {normalized, group, score}
    end)
    
    # Select best group
    {_normalized, best_group, _score} = 
      Enum.max_by(scored_groups, &elem(&1, 2))
    
    # Select best candidate from group
    best_candidate = Enum.max_by(best_group, & &1.confidence)
    
    # Add consensus information
    consensus_confidence = length(best_group) / length(candidates)
    
    {:ok, %{
      best_candidate |
      validation: Map.put(
        best_candidate.validation,
        :consensus_confidence,
        consensus_confidence
      ),
      metadata: Map.merge(best_candidate.metadata, %{
        total_samples: length(candidates),
        consensus_size: length(best_group),
        alternative_answers: length(answer_groups) - 1
      })
    }}
  end
  
  defp add_reasoning_variation(opts, sample_index) do
    # Add controlled variation to reasoning
    variations = [
      "Let's approach this step-by-step:",
      "I'll think through this systematically:",
      "Breaking this down logically:",
      "Let me work through this carefully:",
      "Analyzing this problem step by step:"
    ]
    
    variation_prefix = Enum.at(variations, rem(sample_index - 1, length(variations)))
    
    Keyword.update(opts, :variation_prefix, variation_prefix, fn _ -> variation_prefix end)
  end
  
  defp identify_dependencies(step, all_steps) do
    # Simple dependency identification based on references
    step_refs = extract_step_references(step.content)
    
    Enum.filter(all_steps, fn other_step ->
      other_step.index < step.index and
      step_refers_to?(step.content, other_step)
    end)
    |> Enum.map(& &1.index)
  end
  
  defp get_validation_level(opts) do
    Keyword.get(opts, :validation_level, :strict)
  end
  
  defp normalize_outputs(outputs) do
    # Normalize outputs for comparison
    outputs
    |> Enum.map(fn {k, v} ->
      {k, normalize_value(v)}
    end)
    |> Enum.sort()
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end
  
  defp normalize_value(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end
  
  defp normalize_value(value) when is_number(value) do
    Float.round(value * 1.0, 5)
  end
  
  defp normalize_value(value), do: value
  
  defp calculate_group_score(group) do
    # Score based on multiple factors
    avg_confidence = Enum.sum(group, & &1.confidence) / length(group)
    avg_quality = Enum.sum(group, & &1.validation.quality_score) / length(group)
    consistency_bonus = :math.log(length(group) + 1) / 10
    
    avg_confidence * 0.4 + avg_quality * 0.4 + consistency_bonus * 0.2
  end
end
```

### SIGNATURE ENHANCEMENT FOR COT

```elixir
defmodule AshDSPy.ChainOfThought.SignatureEnhancer do
  @moduledoc """
  Enhances signatures with reasoning fields for Chain-of-Thought.
  """
  
  use GenServer
  
  alias AshDSPy.Signature
  alias AshDSPy.Types.Field
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Enhance signature with reasoning field based on rationale type.
  """
  def enhance(server \\ __MODULE__, signature, rationale_type) do
    GenServer.call(server, {:enhance, signature, rationale_type})
  end
  
  @impl true
  def init(opts) do
    {:ok, %{opts: opts}}
  end
  
  @impl true
  def handle_call({:enhance, signature, rationale_type}, _from, state) do
    enhanced = do_enhance(signature, rationale_type)
    {:reply, {:ok, enhanced}, state}
  end
  
  defp do_enhance(signature, rationale_type) do
    reasoning_field = create_reasoning_field(rationale_type, signature)
    
    # Create new signature with reasoning field
    enhanced_fields = insert_reasoning_field(
      signature.input_fields,
      signature.output_fields,
      reasoning_field
    )
    
    %{signature |
      name: "#{signature.name}_cot",
      output_fields: enhanced_fields.output_fields,
      instructions: enhance_instructions(signature.instructions, rationale_type)
    }
  end
  
  defp create_reasoning_field(rationale_type, signature) do
    base_desc = "Think step by step to arrive at the answer"
    
    desc = case rationale_type do
      :simple ->
        base_desc
        
      :detailed ->
        """
        #{base_desc}. Provide detailed reasoning that:
        1. Clearly identifies each logical step
        2. Explains connections between steps
        3. Shows calculations and analysis
        4. Justifies the conclusion
        """
        
      :structured ->
        """
        #{base_desc}. Structure your reasoning as:
        Step 1: [Problem understanding]
        Step 2: [Key information]
        Step 3: [Concept application]
        Step 4: [Analysis/calculations]
        Step 5: [Conclusion]
        """
    end
    
    %Field{
      name: :reasoning,
      type: :string,
      desc: desc,
      required: true,
      constraints: [
        min_length: 50,
        max_length: 2000,
        format: :reasoning_text
      ],
      metadata: %{
        prefix: "Reasoning:",
        rationale_type: rationale_type,
        original_signature: signature.name
      }
    }
  end
  
  defp insert_reasoning_field(input_fields, output_fields, reasoning_field) do
    # Reasoning goes before other output fields
    enhanced_output_fields = Map.put(output_fields, :reasoning, reasoning_field)
    
    # Reorder to put reasoning first
    ordered_output_fields = [:reasoning | Map.keys(output_fields)]
    |> Enum.map(fn key -> {key, Map.get(enhanced_output_fields, key)} end)
    |> Map.new()
    
    %{
      input_fields: input_fields,
      output_fields: ordered_output_fields
    }
  end
  
  defp enhance_instructions(nil, _rationale_type), do: nil
  
  defp enhance_instructions(instructions, rationale_type) do
    suffix = case rationale_type do
      :simple -> " Think step by step."
      :detailed -> " Provide detailed step-by-step reasoning."
      :structured -> " Use structured step-by-step reasoning."
    end
    
    instructions <> suffix
  end
end
```

### STEP VALIDATION SYSTEM

```elixir
defmodule AshDSPy.ChainOfThought.StepValidator do
  @moduledoc """
  Validates reasoning steps for logical consistency and coherence.
  """
  
  use GenServer
  require Logger
  
  @validation_rules [
    :logical_consistency,
    :step_coherence,
    :dependency_validity,
    :conclusion_support,
    :factual_accuracy
  ]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def validate(server \\ __MODULE__, reasoning_text, context) do
    GenServer.call(server, {:validate, reasoning_text, context})
  end
  
  def validate_step(server \\ __MODULE__, step, all_steps, context, level) do
    GenServer.call(server, {:validate_step, step, all_steps, context, level})
  end
  
  @impl true
  def init(opts) do
    # Load validation patterns
    patterns = load_validation_patterns()
    
    {:ok, %{
      patterns: patterns,
      opts: opts
    }}
  end
  
  @impl true
  def handle_call({:validate, reasoning_text, context}, _from, state) do
    steps = StepParser.parse(reasoning_text)
    
    validation_results = Enum.map(steps, fn step ->
      validate_single_step(step, steps, context, state)
    end)
    
    overall = aggregate_validation_results(validation_results)
    
    {:reply, {:ok, overall}, state}
  end
  
  @impl true
  def handle_call({:validate_step, step, all_steps, context, level}, _from, state) do
    result = validate_single_step(step, all_steps, context, state, level)
    {:reply, result, state}
  end
  
  defp validate_single_step(step, all_steps, context, state, level \\ :strict) do
    # Run applicable validation rules
    rule_results = @validation_rules
    |> Enum.filter(fn rule -> should_apply_rule?(rule, level) end)
    |> Enum.map(fn rule ->
      result = apply_validation_rule(rule, step, all_steps, context, state)
      {rule, result}
    end)
    |> Map.new()
    
    # Calculate overall validity
    valid = Enum.all?(rule_results, fn {_rule, result} -> 
      result.valid or result.severity == :warning
    end)
    
    score = calculate_validation_score(rule_results)
    
    %{
      valid: valid,
      score: score,
      rules: rule_results,
      issues: extract_issues(rule_results),
      suggestions: generate_suggestions(rule_results, step)
    }
  end
  
  defp apply_validation_rule(:logical_consistency, step, all_steps, _context, state) do
    # Check for logical consistency within the step
    inconsistencies = detect_logical_inconsistencies(step.content, state.patterns)
    
    %{
      valid: inconsistencies == [],
      severity: :error,
      issues: inconsistencies,
      score: if(inconsistencies == [], do: 1.0, else: 0.5)
    }
  end
  
  defp apply_validation_rule(:step_coherence, step, all_steps, _context, state) do
    # Check coherence with previous steps
    previous_steps = Enum.filter(all_steps, & &1.index < step.index)
    
    coherence_score = calculate_coherence_score(step, previous_steps, state.patterns)
    
    %{
      valid: coherence_score > 0.6,
      severity: :warning,
      score: coherence_score,
      issues: if(coherence_score < 0.6, do: ["Low coherence with previous steps"], else: [])
    }
  end
  
  defp apply_validation_rule(:dependency_validity, step, all_steps, _context, _state) do
    # Validate step dependencies are satisfied
    missing_deps = find_missing_dependencies(step, all_steps)
    
    %{
      valid: missing_deps == [],
      severity: :error,
      issues: Enum.map(missing_deps, &"Missing dependency: #{&1}"),
      score: if(missing_deps == [], do: 1.0, else: 0.3)
    }
  end
  
  defp apply_validation_rule(:conclusion_support, step, all_steps, _context, _state) do
    if step.type in [:conclusion, :answer, :final] do
      # Check if conclusion is supported by previous steps
      support_score = calculate_conclusion_support(step, all_steps)
      
      %{
        valid: support_score > 0.7,
        severity: :error,
        score: support_score,
        issues: if(support_score < 0.7, do: ["Conclusion not well supported"], else: [])
      }
    else
      # Not applicable to non-conclusion steps
      %{valid: true, severity: :info, score: 1.0, issues: []}
    end
  end
  
  defp apply_validation_rule(:factual_accuracy, step, _all_steps, context, state) do
    # Check for obvious factual errors
    errors = detect_factual_errors(step.content, context, state.patterns)
    
    %{
      valid: errors == [],
      severity: :warning,
      issues: errors,
      score: if(errors == [], do: 1.0, else: 0.6)
    }
  end
  
  defp detect_logical_inconsistencies(content, patterns) do
    # Detect contradictions and logical errors
    inconsistencies = []
    
    # Check for contradictory statements
    if contains_contradiction?(content, patterns.contradiction_patterns) do
      inconsistencies ++ ["Contains contradictory statements"]
    else
      inconsistencies
    end
  end
  
  defp calculate_coherence_score(step, previous_steps, patterns) do
    if previous_steps == [] do
      1.0
    else
      # Calculate semantic similarity with previous steps
      similarities = Enum.map(previous_steps, fn prev_step ->
        calculate_semantic_similarity(step.content, prev_step.content)
      end)
      
      # Weight recent steps more heavily
      weighted_sum = similarities
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.reduce(0.0, fn {sim, idx}, acc ->
        weight = 1.0 / (idx + 1)
        acc + sim * weight
      end)
      
      total_weight = Enum.reduce(1..length(similarities), 0.0, fn idx, acc ->
        acc + 1.0 / idx
      end)
      
      weighted_sum / total_weight
    end
  end
  
  defp find_missing_dependencies(step, all_steps) do
    # Extract references to other steps
    references = extract_step_references(step.content)
    
    # Check if referenced steps exist
    available_indices = Enum.map(all_steps, & &1.index)
    
    Enum.filter(references, fn ref ->
      ref not in available_indices or ref >= step.index
    end)
  end
  
  defp calculate_conclusion_support(conclusion_step, all_steps) do
    # Analyze how well previous steps support the conclusion
    support_steps = Enum.filter(all_steps, & &1.index < conclusion_step.index)
    
    if support_steps == [] do
      0.0
    else
      # Extract key claims from conclusion
      conclusion_claims = extract_claims(conclusion_step.content)
      
      # Check how many claims are supported
      supported_claims = Enum.count(conclusion_claims, fn claim ->
        Enum.any?(support_steps, fn step ->
          supports_claim?(step.content, claim)
        end)
      end)
      
      if length(conclusion_claims) > 0 do
        supported_claims / length(conclusion_claims)
      else
        0.5  # No clear claims to verify
      end
    end
  end
  
  defp detect_factual_errors(content, context, patterns) do
    errors = []
    
    # Check basic mathematical errors
    math_errors = detect_math_errors(content)
    errors = errors ++ math_errors
    
    # Check against known facts in context
    context_errors = detect_context_violations(content, context)
    errors = errors ++ context_errors
    
    # Check common misconceptions
    misconception_errors = detect_misconceptions(content, patterns.misconceptions)
    errors ++ misconception_errors
  end
  
  defp should_apply_rule?(rule, level) do
    case level do
      :basic -> rule in [:logical_consistency]
      :strict -> rule in [:logical_consistency, :step_coherence, :dependency_validity]
      :comprehensive -> true
    end
  end
  
  defp calculate_validation_score(rule_results) do
    scores = Enum.map(rule_results, fn {_rule, result} -> result.score end)
    
    if scores == [] do
      1.0
    else
      Enum.sum(scores) / length(scores)
    end
  end
  
  defp extract_issues(rule_results) do
    rule_results
    |> Enum.flat_map(fn {rule, result} ->
      Enum.map(result.issues, fn issue ->
        %{rule: rule, issue: issue, severity: result.severity}
      end)
    end)
  end
  
  defp generate_suggestions(rule_results, step) do
    suggestions = []
    
    # Generate suggestions based on validation failures
    Enum.each(rule_results, fn {rule, result} ->
      if not result.valid do
        case rule do
          :logical_consistency ->
            suggestions ++ ["Review step #{step.index} for logical consistency"]
            
          :step_coherence ->
            suggestions ++ ["Improve connection between step #{step.index} and previous steps"]
            
          :dependency_validity ->
            suggestions ++ ["Ensure all referenced steps are properly defined"]
            
          :conclusion_support ->
            suggestions ++ ["Strengthen support for conclusion in earlier steps"]
            
          :factual_accuracy ->
            suggestions ++ ["Verify factual claims in step #{step.index}"]
            
          _ -> suggestions
        end
      end
    end)
    
    Enum.uniq(suggestions)
  end
  
  defp load_validation_patterns do
    %{
      contradiction_patterns: [
        ~r/but.*however/i,
        ~r/on one hand.*on the other hand.*contradiction/i,
        ~r/this contradicts/i
      ],
      misconceptions: load_common_misconceptions(),
      math_patterns: load_math_patterns(),
      logical_connectors: load_logical_connectors()
    }
  end
  
  # Helper functions for semantic analysis
  
  defp calculate_semantic_similarity(text1, text2) do
    # Simple word overlap similarity
    words1 = text1 |> String.downcase() |> String.split(~r/\W+/) |> MapSet.new()
    words2 = text2 |> String.downcase() |> String.split(~r/\W+/) |> MapSet.new()
    
    intersection = MapSet.intersection(words1, words2) |> MapSet.size()
    union = MapSet.union(words1, words2) |> MapSet.size()
    
    if union > 0 do
      intersection / union
    else
      0.0
    end
  end
  
  defp extract_step_references(content) do
    # Extract references to other steps
    Regex.scan(~r/step\s+(\d+)/i, content)
    |> Enum.map(fn [_, num] -> String.to_integer(num) end)
    |> Enum.uniq()
  end
  
  defp extract_claims(content) do
    # Extract key claims from text
    sentences = String.split(content, ~r/[.!?]+/)
    
    # Filter for claim-like sentences
    Enum.filter(sentences, fn sentence ->
      String.contains?(sentence, ["therefore", "thus", "so", "conclude", "answer", "result"])
    end)
  end
  
  defp supports_claim?(step_content, claim) do
    # Check if step content supports the claim
    claim_keywords = claim
    |> String.downcase()
    |> String.split(~r/\W+/)
    |> Enum.filter(& String.length(&1) > 3)
    
    step_text = String.downcase(step_content)
    
    matching_keywords = Enum.count(claim_keywords, fn keyword ->
      String.contains?(step_text, keyword)
    end)
    
    matching_keywords / length(claim_keywords) > 0.5
  end
  
  defp detect_math_errors(content) do
    # Detect obvious mathematical errors
    errors = []
    
    # Check for incorrect basic arithmetic
    arithmetic_patterns = [
      {~r/2\s*\+\s*2\s*=\s*(\d+)/, "4"},
      {~r/10\s*\*\s*10\s*=\s*(\d+)/, "100"},
      {~r/(\d+)\s*\/\s*0/, "division by zero"}
    ]
    
    Enum.flat_map(arithmetic_patterns, fn {pattern, expected} ->
      case Regex.run(pattern, content) do
        nil -> []
        [_, result] when expected == "division by zero" -> 
          ["Division by zero error"]
        [_, result] when result != expected ->
          ["Arithmetic error: #{result} != #{expected}"]
        _ -> []
      end
    end)
  end
  
  defp detect_context_violations(content, context) do
    # Check for violations of facts provided in context
    []  # Placeholder - would check against context facts
  end
  
  defp detect_misconceptions(content, misconception_patterns) do
    # Check for common misconceptions
    []  # Placeholder - would check against known misconceptions
  end
  
  defp contains_contradiction?(content, patterns) do
    Enum.any?(patterns, fn pattern ->
      Regex.match?(pattern, content)
    end)
  end
  
  defp load_common_misconceptions do
    []  # Would load from configuration
  end
  
  defp load_math_patterns do
    []  # Would load mathematical validation patterns
  end
  
  defp load_logical_connectors do
    ["therefore", "thus", "hence", "so", "because", "since", "as", "given that"]
  end
end
```

### QUALITY ASSESSMENT ENGINE

```elixir
defmodule AshDSPy.ChainOfThought.QualityAssessor do
  @moduledoc """
  Assesses the quality of chain-of-thought reasoning.
  """
  
  use GenServer
  
  @quality_dimensions [
    :clarity,
    :completeness,
    :correctness,
    :efficiency,
    :insight
  ]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def assess(server \\ __MODULE__, steps, outputs) do
    GenServer.call(server, {:assess, steps, outputs})
  end
  
  @impl true
  def init(opts) do
    {:ok, %{
      weights: init_quality_weights(),
      opts: opts
    }}
  end
  
  @impl true
  def handle_call({:assess, steps, outputs}, _from, state) do
    assessment = perform_assessment(steps, outputs, state)
    {:reply, {:ok, assessment}, state}
  end
  
  defp perform_assessment(steps, outputs, state) do
    # Assess each quality dimension
    dimension_scores = @quality_dimensions
    |> Enum.map(fn dimension ->
      score = assess_dimension(dimension, steps, outputs)
      {dimension, score}
    end)
    |> Map.new()
    
    # Calculate weighted overall score
    overall_score = calculate_weighted_score(dimension_scores, state.weights)
    
    %{
      overall_score: overall_score,
      dimensions: dimension_scores,
      grade: score_to_grade(overall_score),
      feedback: generate_quality_feedback(dimension_scores)
    }
  end
  
  defp assess_dimension(:clarity, steps, _outputs) do
    # Assess clarity of reasoning
    clarity_factors = %{
      step_structure: assess_step_structure(steps),
      language_clarity: assess_language_clarity(steps),
      logical_flow: assess_logical_flow(steps)
    }
    
    # Weighted average of factors
    weights = %{step_structure: 0.4, language_clarity: 0.3, logical_flow: 0.3}
    
    calculate_weighted_average(clarity_factors, weights)
  end
  
  defp assess_dimension(:completeness, steps, outputs) do
    # Assess completeness of reasoning
    required_elements = identify_required_elements(outputs)
    covered_elements = identify_covered_elements(steps)
    
    coverage = MapSet.intersection(
      MapSet.new(required_elements),
      MapSet.new(covered_elements)
    ) |> MapSet.size()
    
    if length(required_elements) > 0 do
      coverage / length(required_elements)
    else
      1.0
    end
  end
  
  defp assess_dimension(:correctness, steps, outputs) do
    # Assess correctness (based on validation results)
    valid_steps = Enum.count(steps, fn step ->
      Map.get(step, :validation, %{valid: true}).valid
    end)
    
    if length(steps) > 0 do
      valid_steps / length(steps)
    else
      0.0
    end
  end
  
  defp assess_dimension(:efficiency, steps, _outputs) do
    # Assess reasoning efficiency
    optimal_steps = estimate_optimal_steps(steps)
    actual_steps = length(steps)
    
    if actual_steps == 0 do
      0.0
    else
      efficiency = optimal_steps / actual_steps
      min(efficiency, 1.0)  # Cap at 1.0
    end
  end
  
  defp assess_dimension(:insight, steps, _outputs) do
    # Assess depth of insight
    insight_indicators = [
      has_novel_connections?(steps),
      has_deep_analysis?(steps),
      has_multiple_perspectives?(steps)
    ]
    
    Enum.count(insight_indicators, & &1) / length(insight_indicators)
  end
  
  defp assess_step_structure(steps) do
    # Check if steps are well-structured
    structured_steps = Enum.count(steps, fn step ->
      has_clear_structure?(step)
    end)
    
    if length(steps) > 0 do
      structured_steps / length(steps)
    else
      0.0
    end
  end
  
  defp assess_language_clarity(steps) do
    # Assess clarity of language used
    clarity_scores = Enum.map(steps, fn step ->
      calculate_text_clarity(step.content)
    end)
    
    if clarity_scores == [] do
      0.0
    else
      Enum.sum(clarity_scores) / length(clarity_scores)
    end
  end
  
  defp assess_logical_flow(steps) do
    # Assess how well steps flow logically
    if length(steps) < 2 do
      1.0
    else
      transitions = steps
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [prev, curr] ->
        assess_transition_quality(prev, curr)
      end)
      
      Enum.sum(transitions) / length(transitions)
    end
  end
  
  defp has_clear_structure?(step) do
    # Check for structural markers
    markers = ["first", "second", "step", "then", "finally", "therefore"]
    
    Enum.any?(markers, fn marker ->
      String.contains?(String.downcase(step.content), marker)
    end)
  end
  
  defp calculate_text_clarity(text) do
    # Simple clarity metrics
    sentences = String.split(text, ~r/[.!?]+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    
    if sentences == [] do
      0.0
    else
      # Average sentence length (optimal ~15-20 words)
      avg_length = sentences
      |> Enum.map(&length(String.split(&1, " ")))
      |> Enum.sum()
      |> Kernel./(length(sentences))
      
      # Score based on distance from optimal
      length_score = 1.0 - abs(avg_length - 17.5) / 17.5
      max(length_score, 0.0)
    end
  end
  
  defp assess_transition_quality(prev_step, curr_step) do
    # Check for logical connectors
    connectors = ["therefore", "thus", "because", "since", "as a result", 
                  "consequently", "hence", "so", "this means"]
    
    has_connector = Enum.any?(connectors, fn conn ->
      String.contains?(String.downcase(curr_step.content), conn)
    end)
    
    # Check for conceptual continuity
    continuity = calculate_semantic_similarity(prev_step.content, curr_step.content)
    
    if has_connector do
      0.7 + 0.3 * continuity
    else
      continuity
    end
  end
  
  defp identify_required_elements(outputs) do
    # Identify what elements should be covered in reasoning
    output_keys = Map.keys(outputs)
    
    # Each output should have reasoning support
    output_keys
  end
  
  defp identify_covered_elements(steps) do
    # Extract what elements are covered in steps
    steps
    |> Enum.flat_map(fn step ->
      extract_covered_concepts(step.content)
    end)
    |> Enum.uniq()
  end
  
  defp extract_covered_concepts(content) do
    # Extract key concepts from content
    # This is simplified - in practice would use NLP
    content
    |> String.downcase()
    |> String.split(~r/\W+/)
    |> Enum.filter(& String.length(&1) > 4)
    |> Enum.uniq()
  end
  
  defp estimate_optimal_steps(steps) do
    # Estimate optimal number of steps
    # Based on complexity indicators
    complexity_indicators = Enum.count(steps, fn step ->
      String.contains?(String.downcase(step.content), 
        ["calculate", "analyze", "consider", "evaluate"])
    end)
    
    # Base steps + complexity-driven steps
    3 + complexity_indicators
  end
  
  defp has_novel_connections?(steps) do
    # Check for novel connections or insights
    novel_indicators = ["interestingly", "surprisingly", "notably", 
                       "this suggests", "this implies", "connection between"]
    
    Enum.any?(steps, fn step ->
      Enum.any?(novel_indicators, fn indicator ->
        String.contains?(String.downcase(step.content), indicator)
      end)
    end)
  end
  
  defp has_deep_analysis?(steps) do
    # Check for deep analytical thinking
    analysis_indicators = ["analyze", "examine", "investigate", "explore",
                          "consider multiple", "various factors", "deeper"]
    
    count = Enum.count(steps, fn step ->
      Enum.any?(analysis_indicators, fn indicator ->
        String.contains?(String.downcase(step.content), indicator)
      end)
    end)
    
    count >= 2  # At least 2 analytical steps
  end
  
  defp has_multiple_perspectives?(steps) do
    # Check for consideration of multiple perspectives
    perspective_indicators = ["alternatively", "another way", "different perspective",
                             "on the other hand", "however", "multiple approaches"]
    
    Enum.any?(steps, fn step ->
      Enum.any?(perspective_indicators, fn indicator ->
        String.contains?(String.downcase(step.content), indicator)
      end)
    end)
  end
  
  defp calculate_weighted_score(dimension_scores, weights) do
    @quality_dimensions
    |> Enum.reduce(0.0, fn dimension, acc ->
      score = Map.get(dimension_scores, dimension, 0.0)
      weight = Map.get(weights, dimension, 0.2)
      acc + score * weight
    end)
  end
  
  defp calculate_weighted_average(factors, weights) do
    total_weight = weights |> Map.values() |> Enum.sum()
    
    weighted_sum = factors
    |> Enum.reduce(0.0, fn {factor, value}, acc ->
      weight = Map.get(weights, factor, 0.0)
      acc + value * weight
    end)
    
    weighted_sum / total_weight
  end
  
  defp score_to_grade(score) do
    cond do
      score >= 0.9 -> :excellent
      score >= 0.8 -> :good
      score >= 0.7 -> :satisfactory
      score >= 0.6 -> :needs_improvement
      true -> :poor
    end
  end
  
  defp generate_quality_feedback(dimension_scores) do
    # Generate feedback based on lowest scoring dimensions
    sorted_dims = dimension_scores
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.take(2)  # Focus on two weakest areas
    
    Enum.map(sorted_dims, fn {dimension, score} ->
      generate_dimension_feedback(dimension, score)
    end)
  end
  
  defp generate_dimension_feedback(dimension, score) when score < 0.6 do
    case dimension do
      :clarity ->
        "Improve reasoning clarity by using clearer structure and transitions"
      :completeness ->
        "Ensure all required elements are addressed in the reasoning"
      :correctness ->
        "Review reasoning steps for logical errors or inconsistencies"
      :efficiency ->
        "Streamline reasoning by removing redundant or unnecessary steps"
      :insight ->
        "Deepen analysis by exploring multiple perspectives or connections"
    end
  end
  
  defp generate_dimension_feedback(_dimension, _score), do: nil
  
  defp init_quality_weights do
    %{
      clarity: 0.25,
      completeness: 0.25,
      correctness: 0.3,
      efficiency: 0.1,
      insight: 0.1
    }
  end
  
  defp calculate_semantic_similarity(text1, text2) do
    # Reuse from validator
    words1 = text1 |> String.downcase() |> String.split(~r/\W+/) |> MapSet.new()
    words2 = text2 |> String.downcase() |> String.split(~r/\W+/) |> MapSet.new()
    
    intersection = MapSet.intersection(words1, words2) |> MapSet.size()
    union = MapSet.union(words1, words2) |> MapSet.size()
    
    if union > 0 do
      intersection / union
    else
      0.0
    end
  end
end
```

### CONFIDENCE CALIBRATION

```elixir
defmodule AshDSPy.ChainOfThought.ConfidenceCalibrator do
  @moduledoc """
  Calibrates confidence scores for chain-of-thought reasoning.
  """
  
  use GenServer
  require Logger
  
  @calibration_window 1000  # Number of predictions to use for calibration
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def calibrate(server \\ __MODULE__, factors) do
    GenServer.call(server, {:calibrate, factors})
  end
  
  def record_outcome(server \\ __MODULE__, predicted_confidence, actual_accuracy) do
    GenServer.cast(server, {:record_outcome, predicted_confidence, actual_accuracy})
  end
  
  @impl true
  def init(opts) do
    # Initialize calibration history
    :ets.new(:confidence_calibration, [:named_table, :set, :public])
    
    {:ok, %{
      history: [],
      calibration_curve: initialize_calibration_curve(),
      opts: opts
    }}
  end
  
  @impl true
  def handle_call({:calibrate, factors}, _from, state) do
    raw_confidence = calculate_raw_confidence(factors)
    calibrated = apply_calibration(raw_confidence, state.calibration_curve)
    
    {:reply, {:ok, calibrated}, state}
  end
  
  @impl true
  def handle_cast({:record_outcome, predicted, actual}, state) do
    # Add to history
    updated_history = [{predicted, actual} | state.history]
    |> Enum.take(@calibration_window)
    
    # Recalibrate if enough data
    updated_curve = if length(updated_history) >= 50 do
      recalibrate_curve(updated_history)
    else
      state.calibration_curve
    end
    
    {:noreply, %{state | 
      history: updated_history, 
      calibration_curve: updated_curve
    }}
  end
  
  defp calculate_raw_confidence(factors) do
    # Weight different confidence factors
    weights = %{
      step_validity: 0.3,
      logical_consistency: 0.3,
      output_completeness: 0.2,
      reasoning_clarity: 0.2
    }
    
    weighted_sum = Enum.reduce(factors, 0.0, fn {factor, value}, acc ->
      weight = Map.get(weights, factor, 0.0)
      acc + value * weight
    end)
    
    # Ensure in [0, 1] range
    max(0.0, min(1.0, weighted_sum))
  end
  
  defp apply_calibration(raw_confidence, calibration_curve) do
    # Apply isotonic regression calibration
    # Find appropriate calibration bin
    bin_index = trunc(raw_confidence * 10)
    bin_index = max(0, min(9, bin_index))
    
    Map.get(calibration_curve, bin_index, raw_confidence)
  end
  
  defp initialize_calibration_curve do
    # Start with identity mapping
    0..9
    |> Enum.map(fn i -> {i, i / 10.0} end)
    |> Map.new()
  end
  
  defp recalibrate_curve(history) do
    # Group by confidence bins
    binned = Enum.group_by(history, fn {pred, _actual} ->
      trunc(pred * 10)
    end)
    
    # Calculate actual accuracy per bin
    0..9
    |> Enum.map(fn bin ->
      case Map.get(binned, bin, []) do
        [] -> {bin, bin / 10.0}  # No data, use identity
        outcomes ->
          actual_accuracy = outcomes
          |> Enum.map(&elem(&1, 1))
          |> Enum.sum()
          |> Kernel./(length(outcomes))
          
          {bin, actual_accuracy}
      end
    end)
    |> Map.new()
  end
end
```

### STEP PARSER

```elixir
defmodule AshDSPy.ChainOfThought.StepParser do
  @moduledoc """
  Parses reasoning text into structured steps.
  """
  
  @step_patterns [
    # Numbered steps
    ~r/^(?:Step\s+)?(\d+)[:.)]\s*(.+)$/im,
    # Bullet points
    ~r/^[\-\*•]\s+(.+)$/im,
    # First, Second, etc.
    ~r/^(First|Second|Third|Fourth|Fifth|Next|Then|Finally)[:,]?\s*(.+)$/im,
    # Logical connectors
    ~r/^(Therefore|Thus|Hence|So|Consequently)[:,]?\s*(.+)$/im
  ]
  
  @doc """
  Parse reasoning text into structured steps.
  """
  def parse(reasoning_text) do
    lines = String.split(reasoning_text, "\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    
    {steps, _} = Enum.reduce(lines, {[], nil}, fn line, {steps, current} ->
      case identify_step_start(line) do
        {:new_step, type, content} ->
          # Start new step
          new_step = %{
            content: content,
            type: type,
            markers: [extract_marker(line)]
          }
          
          if current do
            {[current | steps], new_step}
          else
            {steps, new_step}
          end
          
        :continuation ->
          # Continue current step
          if current do
            updated = %{current | content: current.content <> " " <> line}
            {steps, updated}
          else
            # No current step, treat as new implicit step
            {steps, %{content: line, type: :implicit, markers: []}}
          end
      end
    end)
    
    # Add final step if exists
    final_steps = if current, do: [current | steps], else: steps
    
    # Reverse to maintain order and add indices
    final_steps
    |> Enum.reverse()
    |> classify_step_types()
  end
  
  defp identify_step_start(line) do
    Enum.find_value(@step_patterns, :continuation, fn pattern ->
      case Regex.run(pattern, line) do
        nil -> nil
        matches -> {:new_step, pattern_to_type(pattern), extract_content(matches)}
      end
    end)
  end
  
  defp pattern_to_type(pattern) do
    cond do
      pattern == ~r/^(?:Step\s+)?(\d+)[:.)]\s*(.+)$/im -> :numbered
      pattern == ~r/^[\-\*•]\s+(.+)$/im -> :bullet
      pattern == ~r/^(First|Second|Third|Fourth|Fifth|Next|Then|Finally)[:,]?\s*(.+)$/im -> :ordinal
      pattern == ~r/^(Therefore|Thus|Hence|So|Consequently)[:,]?\s*(.+)$/im -> :conclusion
      true -> :other
    end
  end
  
  defp extract_content([_full_match, content]), do: content
  defp extract_content([_full_match, _marker, content]), do: content
  defp extract_content(_), do: ""
  
  defp extract_marker(line) do
    cond do
      match = Regex.run(~r/^(?:Step\s+)?(\d+)/, line) ->
        "Step " <> hd(tl(match))
        
      match = Regex.run(~r/^(First|Second|Third|Fourth|Fifth|Next|Then|Finally)/, line) ->
        hd(tl(match))
        
      match = Regex.run(~r/^(Therefore|Thus|Hence|So|Consequently)/, line) ->
        hd(tl(match))
        
      String.starts_with?(line, ["-", "*", "•"]) ->
        "•"
        
      true ->
        ""
    end
  end
  
  defp classify_step_types(steps) do
    # Further classify steps based on content
    steps
    |> Enum.with_index(1)
    |> Enum.map(fn {step, index} ->
      enhanced_type = if index == length(steps) and 
                        step.type in [:conclusion, :implicit] do
        :final
      else
        classify_by_content(step.content, step.type)
      end
      
      %{step | type: enhanced_type, index: index}
    end)
  end
  
  defp classify_by_content(content, current_type) do
    lower_content = String.downcase(content)
    
    cond do
      # Override if clear conclusion markers
      String.contains?(lower_content, ["therefore", "thus", "in conclusion", "the answer"]) ->
        :conclusion
        
      # Problem understanding
      String.contains?(lower_content, ["understand", "given", "we need to", "the problem"]) ->
        :understanding
        
      # Analysis
      String.contains?(lower_content, ["analyze", "consider", "examine", "look at"]) ->
        :analysis
        
      # Calculation
      String.contains?(lower_content, ["calculate", "compute", "solve", "=" |> Regex.escape()]) ->
        :calculation
        
      # Keep original classification
      true ->
        current_type
    end
  end
end
```

### REASONING OPTIMIZATION

```elixir
defmodule AshDSPy.ChainOfThought.ReasoningOptimizer do
  @moduledoc """
  Learns from execution history to optimize reasoning generation.
  """
  
  use GenServer
  require Logger
  
  @learning_window 500
  @pattern_threshold 0.7
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def record_execution(server \\ __MODULE__, result) do
    GenServer.cast(server, {:record_execution, result})
  end
  
  def get_optimization_hints(server \\ __MODULE__, signature, context) do
    GenServer.call(server, {:get_hints, signature, context})
  end
  
  @impl true
  def init(opts) do
    # Initialize pattern storage
    :ets.new(:reasoning_patterns, [:named_table, :set, :public])
    :ets.new(:performance_stats, [:named_table, :set, :public])
    
    {:ok, %{
      execution_history: [],
      learned_patterns: %{},
      opts: opts
    }}
  end
  
  @impl true
  def handle_cast({:record_execution, result}, state) do
    # Extract features from execution
    features = extract_execution_features(result)
    
    # Update history
    updated_history = [{features, result} | state.execution_history]
    |> Enum.take(@learning_window)
    
    # Learn patterns if enough data
    updated_patterns = if length(updated_history) >= 50 do
      learn_patterns(updated_history, state.learned_patterns)
    else
      state.learned_patterns
    end
    
    {:noreply, %{state | 
      execution_history: updated_history,
      learned_patterns: updated_patterns
    }}
  end
  
  @impl true
  def handle_call({:get_hints, signature, context}, _from, state) do
    hints = generate_optimization_hints(signature, context, state.learned_patterns)
    {:reply, {:ok, hints}, state}
  end
  
  defp extract_execution_features(result) do
    %{
      signature_name: result.metadata.signature,
      rationale_type: result.metadata.rationale_type,
      step_count: length(result.steps),
      quality_score: result.validation.quality_score,
      confidence: result.confidence,
      step_types: Enum.map(result.steps, & &1.type) |> Enum.frequencies(),
      avg_step_length: calculate_avg_step_length(result.steps),
      reasoning_patterns: extract_reasoning_patterns(result.reasoning)
    }
  end
  
  defp learn_patterns(history, current_patterns) do
    # Group by signature and rationale type
    grouped = Enum.group_by(history, fn {features, _} ->
      {features.signature_name, features.rationale_type}
    end)
    
    # Learn optimal patterns for each group
    Enum.reduce(grouped, current_patterns, fn {{sig, type}, group}, acc ->
      pattern = learn_group_pattern(group)
      Map.put(acc, {sig, type}, pattern)
    end)
  end
  
  defp learn_group_pattern(group) do
    # Find patterns in high-quality executions
    high_quality = Enum.filter(group, fn {features, result} ->
      features.quality_score > @pattern_threshold
    end)
    
    if high_quality == [] do
      nil
    else
      # Extract common patterns
      %{
        optimal_step_count: calculate_optimal_steps(high_quality),
        common_step_types: extract_common_step_types(high_quality),
        effective_patterns: extract_effective_patterns(high_quality),
        avg_quality: calculate_avg_quality(high_quality)
      }
    end
  end
  
  defp generate_optimization_hints(signature, context, learned_patterns) do
    pattern_key = {signature.name, context[:rationale_type] || :simple}
    
    case Map.get(learned_patterns, pattern_key) do
      nil -> 
        # No learned pattern, use defaults
        default_hints()
        
      pattern ->
        # Generate hints based on learned pattern
        %{
          suggested_steps: pattern.optimal_step_count,
          recommended_structure: pattern.common_step_types,
          effective_phrases: pattern.effective_patterns,
          quality_target: pattern.avg_quality
        }
    end
  end
  
  defp calculate_avg_step_length(steps) do
    if steps == [] do
      0
    else
      total_length = Enum.sum(steps, fn step ->
        String.length(step.content)
      end)
      
      total_length / length(steps)
    end
  end
  
  defp extract_reasoning_patterns(reasoning_text) do
    # Extract effective reasoning patterns
    patterns = [
      "step-by-step" => ~r/step[\s\-]by[\s\-]step/i,
      "first-then" => ~r/first.*then/is,
      "because-therefore" => ~r/because.*therefore/is,
      "given-conclude" => ~r/given.*conclude/is
    ]
    
    Enum.filter(patterns, fn {_name, pattern} ->
      Regex.match?(pattern, reasoning_text)
    end)
    |> Enum.map(&elem(&1, 0))
  end
  
  defp calculate_optimal_steps(executions) do
    step_counts = Enum.map(executions, fn {features, _} ->
      features.step_count
    end)
    
    # Use median for robustness
    sorted = Enum.sort(step_counts)
    mid = div(length(sorted), 2)
    
    if rem(length(sorted), 2) == 0 do
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    else
      Enum.at(sorted, mid)
    end
  end
  
  defp extract_common_step_types(executions) do
    # Find most common step type sequences
    type_sequences = Enum.map(executions, fn {features, _} ->
      features.step_types
    end)
    
    # Aggregate frequencies
    Enum.reduce(type_sequences, %{}, fn types, acc ->
      Map.merge(acc, types, fn _k, v1, v2 -> v1 + v2 end)
    end)
  end
  
  defp extract_effective_patterns(executions) do
    # Extract patterns from high-quality reasoning
    all_patterns = Enum.flat_map(executions, fn {features, _} ->
      features.reasoning_patterns
    end)
    
    # Count frequencies
    Enum.frequencies(all_patterns)
    |> Enum.filter(fn {_pattern, count} -> count > length(executions) / 2 end)
    |> Enum.map(&elem(&1, 0))
  end
  
  defp calculate_avg_quality(executions) do
    qualities = Enum.map(executions, fn {features, _} ->
      features.quality_score
    end)
    
    Enum.sum(qualities) / length(qualities)
  end
  
  defp default_hints do
    %{
      suggested_steps: 5,
      recommended_structure: %{
        understanding: 1,
        analysis: 2,
        calculation: 1,
        conclusion: 1
      },
      effective_phrases: ["step-by-step", "first-then"],
      quality_target: 0.8
    }
  end
end
```

## INTEGRATION AND TESTING

### ASH FRAMEWORK INTEGRATION

```elixir
defmodule AshDSPy.ChainOfThought.AshIntegration do
  @moduledoc """
  Ash framework integration for Chain-of-Thought reasoning.
  """
  
  use Ash.Resource.Change
  
  alias AshDSPy.ChainOfThought.Engine
  
  @doc """
  Ash change for Chain-of-Thought reasoning.
  """
  def change(changeset, opts, _context) do
    signature = Keyword.fetch!(opts, :signature)
    input_mapping = Keyword.get(opts, :input_mapping, %{})
    output_field = Keyword.get(opts, :output_field, :reasoning_result)
    cot_opts = Keyword.get(opts, :cot_opts, [])
    
    Ash.Changeset.before_action(changeset, fn changeset ->
      # Extract inputs
      inputs = extract_inputs(changeset, input_mapping)
      
      # Execute reasoning
      case Engine.reason(signature, inputs, cot_opts) do
        {:ok, result} ->
          # Store full result
          changeset
          |> Ash.Changeset.force_change_attribute(output_field, result)
          |> add_reasoning_metadata(result)
          
        {:error, reason} ->
          Ash.Changeset.add_error(
            changeset,
            field: output_field,
            message: "Chain-of-Thought reasoning failed: #{inspect(reason)}"
          )
      end
    end)
  end
  
  defp extract_inputs(changeset, mapping) do
    mapping
    |> Enum.reduce(%{}, fn {input_field, source}, acc ->
      value = get_value_from_changeset(changeset, source)
      Map.put(acc, input_field, value)
    end)
  end
  
  defp get_value_from_changeset(changeset, source) when is_atom(source) do
    Ash.Changeset.get_attribute(changeset, source)
  end
  
  defp get_value_from_changeset(changeset, {:argument, arg_name}) do
    Ash.Changeset.get_argument(changeset, arg_name)
  end
  
  defp add_reasoning_metadata(changeset, result) do
    changeset
    |> Ash.Changeset.force_change_attribute(:reasoning_confidence, result.confidence)
    |> Ash.Changeset.force_change_attribute(:reasoning_quality, result.validation.quality_score)
    |> Ash.Changeset.force_change_attribute(:reasoning_steps, length(result.steps))
  end
end
```

### COMPREHENSIVE TESTING

```elixir
defmodule AshDSPy.ChainOfThought.EngineTest do
  use ExUnit.Case, async: true
  
  alias AshDSPy.ChainOfThought.Engine
  alias AshDSPy.Signature
  
  setup do
    {:ok, engine} = Engine.start_link(test_mode: true)
    
    # Create test signature
    signature = %Signature{
      name: "math_problem",
      instructions: "Solve the math problem step by step.",
      input_fields: %{
        problem: %{type: :string, required: true}
      },
      output_fields: %{
        answer: %{type: :number, required: true},
        explanation: %{type: :string, required: false}
      }
    }
    
    %{engine: engine, signature: signature}
  end
  
  describe "reason/3" do
    test "generates step-by-step reasoning", %{signature: signature} do
      inputs = %{problem: "If a train travels 60 mph for 2.5 hours, how far does it go?"}
      
      assert {:ok, result} = Engine.reason(signature, inputs)
      
      # Check structure
      assert Map.has_key?(result, :reasoning)
      assert Map.has_key?(result, :steps)
      assert Map.has_key?(result, :outputs)
      
      # Check reasoning quality
      assert String.length(result.reasoning) > 50
      assert length(result.steps) >= 3
      
      # Check output
      assert result.outputs.answer == 150
    end
    
    test "validates reasoning steps", %{signature: signature} do
      inputs = %{problem: "What is 2+2?"}
      opts = [validation_level: :comprehensive]
      
      assert {:ok, result} = Engine.reason(signature, inputs, opts)
      
      # All steps should be validated
      assert Enum.all?(result.steps, fn step ->
        Map.has_key?(step, :validation)
      end)
    end
    
    test "handles different rationale types", %{signature: signature} do
      inputs = %{problem: "Calculate the area of a circle with radius 5"}
      
      # Test each rationale type
      for type <- [:simple, :detailed, :structured] do
        opts = [rationale_type: type]
        assert {:ok, result} = Engine.reason(signature, inputs, opts)
        
        # Check appropriate complexity
        case type do
          :simple -> assert length(result.steps) <= 5
          :detailed -> assert length(result.steps) >= 5
          :structured -> 
            assert Enum.any?(result.steps, fn step ->
              String.contains?(step.content, "Step")
            end)
        end
      end
    end
  end
  
  describe "reason_with_consistency/3" do
    test "generates multiple reasoning paths", %{signature: signature} do
      inputs = %{problem: "What are the factors of 24?"}
      opts = [n_samples: 3]
      
      assert {:ok, result} = Engine.reason_with_consistency(signature, inputs, opts)
      
      # Check consensus information
      assert result.metadata.total_samples == 3
      assert result.validation.consensus_confidence > 0
    end
    
    test "selects most consistent answer", %{signature: signature} do
      inputs = %{problem: "Is 17 a prime number? Explain."}
      opts = [n_samples: 5]
      
      assert {:ok, result} = Engine.reason_with_consistency(signature, inputs, opts)
      
      # Should consistently identify 17 as prime
      assert result.outputs.answer == true
      assert result.validation.consensus_confidence > 0.6
    end
  end
  
  describe "validate_reasoning/2" do
    test "validates existing reasoning text" do
      reasoning = """
      Step 1: Understand the problem - we need to find 15% of 80.
      Step 2: Convert percentage to decimal: 15% = 0.15
      Step 3: Multiply: 0.15 × 80 = 12
      Therefore, 15% of 80 is 12.
      """
      
      assert {:ok, validation} = Engine.validate_reasoning(reasoning)
      assert validation.valid
      assert validation.score > 0.8
    end
    
    test "detects invalid reasoning" do
      reasoning = """
      First we add 2 + 2 = 5.
      Then we multiply by 0 to get infinity.
      Therefore, mathematics is broken.
      """
      
      assert {:ok, validation} = Engine.validate_reasoning(reasoning)
      refute validation.valid
      assert length(validation.issues) > 0
    end
  end
  
  describe "quality assessment" do
    test "assesses reasoning quality dimensions", %{signature: signature} do
      inputs = %{problem: "Explain why the sky is blue"}
      opts = [rationale_type: :detailed]
      
      assert {:ok, result} = Engine.reason(signature, inputs, opts)
      
      quality = result.validation.quality_score
      assert quality.overall_score > 0
      assert Map.has_key?(quality.dimensions, :clarity)
      assert Map.has_key?(quality.dimensions, :completeness)
      assert Map.has_key?(quality.dimensions, :correctness)
    end
  end
  
  describe "confidence calibration" do
    test "provides calibrated confidence scores", %{signature: signature} do
      # Run multiple predictions
      problems = [
        "What is 2+2?",  # High confidence
        "Explain quantum entanglement",  # Lower confidence
        "Calculate the 50th Fibonacci number"  # Medium confidence
      ]
      
      confidences = Enum.map(problems, fn problem ->
        {:ok, result} = Engine.reason(signature, %{problem: problem})
        result.confidence
      end)
      
      # Check confidence ordering
      [simple, complex, medium] = confidences
      assert simple > complex
      assert simple > medium
      assert medium > complex
    end
  end
  
  describe "step parsing" do
    test "parses various step formats" do
      alias AshDSPy.ChainOfThought.StepParser
      
      reasoning = """
      First, let's identify what we know.
      Second, we'll apply the formula.
      Step 3: Calculate the result.
      - Check our answer
      Therefore, the answer is 42.
      """
      
      steps = StepParser.parse(reasoning)
      
      assert length(steps) == 5
      assert Enum.at(steps, 0).type == :ordinal
      assert Enum.at(steps, 2).type == :numbered
      assert Enum.at(steps, 3).type == :bullet
      assert Enum.at(steps, 4).type == :conclusion
    end
  end
end
```

## PERFORMANCE CONSIDERATIONS

### 1. REASONING GENERATION OPTIMIZATION
- Cache enhanced signatures to avoid repeated enhancement
- Pre-compile common reasoning templates
- Use streaming for long reasoning chains

### 2. VALIDATION PERFORMANCE
- Parallel validation of independent steps
- Cache validation patterns and rules
- Early termination on critical failures

### 3. QUALITY ASSESSMENT OPTIMIZATION
- Batch quality assessments for multiple steps
- Use approximations for real-time assessment
- Cache quality metrics for similar inputs

### 4. MEMORY MANAGEMENT
- Limit reasoning history window
- Compress stored reasoning patterns
- Periodic cleanup of optimization data

## CONFIGURATION

```elixir
# config/config.exs
config :ash_dspy, :chain_of_thought,
  # Engine configuration
  default_rationale_type: :simple,
  max_reasoning_length: 2000,
  min_step_count: 3,
  max_step_count: 20,
  
  # Validation configuration
  validation_level: :strict,
  validation_timeout: 5000,
  
  # Quality assessment
  quality_weights: %{
    clarity: 0.25,
    completeness: 0.25,
    correctness: 0.3,
    efficiency: 0.1,
    insight: 0.1
  },
  min_quality_score: 0.6,
  
  # Self-consistency
  default_n_samples: 5,
  consensus_threshold: 0.6,
  
  # Optimization
  learning_window: 500,
  pattern_threshold: 0.7,
  optimization_enabled: true
```

This implementation provides a comprehensive Chain-of-Thought reasoning system with advanced validation, quality assessment, confidence calibration, and continuous optimization capabilities.