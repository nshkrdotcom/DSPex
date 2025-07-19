defmodule DSPEx.Teleprompter.BEACON.Examples do
  @moduledoc """
  Real-world usage examples for BEACON teleprompter.

  Demonstrates common optimization patterns and best practices for using
  BEACON across different types of programs and datasets.
  """

  alias DSPEx.{Example, OptimizedProgram, Predict}
  alias DSPEx.Teleprompter.BEACON

  @doc """
  Example: Question answering optimization

  Shows how to use BEACON to optimize a simple question-answering program
  with different instruction strategies and demonstration selection.
  """
  def question_answering_example do
    IO.puts("=== BEACON Question Answering Optimization Example ===\n")

    # Define signature for question answering
    defmodule QASignature do
      @moduledoc """
      Signature for question answering with context.

      Takes context and question as inputs, produces an answer.
      """
      use DSPEx.Signature, "context, question -> answer"
    end

    # Create student and teacher programs
    student = %Predict{signature: QASignature, client: :gemini}
    teacher = %Predict{signature: QASignature, client: :openai}

    # Create training dataset
    trainset = [
      Example.new(
        %{
          context:
            "The capital of France is Paris. It is located in the northern part of the country.",
          question: "What is the capital of France?",
          answer: "Paris"
        },
        [:context, :question]
      ),
      Example.new(
        %{
          context:
            "Python is a high-level programming language. It was created by Guido van Rossum.",
          question: "Who created Python?",
          answer: "Guido van Rossum"
        },
        [:context, :question]
      ),
      Example.new(
        %{
          context:
            "The iPhone was first released by Apple in 2007. It revolutionized the smartphone industry.",
          question: "When was the iPhone first released?",
          answer: "2007"
        },
        [:context, :question]
      ),
      Example.new(
        %{
          context:
            "William Shakespeare wrote many famous plays including Hamlet, Romeo and Juliet, and Macbeth.",
          question: "Name a play written by Shakespeare.",
          answer: "Hamlet"
        },
        [:context, :question]
      )
    ]

    # Define evaluation metric
    metric_fn = fn example, prediction ->
      # Simple exact match scoring
      expected = String.downcase(String.trim(example.data.answer))
      actual = String.downcase(String.trim(prediction.answer || ""))
      if expected == actual, do: 1.0, else: 0.0
    end

    # Create BEACON teleprompter with balanced configuration
    teleprompter =
      BEACON.new(
        # Generate 15 instruction variants
        num_candidates: 15,
        # Use up to 3 demonstrations
        max_bootstrapped_demos: 3,
        # Run 30 optimization trials
        num_trials: 30,
        # Require 70% accuracy for demos
        quality_threshold: 0.7,
        # Use 10 concurrent workers
        max_concurrency: 10,
        # 60 second timeout
        timeout: 60_000
      )

    IO.puts("Configuration:")
    IO.puts("- Instruction candidates: #{teleprompter.num_candidates}")
    IO.puts("- Bootstrap demos: #{teleprompter.max_bootstrapped_demos}")
    IO.puts("- Optimization trials: #{teleprompter.num_trials}")
    IO.puts("- Quality threshold: #{teleprompter.quality_threshold}")
    IO.puts("")

    # Perform optimization
    IO.puts("Starting BEACON optimization...")

    case BEACON.compile(teleprompter, student, teacher, trainset, metric_fn, []) do
      {:ok, optimized} ->
        IO.puts("✓ Optimization completed successfully!")

        # Display results
        case optimized do
          %OptimizedProgram{} ->
            IO.puts("- Optimized program type: OptimizedProgram")
            IO.puts("- Demo count: #{length(optimized.demos)}")

            print_instruction_if_present(optimized)

          _ ->
            IO.puts("- Optimized program type: #{optimized.__struct__}")
        end

        IO.puts("\nExample usage of optimized program:")

        test_input = %{
          context: "Mars is the fourth planet from the Sun. It is often called the Red Planet.",
          question: "What is Mars often called?"
        }

        case DSPEx.Program.forward(optimized, test_input) do
          {:ok, result} ->
            IO.puts("Input: #{test_input.question}")
            IO.puts("Output: #{result.answer}")

          {:error, reason} ->
            IO.puts("Error running optimized program: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("✗ Optimization failed: #{inspect(reason)}")
        IO.puts("This may be due to API limitations in the current environment.")
    end

    IO.puts("\n" <> String.duplicate("=", 60) <> "\n")
  end

  defp print_instruction_if_present(optimized) do
    if Map.has_key?(optimized, :instruction) do
      IO.puts("- Instruction: \"#{String.slice(optimized.instruction, 0, 100)}...\"")
    end
  end

  @doc """
  Example: Classification optimization

  Demonstrates BEACON optimization for text classification tasks with
  multiple categories and confidence scoring.
  """
  def classification_example do
    IO.puts("=== BEACON Text Classification Optimization Example ===\n")

    # Define signature for classification
    defmodule ClassificationSignature do
      @moduledoc """
      Signature for text classification with confidence scoring.

      Takes text as input, produces category and confidence level.
      """
      use DSPEx.Signature, "text -> category, confidence"
    end

    # Create programs
    student = %Predict{signature: ClassificationSignature, client: :gemini}
    teacher = %Predict{signature: ClassificationSignature, client: :openai}

    # Create training dataset for sentiment classification
    trainset = [
      Example.new(
        %{
          text: "I absolutely love this product! It exceeded all my expectations.",
          category: "positive",
          confidence: "high"
        },
        [:text]
      ),
      Example.new(
        %{
          text: "This is the worst purchase I've ever made. Complete waste of money.",
          category: "negative",
          confidence: "high"
        },
        [:text]
      ),
      Example.new(
        %{
          text: "The product is okay, nothing special but does the job.",
          category: "neutral",
          confidence: "medium"
        },
        [:text]
      ),
      Example.new(
        %{
          text: "Amazing quality and fast delivery! Highly recommended.",
          category: "positive",
          confidence: "high"
        },
        [:text]
      ),
      Example.new(
        %{
          text: "Not sure if I like this. It has some good features but also some issues.",
          category: "neutral",
          confidence: "low"
        },
        [:text]
      )
    ]

    # Multi-criteria evaluation metric
    metric_fn = fn example, prediction ->
      category_score = if example.data.category == prediction.category, do: 0.7, else: 0.0
      confidence_score = if example.data.confidence == prediction.confidence, do: 0.3, else: 0.0
      category_score + confidence_score
    end

    # Create BEACON teleprompter optimized for classification
    teleprompter =
      BEACON.new(
        # More candidates for complex classification
        num_candidates: 20,
        # More demos for better context
        max_bootstrapped_demos: 4,
        # More trials for complex optimization
        num_trials: 40,
        # Higher quality threshold
        quality_threshold: 0.8,
        max_concurrency: 15
      )

    IO.puts("Starting classification optimization...")

    case BEACON.compile(teleprompter, student, teacher, trainset, metric_fn, []) do
      {:ok, optimized} ->
        IO.puts("✓ Classification optimization completed!")

        # Test the optimized classifier
        test_cases = [
          "This product is fantastic! I'm so happy with my purchase.",
          "Terrible quality, broke after one day.",
          "It's an average product, nothing to write home about."
        ]

        IO.puts("\nTesting optimized classifier:")

        Enum.each(test_cases, &test_classification(&1, optimized))

      {:error, reason} ->
        IO.puts("✗ Classification optimization failed: #{inspect(reason)}")
    end

    IO.puts(String.duplicate("=", 60) <> "\n")
  end

  defp test_classification(text, optimized_program) do
    case DSPEx.Program.forward(optimized_program, %{text: text}) do
      {:ok, result} ->
        IO.puts("Text: \"#{text}\"")
        IO.puts("Category: #{result.category}, Confidence: #{result.confidence}\n")

      {:error, reason} ->
        IO.puts("Classification error: #{inspect(reason)}")
    end
  end

  @doc """
  Example: Chain of thought reasoning optimization

  Shows how BEACON can optimize complex reasoning programs that require
  step-by-step thinking and intermediate steps.
  """
  def chain_of_thought_example do
    IO.puts("=== BEACON Chain of Thought Reasoning Example ===\n")

    # Define signature for chain of thought reasoning
    defmodule ChainOfThoughtSignature do
      @moduledoc """
      Signature for chain of thought reasoning problems.

      Takes a problem as input, produces reasoning steps and final answer.
      """
      use DSPEx.Signature, "problem -> reasoning, answer"
    end

    # Create programs
    student = %Predict{signature: ChainOfThoughtSignature, client: :gemini}
    teacher = %Predict{signature: ChainOfThoughtSignature, client: :openai}

    # Create training dataset for math word problems
    trainset = create_chain_of_thought_trainset()

    # Evaluation metric that considers both reasoning and answer
    metric_fn = &chain_of_thought_metric/2

    # Create BEACON teleprompter for complex reasoning
    teleprompter =
      BEACON.new(
        # Many instruction variants for reasoning
        num_candidates: 25,
        # Good examples are crucial for reasoning
        max_bootstrapped_demos: 3,
        # More trials for complex optimization
        num_trials: 50,
        # High quality for mathematical reasoning
        quality_threshold: 0.8,
        max_concurrency: 12,
        # Longer timeout for complex reasoning
        timeout: 90_000
      )

    IO.puts("Optimizing chain of thought reasoning...")

    case BEACON.compile(teleprompter, student, teacher, trainset, metric_fn, []) do
      {:ok, optimized} ->
        IO.puts("✓ Chain of thought optimization completed!")

        # Test with a new math problem
        test_problem =
          "A rectangle has a length of 12 meters and a width of 8 meters. What is its area?"

        case DSPEx.Program.forward(optimized, %{problem: test_problem}) do
          {:ok, result} ->
            IO.puts("Problem: #{test_problem}")
            IO.puts("Reasoning: #{result.reasoning}")
            IO.puts("Answer: #{result.answer}")

          {:error, reason} ->
            IO.puts("Reasoning error: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("✗ Chain of thought optimization failed: #{inspect(reason)}")
    end

    IO.puts(String.duplicate("=", 60) <> "\n")
  end

  @doc """
  Example: Multi-step workflow optimization

  Demonstrates optimizing a complex workflow that involves multiple
  processing steps and intermediate results.
  """
  def multi_step_workflow_example do
    IO.puts("=== BEACON Multi-Step Workflow Optimization Example ===\n")

    # Define signature for document analysis workflow
    defmodule DocumentAnalysisSignature do
      @moduledoc """
      Signature for comprehensive document analysis.

      Takes a document as input, produces summary, key points, sentiment, and action items.
      """
      use DSPEx.Signature, "document -> summary, key_points, sentiment, action_items"
    end

    # Create programs
    student = %Predict{signature: DocumentAnalysisSignature, client: :gemini}
    teacher = %Predict{signature: DocumentAnalysisSignature, client: :openai}

    # Create training dataset for document analysis
    trainset = [
      Example.new(
        %{
          document:
            "Meeting Notes: We discussed the quarterly budget. Revenue is up 15% but costs have increased by 8%. We need to optimize our marketing spend and consider new automation tools. Action: Schedule follow-up meeting next week.",
          summary: "Quarterly budget discussion with revenue growth and cost increases",
          key_points: "Revenue +15%, Costs +8%, Marketing optimization needed",
          sentiment: "cautiously optimistic",
          action_items:
            "Schedule follow-up meeting, review marketing spend, evaluate automation tools"
        },
        [:document]
      ),
      Example.new(
        %{
          document:
            "Customer Feedback: The new product launch has been very successful. Customers love the improved design and faster performance. Sales exceeded projections by 30%. Team morale is high.",
          summary: "Successful product launch with excellent customer reception",
          key_points: "Improved design, faster performance, sales +30% vs projections",
          sentiment: "very positive",
          action_items: "Continue current strategy, monitor customer satisfaction, plan scaling"
        },
        [:document]
      )
    ]

    # Complex multi-criteria evaluation
    metric_fn = fn example, prediction ->
      scores = []

      # Summary accuracy (basic keyword matching)
      summary_score = calculate_text_similarity(example.data.summary, prediction.summary || "")
      scores = [summary_score * 0.3 | scores]

      # Key points coverage
      points_score =
        calculate_text_similarity(example.data.key_points, prediction.key_points || "")

      scores = [points_score * 0.25 | scores]

      # Sentiment accuracy
      sentiment_score = if example.data.sentiment == prediction.sentiment, do: 1.0, else: 0.0
      scores = [sentiment_score * 0.2 | scores]

      # Action items relevance
      actions_score =
        calculate_text_similarity(example.data.action_items, prediction.action_items || "")

      scores = [actions_score * 0.25 | scores]

      Enum.sum(scores)
    end

    # Create BEACON teleprompter for complex workflows
    teleprompter =
      BEACON.new(
        # Many variants for complex multi-output tasks
        num_candidates: 30,
        # Complex examples, fewer needed
        max_bootstrapped_demos: 2,
        # Extensive optimization for complexity
        num_trials: 60,
        # Reasonable threshold for complex task
        quality_threshold: 0.75,
        max_concurrency: 20,
        # Extended timeout for complex processing
        timeout: 120_000
      )

    IO.puts("Optimizing multi-step document analysis workflow...")

    case BEACON.compile(teleprompter, student, teacher, trainset, metric_fn, []) do
      {:ok, optimized} ->
        IO.puts("✓ Multi-step workflow optimization completed!")

        # Test with a new document
        test_document = """
        Project Update: The AI integration project is behind schedule due to data quality issues.
        We've identified three main problems: incomplete datasets, format inconsistencies, and
        missing validation procedures. The team is working overtime but morale is declining.
        We need to bring in external consultants and extend the deadline by 6 weeks.
        """

        case DSPEx.Program.forward(optimized, %{document: test_document}) do
          {:ok, result} ->
            IO.puts("Document Analysis Results:")
            IO.puts("Summary: #{result.summary}")
            IO.puts("Key Points: #{result.key_points}")
            IO.puts("Sentiment: #{result.sentiment}")
            IO.puts("Action Items: #{result.action_items}")

          {:error, reason} ->
            IO.puts("Workflow error: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("✗ Multi-step workflow optimization failed: #{inspect(reason)}")
    end

    IO.puts(String.duplicate("=", 60) <> "\n")
  end

  @doc """
  Run all BEACON examples in sequence.

  Demonstrates the full range of BEACON capabilities across different
  types of optimization scenarios.
  """
  def run_all_examples do
    IO.puts("🚀 Running comprehensive BEACON examples...\n")

    question_answering_example()
    classification_example()
    chain_of_thought_example()
    multi_step_workflow_example()

    IO.puts("✅ All BEACON examples completed!")
    IO.puts("These examples demonstrate BEACON's versatility across:")
    IO.puts("• Simple question-answering tasks")
    IO.puts("• Multi-criteria classification")
    IO.puts("• Complex reasoning and chain of thought")
    IO.puts("• Multi-step workflow optimization")
    IO.puts("\nBEACON provides robust optimization capabilities for diverse NLP tasks.")
  end

  # Helper functions

  defp create_chain_of_thought_trainset do
    [
      Example.new(
        %{
          problem:
            "A store has 48 apples. They sell 15 apples in the morning and 12 apples in the afternoon. How many apples do they have left?",
          reasoning:
            "Start with 48 apples. Subtract 15 sold in morning: 48 - 15 = 33. Subtract 12 sold in afternoon: 33 - 12 = 21.",
          answer: "21"
        },
        [:problem]
      ),
      Example.new(
        %{
          problem: "If a train travels 60 miles per hour for 2.5 hours, how far does it travel?",
          reasoning:
            "Distance = speed × time. Speed is 60 mph, time is 2.5 hours. Distance = 60 × 2.5 = 150 miles.",
          answer: "150 miles"
        },
        [:problem]
      ),
      Example.new(
        %{
          problem:
            "Sarah has 3 times as many books as Tom. If Tom has 8 books, how many books does Sarah have?",
          reasoning:
            "Tom has 8 books. Sarah has 3 times as many as Tom. Sarah's books = 3 × 8 = 24 books.",
          answer: "24"
        },
        [:problem]
      )
    ]
  end

  defp chain_of_thought_metric(example, prediction) do
    # Check if the final answer is correct (simplified)
    expected_answer = String.trim(example.data.answer)
    predicted_answer = String.trim(prediction.answer || "")

    answer_correct = String.contains?(predicted_answer, expected_answer)

    # Check if reasoning contains key mathematical concepts
    reasoning = String.downcase(prediction.reasoning || "")
    # Basic reasoning length check
    has_reasoning = String.length(reasoning) > 20

    cond do
      answer_correct and has_reasoning -> 1.0
      answer_correct -> 0.7
      has_reasoning -> 0.3
      true -> 0.0
    end
  end

  defp calculate_text_similarity(text1, text2) when is_binary(text1) and is_binary(text2) do
    # Simple word overlap similarity metric
    words1 = text1 |> String.downcase() |> String.split() |> MapSet.new()
    words2 = text2 |> String.downcase() |> String.split() |> MapSet.new()

    intersection_size = MapSet.intersection(words1, words2) |> MapSet.size()
    union_size = MapSet.union(words1, words2) |> MapSet.size()

    if union_size == 0, do: 0.0, else: intersection_size / union_size
  end

  defp calculate_text_similarity(_text1, _text2), do: 0.0
end
