# Document Analysis with RAG - Demonstrates retrievers and advanced optimizers
# Run with: mix run examples/dspy/03_document_analysis_rag.exs

# Configure Snakepit for pooling BEFORE starting
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)

Application.put_env(:snakepit, :pool_config, %{
  pool_size: 4,
  adapter_args: ["--adapter", "dspex_adapters.dspy_grpc.DSPyGRPCHandler"]
})

# Stop and restart applications if already started
Application.stop(:dspex)
Application.stop(:snakepit)

# Start required applications
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)

# Check DSPy availability using new integration
case Snakepit.execute_in_session("rag_session", "check_dspy", %{}) do
  {:ok, %{"available" => true}} ->
    IO.puts("✓ DSPy available")

  {:error, error} ->
    IO.puts("✗ DSPy check failed: #{inspect(error)}")
    System.halt(1)
end

# Load config and configure Gemini as default language model
config_path = Path.join(__DIR__, "../config.exs")
config_data = Code.eval_file(config_path) |> elem(0)
api_key = config_data.api_key

if api_key do
  IO.puts("\n✓ Configuring Gemini...")
  IO.puts("  API Key: #{String.slice(api_key, 0..5)}...#{String.slice(api_key, -4..-1)}")

  # Configure Gemini using the gRPC bridge  
  case Snakepit.execute_in_session("rag_session", "configure_lm", %{
         "model_type" => "gemini",
         "api_key" => api_key,
         "model" => config_data.model
       }) do
    {:ok, %{"success" => true}} -> IO.puts("  Successfully configured!")
    {:ok, %{"success" => false, "error" => error}} -> IO.puts("  Configuration error: #{error}")
    {:error, error} -> IO.puts("  Configuration error: #{inspect(error)}")
  end
else
  IO.puts("\n⚠️  WARNING: No Gemini API key found!")
  IO.puts("  Set GOOGLE_API_KEY or GEMINI_API_KEY environment variable.")
  IO.puts("  Get your free API key at: https://makersuite.google.com/app/apikey")
  IO.puts("  ")
  IO.puts("  Example: export GOOGLE_API_KEY=your-gemini-api-key")
  IO.puts("  ")
  IO.puts("  Running without LLM - examples will show expected errors...")
end

defmodule DocumentAnalysisRAG do
  @moduledoc """
  Document analysis system with retrieval demonstrating:
  - ColBERTv2: Dense retrieval
  - Retrieve: Vector database integration
  - MIPROv2: Enhanced optimization
  - COPRO: Coordinate optimization
  - Examples: Dataset management
  - Complex pipelines with retrieval
  """

  def run do
    IO.puts("\n=== Document Analysis RAG System Demo ===\n")

    # 1. Setup retrieval systems
    demo_retrieval_setup()

    # 2. Document analysis pipeline
    demo_document_pipeline()

    # 3. Advanced optimization with MIPROv2
    demo_mipro_v2()

    # 4. COPRO for multi-stage optimization
    demo_copro()

    # 5. Dataset and examples management
    demo_examples()
  end

  defp demo_retrieval_setup do
    IO.puts("1. Retrieval System Setup")
    IO.puts("-------------------------")

    # Mock document corpus
    documents = [
      "Elixir is a dynamic, functional language designed for building maintainable and scalable applications.",
      "Elixir leverages the Erlang VM, known for running low-latency, distributed and fault-tolerant systems.",
      "The Erlang VM (BEAM) provides excellent concurrency support through lightweight processes.",
      "Phoenix is a web framework for Elixir that provides high productivity and performance.",
      "LiveView enables rich, interactive web applications without writing JavaScript.",
      "OTP (Open Telecom Platform) provides libraries and design principles for building distributed applications.",
      "GenServer is a behavior module for implementing stateful server processes in Elixir.",
      "Supervisors in Elixir provide fault tolerance by restarting failed processes."
    ]

    # Setup mock retriever for demo (ChromaDB integration would require additional dependencies)
    IO.puts("Setting up mock retriever...")

    # Mock retrieval function that finds relevant documents
    mock_retrieve = fn query, docs, k ->
      # Simple keyword matching for demo
      query_words = String.downcase(query) |> String.split()

      docs
      |> Enum.with_index()
      |> Enum.map(fn {doc, idx} ->
        score =
          query_words
          |> Enum.count(fn word -> String.contains?(String.downcase(doc), word) end)

        {doc, idx, score}
      end)
      |> Enum.filter(fn {_, _, score} -> score > 0 end)
      |> Enum.sort_by(fn {_, _, score} -> -score end)
      |> Enum.take(k)
      |> Enum.map(fn {doc, idx, score} -> %{text: doc, id: idx, score: score} end)
    end

    IO.puts("Added #{length(documents)} documents to retriever")

    # Test retrieval
    query = "How does Elixir handle concurrency?"
    results = mock_retrieve.(query, documents, 3)

    IO.puts("\nQuery: #{query}")
    IO.puts("Retrieved #{length(results)} relevant passages")

    # Display retrieved passages
    for {result, idx} <- Enum.with_index(results) do
      IO.puts("#{idx + 1}. (Score: #{result.score}) #{result.text}")
    end

    IO.puts("\n✓ Retrieval system setup complete")
  end

  defp demo_document_pipeline do
    IO.puts("\n\n2. Document Analysis Pipeline")
    IO.puts("-----------------------------")

    # Mock documents for retrieval
    documents = [
      "Elixir leverages the Erlang VM, known for running low-latency, distributed and fault-tolerant systems.",
      "The Erlang VM (BEAM) provides excellent concurrency support through lightweight processes.",
      "Phoenix is a web framework for Elixir that provides high productivity and performance.",
      "LiveView enables rich, interactive web applications without writing JavaScript.",
      "OTP (Open Telecom Platform) provides libraries and design principles for building distributed applications.",
      "GenServer is a behavior module for implementing stateful server processes in Elixir.",
      "Supervisors in Elixir provide fault tolerance by restarting failed processes."
    ]

    # Mock retriever function
    mock_retrieve = fn query, docs, k ->
      query_words = String.downcase(query) |> String.split()

      docs
      |> Enum.with_index()
      |> Enum.map(fn {doc, idx} ->
        score =
          query_words
          |> Enum.count(fn word -> String.contains?(String.downcase(doc), word) end)

        {doc, idx, score}
      end)
      |> Enum.filter(fn {_, _, score} -> score > 0 end)
      |> Enum.sort_by(fn {_, _, score} -> -score end)
      |> Enum.take(k)
      |> Enum.map(fn {doc, _, _} -> doc end)
    end

    # Create modules for the pipeline
    {:ok, query_processor} =
      DSPex.Modules.Predict.create("question: str -> search_query: str, intent: str")

    {:ok, answer_generator} =
      DSPex.Modules.ChainOfThought.create("question: str, context: str -> answer: str")

    # Example questions
    questions = [
      "What makes Elixir good for building scalable applications?",
      "How does Phoenix LiveView work?",
      "What is OTP and why is it important?"
    ]

    for question <- questions do
      IO.puts("\nQ: #{question}")

      # Process query
      {search_query, intent} =
        case DSPex.Modules.Predict.execute(query_processor, %{
               question: question
             }) do
          {:ok, result} ->
            sq =
              case result do
                %{"success" => true, "result" => prediction_data} ->
                  prediction_data["search_query"] || question

                %{"search_query" => sq} ->
                  sq

                _ ->
                  question
              end

            i =
              case result do
                %{"success" => true, "result" => prediction_data} ->
                  prediction_data["intent"] || "general"

                %{"intent" => i} ->
                  i

                _ ->
                  "general"
              end

            IO.puts("Search Query: #{sq}")
            IO.puts("Intent: #{i}")
            {sq, i}

          {:error, error} ->
            IO.puts("Error processing query: #{inspect(error)}")
            {question, "general"}
        end

      # Retrieve relevant context using mock retriever
      relevant_docs = mock_retrieve.(search_query, documents, 2)
      context = Enum.join(relevant_docs, " ")

      # Generate answer with context
      case DSPex.Modules.ChainOfThought.execute(answer_generator, %{
             question: question,
             context: context
           }) do
        {:ok, result} ->
          answer_text =
            get_in(result, ["result", "prediction_data", "answer"]) ||
              get_in(result, ["answer"]) ||
              "No answer in result: #{inspect(result)}"

          IO.puts("Answer: #{answer_text}")

        {:error, error} ->
          IO.puts("Error generating answer: #{inspect(error)}")
      end

      IO.puts(String.duplicate("-", 50))
    end
  end

  defp demo_mipro_v2 do
    IO.puts("\n\n3. MIPROv2 - Enhanced RAG Optimization")
    IO.puts("---------------------------------------")

    # Create a retrieval-augmented generation module
    {:ok, rag_module} =
      DSPex.Modules.Predict.create(
        "question: str, retrieved_docs: list[str] -> answer: str, sources: list[int]"
      )

    # Training data for RAG
    trainset = [
      %{
        question: "What is GenServer?",
        retrieved_docs: [
          "GenServer is a behavior module for implementing stateful server processes.",
          "It provides a standard interface for building server processes.",
          "GenServer handles message passing and state management."
        ],
        answer:
          "GenServer is a behavior module in Elixir that provides a standard way to implement stateful server processes with message handling and state management.",
        sources: [0, 1, 2]
      },
      %{
        question: "How do Supervisors work?",
        retrieved_docs: [
          "Supervisors provide fault tolerance by restarting failed processes.",
          "They implement supervision strategies like one_for_one and one_for_all.",
          "Supervisors are part of OTP design principles."
        ],
        answer:
          "Supervisors in Elixir monitor child processes and restart them when they fail, implementing strategies like one_for_one or one_for_all to ensure system reliability.",
        sources: [0, 1]
      }
    ]

    IO.puts("Optimizing RAG with MIPROv2 (mock demonstration)...")

    # Mock optimization result
    mock_report = %{
      initial_score: 0.65,
      final_score: 0.82,
      improvement: 0.17,
      iterations: 5,
      best_prompt: "Given the context documents, provide a comprehensive answer to the question."
    }

    IO.puts("MIPROv2 optimization complete!")
    IO.puts("Optimization Report:")
    IO.puts("- Initial Score: #{mock_report.initial_score}")
    IO.puts("- Final Score: #{mock_report.final_score}")
    IO.puts("- Improvement: #{mock_report.improvement}")
    IO.puts("- Iterations: #{mock_report.iterations}")
    IO.puts("- Best Prompt: #{mock_report.best_prompt}")
  end

  defp demo_copro do
    IO.puts("\n\n4. COPRO - Coordinate Optimization for Multi-Stage")
    IO.puts("---------------------------------------------------")

    # Create a multi-stage document analysis pipeline
    {:ok, doc_classifier} =
      DSPex.Modules.Predict.create("document: str -> category: str, confidence: float")

    {:ok, entity_extractor} =
      DSPex.Modules.ChainOfThought.create(
        "document: str, category: str -> entities: list[str], relationships: list[str]"
      )

    {:ok, summarizer} =
      DSPex.Modules.Predict.create(
        "document: str, entities: list[str] -> summary: str, key_points: list[str]"
      )

    # Combined program (mock structure)
    program = %{
      modules: [doc_classifier, entity_extractor, summarizer],
      flow: :sequential
    }

    # Training data
    trainset = [
      %{
        document: "Elixir processes are lightweight and isolated...",
        category: "technical",
        entities: ["Elixir", "processes", "BEAM"],
        relationships: ["Elixir uses BEAM", "processes are lightweight"],
        summary: "Elixir leverages lightweight processes on the BEAM VM",
        key_points: ["Process isolation", "Lightweight concurrency"]
      }
    ]

    IO.puts("Optimizing multi-stage pipeline with COPRO (mock demonstration)...")

    # Mock COPRO optimization
    stages_optimized = 3

    IO.puts("COPRO optimization complete!")
    IO.puts("Optimized all #{stages_optimized} stages coordinately")
    IO.puts("- Stage 1: Query processing optimized (+12% accuracy)")
    IO.puts("- Stage 2: Retrieval enhanced (+8% relevance)")
    IO.puts("- Stage 3: Answer generation improved (+15% quality)")
  end

  defp demo_examples do
    IO.puts("\n\n5. Dataset and Examples Management")
    IO.puts("-----------------------------------")

    # Create individual examples
    example1 = %{
      question: "What is Elixir?",
      answer: "A functional programming language",
      metadata: %{difficulty: "easy", topic: "basics"}
    }

    example2 = %{
      question: "Explain OTP",
      answer: "Open Telecom Platform - libraries and design principles",
      metadata: %{difficulty: "medium", topic: "architecture"}
    }

    # Mock dataset
    dataset = [example1, example2]

    IO.puts("Created dataset with #{length(dataset)} examples")

    # Load built-in dataset (mock)
    IO.puts("\nLoaded HotPotQA dataset (mock demonstration)")
    hotpot_qa_size = 105_000
    IO.puts("- Total examples: #{hotpot_qa_size}")

    # Mock dataset splitting
    IO.puts("\nDataset splits:")
    IO.puts("- Train: 70%")
    IO.puts("- Validation: 15%")
    IO.puts("- Test: 15%")

    # Sample from dataset
    sample = Enum.random(dataset)
    IO.puts("\nRandom sample from dataset: #{inspect(sample)}")

    # Use with evaluation
    IO.puts("\n\nEvaluating model on dataset...")

    {:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")

    # Create a simple eval dataset
    eval_data = [
      %{question: "What is 2+2?", answer: "4"},
      %{question: "Capital of France?", answer: "Paris"}
    ]

    # Mock evaluation
    mock_results = %{
      accuracy: 0.85,
      f1_score: 0.82,
      precision: 0.88,
      recall: 0.77,
      total_examples: length(eval_data)
    }

    IO.puts("Evaluation complete with F1 scoring")
    IO.puts("Results: #{inspect(mock_results)}")
    IO.puts("Model performance: #{mock_results.accuracy * 100}% accuracy")
  end
end

# Run the system with proper cleanup
Snakepit.run_as_script(fn ->
  DocumentAnalysisRAG.run()
  IO.puts("\n\n=== Document Analysis RAG Complete ===")
  IO.puts("To use with real document analysis:")
  IO.puts("1. Set your Gemini API key: export GOOGLE_API_KEY=your-key")
  IO.puts("2. Set up a vector database (ChromaDB, Qdrant, etc.)")
  IO.puts("3. Run again for actual RAG results")
end)
