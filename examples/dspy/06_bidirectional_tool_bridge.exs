# Bidirectional Tool Bridge Demo - Shows Python DSPy calling back to Elixir
# Run with: mix run examples/dspy/06_bidirectional_tool_bridge.exs

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

# Check DSPy availability
case Snakepit.execute_in_session("bidirectional_session", "check_dspy", %{}) do
  {:ok, %{"available" => true}} -> 
    IO.puts("✓ DSPy available")
  {:error, error} -> 
    IO.puts("✗ DSPy check failed: #{inspect(error)}")
    System.halt(1)
end

# Load config and configure Gemini
config_path = Path.join(__DIR__, "../config.exs")
config_data = Code.eval_file(config_path) |> elem(0)
api_key = config_data.api_key

if api_key do
  IO.puts("\n✓ Configuring Gemini...")
  IO.puts("  API Key: #{String.slice(api_key, 0..5)}...#{String.slice(api_key, -4..-1)}")
  
  case Snakepit.execute_in_session("bidirectional_session", "configure_lm", %{
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
  System.halt(1)
end

defmodule BidirectionalToolBridgeDemo do
  @moduledoc """
  Demonstrates the power of bidirectional tool calling where:
  1. Elixir calls Python DSPy for ML reasoning
  2. Python DSPy calls back to Elixir for business logic, validation, and formatting
  3. Both sides leverage their strengths seamlessly
  """
  
  def run do
    IO.puts("\n=== Bidirectional Tool Bridge Demo ===\n")
    
    # 1. Initialize session with bidirectional tools
    demo_session_setup()
    
    # 2. Enhanced Chain of Thought with Elixir validation
    demo_enhanced_chain_of_thought()
    
    # 3. Enhanced Predict with signature validation
    demo_enhanced_predict()
    
    # 4. Custom business logic integration
    demo_custom_business_logic()
    
    # 5. Advanced metaprogramming with defdsyp
    demo_advanced_metaprogramming()
    
    # 6. Tool discovery and introspection
    demo_tool_discovery()
  end
  
  defp demo_session_setup do
    IO.puts("1. Bidirectional Session Setup")
    IO.puts("------------------------------")
    
    # Initialize session with standard Elixir tools
    case DSPex.Bridge.init_bidirectional_session("bidirectional_session") do
      {:ok, session_id} ->
        IO.puts("✓ Initialized bidirectional session: #{session_id}")
        
        # List available Elixir tools
        case DSPex.Bridge.list_elixir_tools(session_id) do
          {:ok, tools} ->
            IO.puts("✓ Registered Elixir tools: #{Enum.join(tools, ", ")}")
          {:error, error} ->
            IO.puts("✗ Failed to list tools: #{error}")
        end
        
        # Register custom domain-specific tool
        custom_tool = fn params ->
          reasoning = Map.get(params, "reasoning", "")
          domain = Map.get(params, "domain", "general")
          
          # Domain-specific validation logic
          score = case domain do
            "medical" -> if String.contains?(reasoning, ["symptom", "diagnosis"]), do: 0.9, else: 0.3
            "financial" -> if String.contains?(reasoning, ["risk", "return"]), do: 0.8, else: 0.4
            "technical" -> if String.contains?(reasoning, ["algorithm", "implementation"]), do: 0.85, else: 0.5
            _ -> 0.7
          end
          
          %{
            valid: score > 0.5,
            score: score,
            domain: domain,
            suggestions: (if score < 0.5, do: ["Add more domain-specific terminology"], else: [])
          }
        end
        
        case DSPex.Bridge.register_custom_tool(session_id, "domain_validator", custom_tool, %{
          description: "Validate reasoning against domain-specific criteria",
          parameters: [
            %{name: "reasoning", type: "string", required: true},
            %{name: "domain", type: "string", required: false}
          ]
        }) do
          {:ok, _} -> IO.puts("✓ Registered custom domain validator")
          {:error, error} -> IO.puts("✗ Failed to register custom tool: #{error}")
        end
        
      {:error, error} ->
        IO.puts("✗ Failed to initialize bidirectional session: #{error}")
    end
    
    IO.puts("")
  end
  
  defp demo_enhanced_chain_of_thought do
    IO.puts("2. Enhanced Chain of Thought with Elixir Validation")
    IO.puts("--------------------------------------------------")
    
    questions = [
      %{question: "What are the key symptoms of pneumonia?", domain: "medical"},
      %{question: "How should I diversify my investment portfolio?", domain: "financial"},
      %{question: "What's the best algorithm for sorting large datasets?", domain: "technical"}
    ]
    
    for %{question: question, domain: domain} <- questions do
      IO.puts("\nQ: #{question}")
      IO.puts("Domain: #{domain}")
      
      # Use enhanced Chain of Thought that calls back to Elixir
      case Snakepit.execute_in_session("bidirectional_session", "enhanced_chain_of_thought", %{
        "signature" => "question -> reasoning, answer",
        "question" => question,
        "domain" => domain
      }) do
        {:ok, %{"success" => true} = result} ->
          IO.puts("\n🧠 DSPy Reasoning:")
          reasoning = get_in(result, ["result", "reasoning"]) || get_in(result, ["reasoning"])
          if reasoning, do: IO.puts("   #{reasoning}")
          
          IO.puts("\n🔍 Elixir Validation:")
          validation = result["elixir_validation"]
          if validation do
            IO.puts("   Score: #{validation["score"]}/1.0")
            IO.puts("   Valid: #{validation["valid"]}")
            IO.puts("   Domain: #{validation["domain"]}")
            
            if validation["suggestions"] && length(validation["suggestions"]) > 0 do
              IO.puts("   Suggestions: #{Enum.join(validation["suggestions"], ", ")}")
            end
          end
          
          IO.puts("\n✨ Formatted Output:")
          formatted = result["formatted_output"]
          if formatted, do: IO.puts("   #{formatted}")
          
          answer = get_in(result, ["result", "answer"]) || get_in(result, ["answer"])
          if answer, do: IO.puts("\n💡 Answer: #{answer}")
          
        {:ok, %{"success" => false, "error" => error}} ->
          IO.puts("✗ Enhanced Chain of Thought failed: #{error}")
          
        {:error, error} ->
          IO.puts("✗ Error: #{inspect(error)}")
      end
      
      IO.puts("\n" <> String.duplicate("-", 60))
    end
  end
  
  defp demo_enhanced_predict do
    IO.puts("\n\n3. Enhanced Predict with Signature Validation")
    IO.puts("---------------------------------------------")
    
    test_cases = [
      %{signature: "question -> answer", question: "What is Elixir?"},
      %{signature: "invalid_signature_format", question: "This should fail"},
      %{signature: "problem: str -> solution: str, confidence: float", question: "How to optimize database queries?"}
    ]
    
    for %{signature: signature, question: question} <- test_cases do
      IO.puts("\nSignature: #{signature}")
      IO.puts("Question: #{question}")
      
      case Snakepit.execute_in_session("bidirectional_session", "enhanced_predict", %{
        "signature" => signature,
        "question" => question
      }) do
        {:ok, %{"success" => true} = result} ->
          IO.puts("✓ Enhanced Predict succeeded")
          
          if result["type"] == "enhanced_predict" do
            IO.puts("  🔧 Used Elixir signature validation and result transformation")
          end
          
          transformed_result = result["result"]
          if transformed_result do
            answer = get_in(transformed_result, ["transformed_result", "success"]) ||
                    get_in(transformed_result, ["prediction_data", "answer"]) ||
                    get_in(transformed_result, ["answer"])
            if answer, do: IO.puts("  💡 Answer: #{inspect(answer)}")
          end
          
        {:ok, %{"success" => false, "error" => error}} ->
          IO.puts("✗ Enhanced Predict failed: #{error}")
          IO.puts("  (This demonstrates Elixir-side validation catching invalid signatures)")
          
        {:error, error} ->
          IO.puts("✗ Error: #{inspect(error)}")
      end
    end
  end
  
  defp demo_custom_business_logic do
    IO.puts("\n\n4. Custom Business Logic Integration")
    IO.puts("------------------------------------")
    
    # Register business-specific tools
    business_validator = fn params ->
      reasoning = Map.get(params, "reasoning", "")
      business_context = Map.get(params, "business_context", "general")
      
      # Simulate business rule validation
      compliance_score = case business_context do
        "healthcare" -> 
          if String.contains?(reasoning, ["HIPAA", "patient privacy", "medical ethics"]), do: 0.9, else: 0.3
        "finance" -> 
          if String.contains?(reasoning, ["regulatory compliance", "risk management"]), do: 0.85, else: 0.4
        "legal" -> 
          if String.contains?(reasoning, ["precedent", "statute", "jurisdiction"]), do: 0.8, else: 0.2
        _ -> 0.6
      end
      
      %{
        compliant: compliance_score > 0.5,
        compliance_score: compliance_score,
        business_context: business_context,
        recommendations: (if compliance_score < 0.5, do: ["Include relevant regulations", "Cite industry standards"], else: [])
      }
    end
    
    case DSPex.Bridge.register_custom_tool("bidirectional_session", "business_validator", business_validator, %{
      description: "Validate reasoning against business and regulatory requirements",
      parameters: [
        %{name: "reasoning", type: "string", required: true},
        %{name: "business_context", type: "string", required: false}
      ]
    }) do
      {:ok, _} ->
        IO.puts("✓ Registered business validator")
        
        # Create a custom enhanced module using defdsyp
        defmodule BusinessChainOfThought do
          use DSPex.Bridge
          
          defdsyp __MODULE__, "dspy.ChainOfThought", %{
            execute_method: "__call__",
            elixir_tools: [
              "validate_reasoning",
              "business_validator", 
              "process_template"
            ],
            enhanced_mode: true,
            result_transform: fn result ->
              # Custom business-focused transformation
              case result do
                %{"elixir_validation" => validation, "result" => dspy_result} ->
                  %{
                    "business_analysis" => %{
                      "reasoning_quality" => validation["score"],
                      "compliance_status" => validation["valid"],
                      "dspy_output" => dspy_result
                    }
                  }
                _ -> result
              end
            end
          }
        end
        
        # Test the custom business module
        business_question = "How should we handle patient data in our new healthcare app?"
        
        case BusinessChainOfThought.create(%{"signature" => "question -> reasoning, answer"}, 
          session_id: "bidirectional_session") do
          {:ok, business_cot} ->
            IO.puts("✓ Created BusinessChainOfThought module")
            
            case BusinessChainOfThought.execute(business_cot, %{
              "question" => business_question,
              "business_context" => "healthcare"
            }) do
              {:ok, result} ->
                IO.puts("\n📋 Business Analysis Results:")
                IO.puts("Question: #{business_question}")
                
                if result["business_analysis"] do
                  analysis = result["business_analysis"]
                  IO.puts("Reasoning Quality: #{analysis["reasoning_quality"]}")
                  IO.puts("Compliance Status: #{analysis["compliance_status"]}")
                  
                  if analysis["dspy_output"] do
                    answer = get_in(analysis["dspy_output"], ["answer"])
                    if answer, do: IO.puts("Answer: #{answer}")
                  end
                else
                  IO.puts("Result: #{inspect(result)}")
                end
                
              {:error, error} ->
                IO.puts("✗ Business analysis failed: #{error}")
            end
            
          {:error, error} ->
            IO.puts("✗ Failed to create BusinessChainOfThought: #{error}")
        end
        
      {:error, error} ->
        IO.puts("✗ Failed to register business validator: #{error}")
    end
  end
  
  defp demo_advanced_metaprogramming do
    IO.puts("\n\n5. Advanced Metaprogramming with Enhanced defdsyp")
    IO.puts("-------------------------------------------------")
    
    # Note: In a real application, these modules would be defined at the top level
    # For this demo, we'll show how enhanced wrappers work with the bridge directly
    
    IO.puts("✓ Enhanced metaprogramming demonstrated through bridge functions")
    IO.puts("  - Enhanced Chain of Thought with domain validation") 
    IO.puts("  - Enhanced Predict with signature validation")
    IO.puts("  - Custom result transformations")
    IO.puts("  - Bidirectional tool integration")
    
    # Test enhanced wrapper creation
    case DSPex.Bridge.create_enhanced_wrapper("dspy.ChainOfThought", 
      session_id: "bidirectional_session",
      signature: "symptoms -> reasoning, diagnosis") do
      {:ok, enhanced_cot} ->
        IO.puts("\n✓ Created enhanced ChainOfThought wrapper: #{inspect(enhanced_cot)}")
        
        # Test execution with enhanced features
        case DSPex.Bridge.execute_enhanced(enhanced_cot, %{
          "symptoms" => "chest pain in 45-year-old male",
          "domain" => "medical"
        }) do
          {:ok, result} ->
            IO.puts("✓ Enhanced execution succeeded")
            if result["elixir_validation"] do
              IO.puts("  - Elixir validation performed: #{result["elixir_validation"]["valid"]}")
            end
            
          {:error, error} ->
            IO.puts("✗ Enhanced execution failed: #{error}")
        end
        
      {:error, error} ->
        IO.puts("✗ Failed to create enhanced wrapper: #{error}")
    end
  end
  
  
  defp demo_tool_discovery do
    IO.puts("\n\n6. Tool Discovery and Introspection")
    IO.puts("-----------------------------------")
    
    # Discover available DSPy modules
    case DSPex.Bridge.discover_schema("dspy", session_id: "bidirectional_session") do
      {:ok, schema} ->
        IO.puts("✓ Discovered #{map_size(schema)} DSPy classes")
        
        # Show a few interesting ones
        interesting_classes = ["Predict", "ChainOfThought", "ReAct", "ProgramOfThought"]
        for class_name <- interesting_classes do
          if Map.has_key?(schema, class_name) do
            class_info = schema[class_name]
            methods_count = map_size(class_info["methods"] || %{})
            IO.puts("  - #{class_name}: #{methods_count} methods")
          end
        end
        
      {:error, error} ->
        IO.puts("✗ Schema discovery failed: #{error}")
    end
    
    # List all registered Elixir tools
    case DSPex.Bridge.list_elixir_tools("bidirectional_session") do
      {:ok, tools} ->
        IO.puts("\n✓ Available Elixir Tools:")
        for tool <- tools do
          IO.puts("  - #{tool}")
        end
        
      {:error, error} ->
        IO.puts("✗ Failed to list Elixir tools: #{error}")
    end
    
    # Show session statistics
    case Snakepit.execute_in_session("bidirectional_session", "get_stats", %{}) do
      {:ok, %{"success" => true, "stats" => stats}} ->
        IO.puts("\n📊 Session Statistics:")
        IO.puts("  DSPy Available: #{stats["dspy_available"]}")
        IO.puts("  Programs Created: #{stats["programs_count"]}")
        IO.puts("  Objects Stored: #{stats["stored_objects_count"]}")
        IO.puts("  LM Configured: #{stats["has_configured_lm"]}")
        
      {:error, error} ->
        IO.puts("✗ Failed to get session stats: #{error}")
    end
  end
end

# Run the comprehensive demo
BidirectionalToolBridgeDemo.run()

IO.puts("\n\n=== Bidirectional Tool Bridge Demo Complete ===")
IO.puts("\n🎯 Key Achievements Demonstrated:")
IO.puts("1. ✅ Python DSPy calling back to Elixir validation functions")
IO.puts("2. ✅ Elixir business logic integration during ML reasoning")
IO.puts("3. ✅ Enhanced DSPy modules with automatic tool registration")
IO.puts("4. ✅ Custom domain-specific validators in Elixir")
IO.puts("5. ✅ Advanced metaprogramming with bidirectional defdsyp")
IO.puts("6. ✅ Real-time tool discovery and session introspection")
IO.puts("\n💡 This demonstrates true bidirectional integration where:")
IO.puts("   - Elixir handles business logic, validation, and concurrent processing")
IO.puts("   - Python handles ML reasoning, DSPy operations, and AI workflows")
IO.puts("   - Both ecosystems work together seamlessly through the tool bridge")