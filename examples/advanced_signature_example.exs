#!/usr/bin/env elixir

# Advanced Native Signatures Example
# Demonstrates complex multi-step reasoning and real-world business scenarios
# Run with: elixir examples/advanced_signature_example.exs

Mix.install([
  {:dspex, path: Path.expand("..", __DIR__)}
])

defmodule AdvancedSignatureExample do
  @moduledoc """
  Advanced signature examples demonstrating complex business scenarios with DSPex native features.
  """

  alias DSPex.{Native, LLM}

  def run do
    IO.puts("🎯 Advanced Native Signatures Example")
    IO.puts("=====================================\n")
    
    # Start DSPex
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    # Configure LLM client
    client = configure_client()
    
    # Run examples
    demo_document_intelligence(client)
    demo_customer_support(client)
    demo_financial_risk_assessment(client)
    demo_product_recommendations(client)
    
    IO.puts("\n✅ === Advanced Examples Complete ===")
  end

  # === Client Configuration ===
  
  defp configure_client do
    # Load config
    config_path = Path.join(__DIR__, "config.exs")
    config_data = Code.eval_file(config_path) |> elem(0)
    api_key = config_data.api_key
    
    config = if api_key && api_key != "" do
      IO.puts("🔑 Using Gemini with API key")
      [
        adapter: :gemini,
        provider: :gemini,
        api_key: api_key,
        model: config_data.model,
        temperature: 0.7,
        max_tokens: 2048
      ]
    else
      IO.puts("⚠️  GEMINI_API_KEY not set, using mock adapter")
      [
        adapter: :mock,
        mock_responses: %{
          "classification" => "contract",
          "entities" => "Acme Corp, XYZ Ltd, $1,000,000, 2024-01-15",
          "risk_level" => "medium", 
          "summary" => "Service agreement between Acme Corp and XYZ Ltd",
          "sentiment" => "frustrated",
          "priority" => "high",
          "response" => "I understand your frustration. Let me help resolve this issue.",
          "credit_score" => "720",
          "recommendation" => "conditional approval",
          "confidence" => "0.85",
          "products" => "Wireless Headphones, Phone Case, Charging Cable",
          "scores" => "0.92, 0.87, 0.81",
          "revenue_impact" => "125.50"
        }
      ]
    end
    
    case LLM.Client.new(config) do
      {:ok, client} ->
        IO.puts("✅ LLM client configured\n")
        client
      {:error, reason} ->
        IO.puts("❌ Failed to configure client: #{inspect(reason)}")
        # Use mock as fallback
        {:ok, mock} = LLM.Client.new([adapter: :mock])
        mock
    end
  end

  # === Document Intelligence ===
  
  defp demo_document_intelligence(client) do
    IO.puts("\n📄 === Document Intelligence Pipeline ===")
    
    # Parse complex signature
    signature_str = """
    document: str, context: str, analysis_type: str -> 
    classification: str, entities: list[str], risk_level: str, summary: str
    """
    
    {:ok, _signature} = Native.Signature.parse(signature_str)
    IO.puts("📝 Signature: #{String.trim(signature_str)}")
    
    # Compile template
    template_str = """
    Analyze the following document:

    Document: <%= @document %>
    Context: <%= @context %>
    Analysis Type: <%= @analysis_type %>

    Provide:
    1. Classification: What type of document is this?
    2. Entities: List key entities (people, organizations, dates, amounts)
    3. Risk Level: Assess risk level (low/medium/high)
    4. Summary: Brief summary of the document

    Format your response as:
    Classification: [type]
    Entities: [comma-separated list]
    Risk Level: [level]
    Summary: [brief summary]
    """
    
    {:ok, template} = Native.Template.compile(template_str)
    
    # Example document
    document = """
    SERVICE AGREEMENT
    This agreement is entered into on January 15, 2024, between Acme Corporation 
    ("Service Provider") and XYZ Limited ("Client") for the provision of software 
    development services. Total contract value: $1,000,000. Payment terms: Net 30.
    Liability limited to contract value. No force majeure clause included.
    """
    
    vars = %{
      document: document,
      context: "Legal compliance review",
      analysis_type: "Contract analysis"
    }
    
    # Render and execute
    prompt = template.(vars)
    
    case LLM.Client.generate(client, prompt) do
      {:ok, response} ->
        IO.puts("\n✅ Analysis Results:")
        IO.puts(response.content)
        
        # In real usage, you would parse the structured output
        # and validate against the signature
        
      {:error, reason} ->
        IO.puts("❌ Analysis failed: #{inspect(reason)}")
    end
  end

  # === Customer Support ===
  
  defp demo_customer_support(client) do
    IO.puts("\n\n🎧 === Customer Support Assistant ===")
    
    # Parse signature
    signature_str = """
    customer_message: str, history: list[str], account_type: str -> 
    sentiment: str, priority: str, response: str
    """
    
    {:ok, _signature} = Native.Signature.parse(signature_str)
    IO.puts("📝 Signature: #{String.trim(signature_str)}")
    
    # Create template
    template_str = """
    Customer Support Request:
    
    Message: <%= @customer_message %>
    Account Type: <%= @account_type %>
    Recent History:
    <%= for msg <- @history do %>
    - <%= msg %>
    <% end %>
    
    Analyze and respond:
    1. Sentiment: What is the customer's emotional state?
    2. Priority: How urgent is this issue? (low/medium/high/critical)
    3. Response: Provide a helpful, empathetic response
    
    Format as:
    Sentiment: [sentiment]
    Priority: [priority]
    Response: [response text]
    """
    
    {:ok, template} = Native.Template.compile(template_str)
    
    # Example support case
    vars = %{
      customer_message: "I've been trying to reset my password for 2 hours! This is ridiculous!",
      account_type: "Premium",
      history: [
        "Attempted password reset 3 times",
        "Account locked due to failed attempts",
        "Previous ticket about login issues"
      ]
    }
    
    prompt = template.(vars)
    
    case LLM.Client.generate(client, prompt) do
      {:ok, response} ->
        IO.puts("\n✅ Support Analysis:")
        IO.puts(response.content)
        
      {:error, reason} ->
        IO.puts("❌ Support analysis failed: #{inspect(reason)}")
    end
  end

  # === Financial Risk Assessment ===
  
  defp demo_financial_risk_assessment(client) do
    IO.puts("\n\n💰 === Financial Risk Assessment ===")
    
    signature_str = """
    credit_history: str, income: float, debt: float, purpose: str -> 
    credit_score: int, recommendation: str, confidence: float
    """
    
    {:ok, _signature} = Native.Signature.parse(signature_str)
    IO.puts("📝 Signature: #{String.trim(signature_str)}")
    
    template_str = """
    Financial Assessment Request:
    
    Credit History: <%= @credit_history %>
    Annual Income: $<%= @income %>
    Total Debt: $<%= @debt %>
    Loan Purpose: <%= @purpose %>
    Debt-to-Income Ratio: <%= Float.round(@debt / @income * 100, 2) %>%
    
    Provide risk assessment:
    1. Estimated credit score (300-850)
    2. Recommendation (approve/conditional approval/decline)
    3. Confidence level (0.0-1.0)
    
    Format as:
    Credit Score: [score]
    Recommendation: [recommendation]
    Confidence: [confidence]
    """
    
    {:ok, template} = Native.Template.compile(template_str)
    
    vars = %{
      credit_history: "Generally good, one late payment 2 years ago",
      income: 85000.0,
      debt: 25000.0,
      purpose: "Home improvement loan"
    }
    
    prompt = template.(vars)
    
    case LLM.Client.generate(client, prompt) do
      {:ok, response} ->
        IO.puts("\n✅ Risk Assessment:")
        IO.puts(response.content)
        
      {:error, reason} ->
        IO.puts("❌ Risk assessment failed: #{inspect(reason)}")
    end
  end

  # === Product Recommendations ===
  
  defp demo_product_recommendations(client) do
    IO.puts("\n\n🛒 === Product Recommendation Engine ===")
    
    signature_str = """
    purchase_history: list[str], browsing_data: str, customer_segment: str -> 
    products: list[str], scores: list[float], revenue_impact: float
    """
    
    {:ok, _signature} = Native.Signature.parse(signature_str)
    IO.puts("📝 Signature: #{String.trim(signature_str)}")
    
    template_str = """
    Personalized Product Recommendations:
    
    Customer Segment: <%= @customer_segment %>
    Recent Purchases:
    <%= for item <- @purchase_history do %>
    - <%= item %>
    <% end %>
    Browsing Behavior: <%= @browsing_data %>
    
    Recommend products with:
    1. Top 3 product recommendations
    2. Relevance scores (0.0-1.0) for each
    3. Expected revenue impact
    
    Format as:
    Products: [product1, product2, product3]
    Scores: [score1, score2, score3]
    Revenue Impact: [dollar amount]
    """
    
    {:ok, template} = Native.Template.compile(template_str)
    
    vars = %{
      customer_segment: "Tech Enthusiast",
      purchase_history: ["Smartphone", "Bluetooth Speaker", "USB-C Cable"],
      browsing_data: "Viewed headphones 5x, cases 3x, chargers 2x in last week"
    }
    
    prompt = template.(vars)
    
    case LLM.Client.generate(client, prompt) do
      {:ok, response} ->
        IO.puts("\n✅ Recommendations:")
        IO.puts(response.content)
        
        # Would validate the output format matches the signature
        
      {:error, reason} ->
        IO.puts("❌ Recommendation failed: #{inspect(reason)}")
    end
  end
end

# Run the example
AdvancedSignatureExample.run()