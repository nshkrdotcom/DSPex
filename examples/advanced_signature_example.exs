#!/usr/bin/env elixir

# Advanced DSPy-Integrated Signatures Example
# Demonstrates complex multi-step reasoning, data pipelines, and real-world business scenarios
# Run with: elixir examples/advanced_signature_example.exs

# Configure for single mode (signatures work with single adapter)
Application.put_env(:dspex, :pooling_enabled, false)

Mix.install([
  {:dspex, path: "."}
])

# Configure logging and test mode
Logger.configure(level: :info)
System.put_env("TEST_MODE", "mock_adapter")

# Start the application
{:ok, _} = Application.ensure_all_started(:dspex)

defmodule AdvancedSignatureExample do
  @moduledoc """
  Advanced DSPy signature examples demonstrating complex business scenarios:
  
  1. Document Intelligence Pipeline - Multi-step analysis with reasoning chains
  2. Customer Support Assistant - Context-aware response generation
  3. Financial Risk Assessment - Data-driven decision making
  4. Product Recommendation Engine - Personalized ML-driven suggestions
  5. Content Moderation System - Multi-dimensional safety analysis
  6. Market Research Pipeline - Competitive analysis and insights
  """

  require Logger
  alias DSPex.Adapters.Registry

  # ====================================================================
  # DOCUMENT INTELLIGENCE PIPELINE
  # Complex multi-step reasoning with intermediate outputs
  # ====================================================================

  def document_intelligence_signature do
    %{
      name: "DocumentIntelligenceSignature",
      description: "Advanced document analysis with classification, entity extraction, risk assessment, and actionable insights",
      inputs: [
        %{
          name: "document_text",
          type: "string", 
          description: "Raw document content to analyze (contracts, reports, emails, etc.)"
        },
        %{
          name: "analysis_depth",
          type: "string",
          description: "Analysis depth: 'surface' for basic info, 'deep' for comprehensive analysis, 'forensic' for detailed investigation"
        },
        %{
          name: "business_context",
          type: "string",
          description: "Business context: 'legal', 'financial', 'technical', 'marketing', 'hr', 'compliance'"
        }
      ],
      outputs: [
        %{
          name: "document_type",
          type: "string",
          description: "Classified document type (contract, report, proposal, correspondence, etc.)"
        },
        %{
          name: "key_entities",
          type: "string",
          description: "Extracted entities: people, organizations, dates, amounts, locations, etc."
        },
        %{
          name: "risk_assessment",
          type: "string",
          description: "Risk analysis: potential issues, compliance concerns, red flags, severity level"
        },
        %{
          name: "action_items",
          type: "string",
          description: "Specific actionable next steps based on document analysis"
        },
        %{
          name: "urgency_level",
          type: "string",
          description: "Business urgency: 'immediate', 'high', 'medium', 'low', 'routine'"
        },
        %{
          name: "confidence_score",
          type: "string",
          description: "Overall confidence in analysis results (0.0-1.0)"
        }
      ]
    }
  end

  def run_document_intelligence_example do
    Logger.info("📄 Advanced Document Intelligence Pipeline")
    Logger.info("==========================================")
    
    adapter = Registry.get_adapter(:python_port)
    configure_language_model(adapter)
    
    signature = document_intelligence_signature()
    
    {:ok, prog_id} = adapter.create_program(%{
      id: "doc_intel_#{System.unique_integer([:positive])}",
      signature: signature
    })
    
    # Complex document scenarios
    documents = [
      %{
        document_text: """
        CONFIDENTIAL ACQUISITION AGREEMENT
        
        This Agreement is entered into on January 15, 2024, between TechCorp Inc. (Buyer) 
        and DataSolutions LLC (Seller) for the acquisition of all assets including 
        proprietary algorithms, customer databases containing 2.3M records, and 47 patents.
        
        Purchase Price: $125,000,000 USD payable in three installments.
        Due Diligence Period: 90 days from execution.
        
        CRITICAL: This transaction must close by March 31, 2024, or penalty clauses 
        activate ($2M daily). Regulatory approval from FTC required within 60 days.
        
        Key Personnel: Dr. Sarah Chen (CTO), Michael Rodriguez (Head of AI), 
        team of 23 engineers must remain for minimum 24 months post-close.
        """,
        analysis_depth: "forensic",
        business_context: "legal"
      },
      
      %{
        document_text: """
        INCIDENT REPORT - SECURITY BREACH
        Date: 2024-07-16 03:47 AM UTC
        
        Automated systems detected unauthorized access to customer database servers
        between 03:15-03:42 AM. Affected systems: production DB cluster (db-prod-01 through db-prod-05).
        
        Preliminary Assessment:
        - 847,392 customer records potentially accessed
        - Payment information exposure: HIGH PROBABILITY
        - Duration of access: 27 minutes
        - Entry vector: SQL injection via payment gateway API
        
        Immediate Actions Taken:
        - Database cluster isolated at 03:42 AM
        - Payment processing suspended
        - Legal team notified
        - Incident response team activated
        
        URGENT: GDPR notification requirements - 72 hour deadline = July 19, 2024 03:47 AM
        """,
        analysis_depth: "deep",
        business_context: "compliance"
      }
    ]
    
    Enum.each(documents, fn doc ->
      Logger.info("\n🔍 Analyzing Document:")
      Logger.info("   Context: #{doc.business_context} | Depth: #{doc.analysis_depth}")
      Logger.info("   Preview: #{String.slice(doc.document_text, 0, 100)}...")
      
      case adapter.execute_program(prog_id, doc) do
        {:ok, result} ->
          outputs = extract_outputs(result)
          
          Logger.info("✅ Document Intelligence Results:")
          Logger.info("   📋 Type: #{get_output(outputs, "document_type")}")
          Logger.info("   👥 Entities: #{get_output(outputs, "key_entities")}")
          Logger.info("   ⚠️  Risk: #{get_output(outputs, "risk_assessment")}")
          Logger.info("   🎯 Actions: #{get_output(outputs, "action_items")}")
          Logger.info("   ⏰ Urgency: #{get_output(outputs, "urgency_level")}")
          Logger.info("   📊 Confidence: #{get_output(outputs, "confidence_score")}")
          
        {:error, reason} ->
          Logger.warning("❌ Analysis failed: #{inspect(reason)}")
      end
    end)
  end

  # ====================================================================
  # CUSTOMER SUPPORT ASSISTANT
  # Context-aware response generation with sentiment analysis
  # ====================================================================

  def customer_support_signature do
    %{
      name: "CustomerSupportAssistantSignature",
      description: "AI-powered customer support with context awareness, sentiment analysis, and solution recommendation",
      inputs: [
        %{
          name: "customer_message",
          type: "string",
          description: "Customer's inquiry, complaint, or request for assistance"
        },
        %{
          name: "customer_tier",
          type: "string",
          description: "Customer tier: 'premium', 'business', 'standard', 'trial'"
        },
        %{
          name: "interaction_history",
          type: "string",
          description: "Previous interaction context and conversation history"
        },
        %{
          name: "product_context",
          type: "string",
          description: "Relevant product/service context: features, limitations, known issues"
        }
      ],
      outputs: [
        %{
          name: "sentiment_analysis",
          type: "string",
          description: "Customer sentiment: frustrated, neutral, satisfied, angry, confused"
        },
        %{
          name: "issue_classification",
          type: "string",
          description: "Issue type: technical, billing, feature_request, complaint, general_inquiry"
        },
        %{
          name: "suggested_response",
          type: "string",
          description: "Personalized response addressing customer's specific concerns and tier"
        },
        %{
          name: "escalation_needed",
          type: "string",
          description: "Escalation requirement: 'none', 'technical', 'billing', 'management', 'legal'"
        },
        %{
          name: "resolution_steps",
          type: "string",
          description: "Step-by-step resolution process tailored to customer tier and issue"
        },
        %{
          name: "follow_up_timeline",
          type: "string",
          description: "Recommended follow-up schedule based on issue severity and customer tier"
        }
      ]
    }
  end

  def run_customer_support_example do
    Logger.info("🎧 Advanced Customer Support Assistant")
    Logger.info("=====================================")
    
    adapter = Registry.get_adapter(:python_port)
    configure_language_model(adapter)
    
    signature = customer_support_signature()
    
    {:ok, prog_id} = adapter.create_program(%{
      id: "support_#{System.unique_integer([:positive])}",
      signature: signature
    })
    
    # Complex customer support scenarios
    support_cases = [
      %{
        customer_message: """
        This is absolutely ridiculous! I've been trying to access my account for 3 DAYS 
        and your system keeps saying my password is wrong. I KNOW my password! I've been 
        using the same one for 2 years. Now I'm locked out completely and can't access 
        my business data. This is costing me money every hour this isn't fixed!
        
        I pay $2,400/month for your premium service and this is what I get? 
        I need this fixed NOW or I'm switching to your competitor.
        """,
        customer_tier: "premium",
        interaction_history: "Previous tickets: password reset (6 months ago), billing inquiry (3 months ago). Usually satisfied customer, first major complaint.",
        product_context: "Enterprise authentication system with 2FA, account lockout after 5 failed attempts, premium SLA: 1-hour response time"
      },
      
      %{
        customer_message: """
        Hi there! I'm loving the new dashboard updates, but I noticed that the export 
        feature seems to be missing some of the filtering options we had before. 
        Specifically, I can't filter by date range when exporting to CSV anymore.
        
        This isn't urgent, but our team uses this feature weekly for reports. 
        Is this a known issue or is there a workaround I'm missing?
        
        Thanks for all the great work on the platform!
        """,
        customer_tier: "business",
        interaction_history: "Regular user, typically opens 1-2 tickets monthly for feature questions. Generally positive feedback.",
        product_context: "Dashboard v2.3 released last week, known issue with CSV export filters, workaround available via API"
      }
    ]
    
    Enum.each(support_cases, fn case_data ->
      Logger.info("\n📞 Processing Support Case:")
      Logger.info("   Tier: #{case_data.customer_tier}")
      Logger.info("   Message: #{String.slice(case_data.customer_message, 0, 100)}...")
      
      case adapter.execute_program(prog_id, case_data) do
        {:ok, result} ->
          outputs = extract_outputs(result)
          
          Logger.info("✅ Support Analysis Results:")
          Logger.info("   😊 Sentiment: #{get_output(outputs, "sentiment_analysis")}")
          Logger.info("   🏷️  Issue Type: #{get_output(outputs, "issue_classification")}")
          Logger.info("   💬 Response: #{String.slice(get_output(outputs, "suggested_response"), 0, 150)}...")
          Logger.info("   ⬆️  Escalation: #{get_output(outputs, "escalation_needed")}")
          Logger.info("   🔧 Steps: #{get_output(outputs, "resolution_steps")}")
          Logger.info("   📅 Follow-up: #{get_output(outputs, "follow_up_timeline")}")
          
        {:error, reason} ->
          Logger.warning("❌ Support analysis failed: #{inspect(reason)}")
      end
    end)
  end

  # ====================================================================
  # FINANCIAL RISK ASSESSMENT
  # Data-driven decision making with quantitative analysis
  # ====================================================================

  def financial_risk_signature do
    %{
      name: "FinancialRiskAssessmentSignature",
      description: "Comprehensive financial risk analysis with quantitative metrics, scenario modeling, and investment recommendations",
      inputs: [
        %{
          name: "financial_data",
          type: "string",
          description: "Financial metrics: revenue, expenses, cash flow, debt, market metrics, etc."
        },
        %{
          name: "market_conditions",
          type: "string",
          description: "Current market environment: economic indicators, sector trends, competitive landscape"
        },
        %{
          name: "investment_timeline",
          type: "string",
          description: "Investment horizon: 'short_term' (< 1 year), 'medium_term' (1-5 years), 'long_term' (5+ years)"
        },
        %{
          name: "risk_tolerance",
          type: "string",
          description: "Risk appetite: 'conservative', 'moderate', 'aggressive', 'speculative'"
        }
      ],
      outputs: [
        %{
          name: "risk_score",
          type: "string",
          description: "Overall risk score (1-10, where 10 is highest risk)"
        },
        %{
          name: "key_risks",
          type: "string",
          description: "Primary risk factors: market risk, credit risk, liquidity risk, operational risk"
        },
        %{
          name: "scenario_analysis",
          type: "string",
          description: "Bull/base/bear case scenarios with probability estimates and potential outcomes"
        },
        %{
          name: "investment_recommendation",
          type: "string",
          description: "Specific investment advice based on risk profile and market conditions"
        },
        %{
          name: "hedge_strategies",
          type: "string",
          description: "Risk mitigation recommendations and hedging approaches"
        },
        %{
          name: "monitoring_metrics",
          type: "string",
          description: "Key performance indicators to track for ongoing risk management"
        }
      ]
    }
  end

  def run_financial_risk_example do
    Logger.info("💰 Advanced Financial Risk Assessment")
    Logger.info("====================================")
    
    adapter = Registry.get_adapter(:python_port)
    configure_language_model(adapter)
    
    signature = financial_risk_signature()
    
    {:ok, prog_id} = adapter.create_program(%{
      id: "finance_#{System.unique_integer([:positive])}",
      signature: signature
    })
    
    # Complex financial scenarios
    financial_cases = [
      %{
        financial_data: """
        Company: TechStartup AI Inc.
        Revenue (TTM): $45M (180% YoY growth)
        Expenses: $52M (R&D: $28M, Sales: $15M, Operations: $9M)
        Cash Position: $23M
        Burn Rate: $7M/month
        Runway: 3.3 months
        Recent Funding: Series B $80M (6 months ago)
        Valuation: $800M
        Debt: $5M convertible notes
        Employee Count: 340 (grew from 85 last year)
        Customer Growth: 340% YoY, Churn: 8% monthly
        """,
        market_conditions: "High interest rates (5.5%), VC funding down 60% YoY, AI sector overvalued by 40%, economic uncertainty, tech layoffs increasing",
        investment_timeline: "medium_term",
        risk_tolerance: "aggressive"
      },
      
      %{
        financial_data: """
        Portfolio: Diversified Real Estate Investment
        Properties: 12 commercial, 8 residential (total value $15.2M)
        Rental Income: $185K/month
        Expenses: $47K/month (maintenance, taxes, insurance, management)
        Occupancy Rate: 92%
        Debt: $8.4M total (avg rate 4.2%, 15-year avg remaining)
        Cash Reserves: $450K
        Market Appreciation: 8.5% YTD, 45% over 5 years
        Geographic Distribution: 60% Austin, 25% Dallas, 15% Houston
        """,
        market_conditions: "Rising interest rates, housing market cooling, commercial real estate stress, inflation affecting construction costs, Texas population growth continuing",
        investment_timeline: "long_term",
        risk_tolerance: "moderate"
      }
    ]
    
    Enum.each(financial_cases, fn case_data ->
      Logger.info("\n📊 Analyzing Financial Case:")
      Logger.info("   Timeline: #{case_data.investment_timeline} | Risk Tolerance: #{case_data.risk_tolerance}")
      Logger.info("   Data Preview: #{String.slice(case_data.financial_data, 0, 100)}...")
      
      case adapter.execute_program(prog_id, case_data) do
        {:ok, result} ->
          outputs = extract_outputs(result)
          
          Logger.info("✅ Financial Risk Assessment:")
          Logger.info("   🎯 Risk Score: #{get_output(outputs, "risk_score")}")
          Logger.info("   ⚠️  Key Risks: #{get_output(outputs, "key_risks")}")
          Logger.info("   📈 Scenarios: #{String.slice(get_output(outputs, "scenario_analysis"), 0, 150)}...")
          Logger.info("   💡 Recommendation: #{String.slice(get_output(outputs, "investment_recommendation"), 0, 150)}...")
          Logger.info("   🛡️  Hedging: #{get_output(outputs, "hedge_strategies")}")
          Logger.info("   📊 Monitoring: #{get_output(outputs, "monitoring_metrics")}")
          
        {:error, reason} ->
          Logger.warning("❌ Financial analysis failed: #{inspect(reason)}")
      end
    end)
  end

  # ====================================================================
  # PRODUCT RECOMMENDATION ENGINE
  # Personalized ML-driven recommendations
  # ====================================================================

  def product_recommendation_signature do
    %{
      name: "ProductRecommendationSignature",
      description: "Advanced product recommendation engine with personalization, cross-sell opportunities, and behavioral prediction",
      inputs: [
        %{
          name: "user_profile",
          type: "string",
          description: "User demographics, preferences, purchase history, and behavioral data"
        },
        %{
          name: "browsing_session",
          type: "string",
          description: "Current session data: pages viewed, time spent, products examined, search queries"
        },
        %{
          name: "inventory_context",
          type: "string",
          description: "Available inventory, pricing, promotions, seasonal factors, business objectives"
        },
        %{
          name: "recommendation_goal",
          type: "string",
          description: "Primary objective: 'conversion', 'upsell', 'cross_sell', 'retention', 'discovery'"
        }
      ],
      outputs: [
        %{
          name: "primary_recommendations",
          type: "string",
          description: "Top 5 product recommendations with confidence scores and reasoning"
        },
        %{
          name: "cross_sell_opportunities",
          type: "string",
          description: "Complementary products and bundle suggestions based on current interest"
        },
        %{
          name: "personalization_insights",
          type: "string",
          description: "User behavior analysis and personalization factors driving recommendations"
        },
        %{
          name: "conversion_probability",
          type: "string",
          description: "Estimated likelihood of purchase for each recommended product"
        },
        %{
          name: "optimal_timing",
          type: "string",
          description: "Best time to present recommendations based on user behavior patterns"
        },
        %{
          name: "a_b_test_variant",
          type: "string",
          description: "Suggested A/B test variations for recommendation optimization"
        }
      ]
    }
  end

  def run_product_recommendation_example do
    Logger.info("🛒 Advanced Product Recommendation Engine")
    Logger.info("========================================")
    
    adapter = Registry.get_adapter(:python_port)
    configure_language_model(adapter)
    
    signature = product_recommendation_signature()
    
    {:ok, prog_id} = adapter.create_program(%{
      id: "recommendations_#{System.unique_integer([:positive])}",
      signature: signature
    })
    
    # Complex recommendation scenarios
    recommendation_cases = [
      %{
        user_profile: """
        User ID: premium_customer_8473
        Demographics: 34, Female, Software Engineer, San Francisco, $145K income
        Purchase History: 23 orders in 18 months, $2,340 lifetime value
        Preferences: Eco-friendly products, premium brands, tech gadgets, fitness equipment
        Recent Purchases: Wireless earbuds ($280), yoga mat ($85), protein powder ($45)
        Behavioral Patterns: Shops evening/weekends, researches extensively, price-sensitive for non-essentials
        Engagement: High email open rate, follows 8 product categories, social media influencer (12K followers)
        """,
        browsing_session: """
        Session Duration: 23 minutes
        Pages Viewed: Home → Fitness → Smartwatches → Product Compare (3 models) → Reviews
        Products Examined: Apple Watch Series 9, Garmin Fenix 7, Samsung Galaxy Watch 6
        Search Queries: "fitness tracker sleep monitoring", "waterproof smartwatch"
        Cart Status: Empty, but added/removed Garmin Fenix 7 twice
        Exit Intent: 75% probability (lingering on checkout page for 3 minutes)
        """,
        inventory_context: "Black Friday sale (25% off), high smartwatch inventory, low wireless earbud stock, new product launch next week",
        recommendation_goal: "conversion"
      },
      
      %{
        user_profile: """
        User ID: new_business_customer_2847
        Demographics: B2B Office Manager, 150-person company, $2M annual procurement budget
        Purchase History: First-time buyer, researching for 6 weeks
        Requirements: Office equipment, bulk ordering, net-30 payment terms, delivery coordination
        Decision Making: Committee-based, 3-week approval cycle, cost-conscious but quality-focused
        Company Growth: Expanding by 40% this year, new office space, hybrid work model
        """,
        browsing_session: """
        Session Duration: 47 minutes
        Pages Viewed: B2B Portal → Office Furniture → Standing Desks → Bulk Pricing → Case Studies
        Products Examined: 12 standing desk models, 6 office chair options, meeting room solutions
        Download Activity: 4 product spec sheets, pricing guide, installation manual
        Form Interactions: Started quote request (75% complete), requested sales consultation
        """,
        inventory_context: "Q4 inventory clearance, volume discounts available, installation team capacity high, B2B goal: increase average order value",
        recommendation_goal: "upsell"
      }
    ]
    
    Enum.each(recommendation_cases, fn case_data ->
      Logger.info("\n🎯 Processing Recommendation Request:")
      Logger.info("   Goal: #{case_data.recommendation_goal}")
      Logger.info("   User Preview: #{String.slice(case_data.user_profile, 0, 100)}...")
      Logger.info("   Session Preview: #{String.slice(case_data.browsing_session, 0, 100)}...")
      
      case adapter.execute_program(prog_id, case_data) do
        {:ok, result} ->
          outputs = extract_outputs(result)
          
          Logger.info("✅ Recommendation Results:")
          Logger.info("   🏆 Primary: #{String.slice(get_output(outputs, "primary_recommendations"), 0, 150)}...")
          Logger.info("   🔗 Cross-sell: #{String.slice(get_output(outputs, "cross_sell_opportunities"), 0, 150)}...")
          Logger.info("   🧠 Insights: #{String.slice(get_output(outputs, "personalization_insights"), 0, 150)}...")
          Logger.info("   📊 Conversion: #{get_output(outputs, "conversion_probability")}")
          Logger.info("   ⏰ Timing: #{get_output(outputs, "optimal_timing")}")
          Logger.info("   🧪 A/B Test: #{get_output(outputs, "a_b_test_variant")}")
          
        {:error, reason} ->
          Logger.warning("❌ Recommendation failed: #{inspect(reason)}")
      end
    end)
  end

  # ====================================================================
  # MASTER EXAMPLE RUNNER
  # ====================================================================

  def run_all_advanced_examples do
    Logger.info("🚀 Advanced DSPy-Integrated Signatures Showcase")
    Logger.info("===============================================")
    Logger.info("Demonstrating complex, real-world business scenarios")
    Logger.info("with multi-step reasoning and comprehensive outputs.\n")
    
    run_document_intelligence_example()
    Process.sleep(2000)
    
    run_customer_support_example()
    Process.sleep(2000)
    
    run_financial_risk_example()
    Process.sleep(2000)
    
    run_product_recommendation_example()
    
    Logger.info("\n🎉 Advanced Examples Complete!")
    Logger.info("💡 These examples showcase DSPy's power for complex business logic:")
    Logger.info("   • Multi-step reasoning chains")
    Logger.info("   • Context-aware decision making") 
    Logger.info("   • Industry-specific knowledge application")
    Logger.info("   • Quantitative analysis integration")
    Logger.info("   • Real-time personalization")
    Logger.info("   • Risk assessment and scenario modeling")
  end

  # ====================================================================
  # HELPER FUNCTIONS
  # ====================================================================

  defp configure_language_model(adapter) do
    api_key = System.get_env("GEMINI_API_KEY")
    
    if is_nil(api_key) or api_key == "" do
      Logger.warning("⚠️  GEMINI_API_KEY not set, using mock responses")
    end
    
    case adapter.configure_lm(%{
      model: "gemini-1.5-flash",
      api_key: api_key || "mock-key",
      provider: "google"
    }) do
      :ok -> 
        Logger.info("✅ Language model configured successfully")
      {:error, reason} -> 
        Logger.warning("⚠️  LM configuration issue: #{inspect(reason)}")
    end
  end

  defp extract_outputs(result) do
    result["outputs"] || result[:outputs] || result
  end

  defp get_output(outputs, key) do
    outputs[key] || outputs[String.to_atom(key)] || "N/A"
  end
end

# ====================================================================
# MAIN EXECUTION
# ====================================================================

IO.puts("🎯 Advanced DSPy-Integrated Signatures Example")
IO.puts("==============================================")
IO.puts("This example demonstrates sophisticated business scenarios that go")
IO.puts("far beyond simple 'question → answer' patterns:\n")

IO.puts("📄 Document Intelligence - Complex multi-step analysis")
IO.puts("🎧 Customer Support - Context-aware response generation")  
IO.puts("💰 Financial Risk Assessment - Data-driven decision making")
IO.puts("🛒 Product Recommendations - Personalized ML suggestions")
IO.puts("")

IO.puts("🔧 Technical Features Demonstrated:")
IO.puts("   • Multi-input, multi-output signatures")
IO.puts("   • Complex business logic integration")
IO.puts("   • Real-world data processing pipelines")
IO.puts("   • Context-aware reasoning chains")
IO.puts("   • Industry-specific analysis patterns")
IO.puts("")

IO.puts("🚀 Running Advanced Examples...")
IO.puts("================================")

AdvancedSignatureExample.run_all_advanced_examples()

# Ensure proper cleanup by explicitly stopping the application
IO.puts("\n🛑 Stopping DSPex application to ensure cleanup...")
Application.stop(:dspex)
IO.puts("\n🎉 All examples complete - application stopped cleanly!")