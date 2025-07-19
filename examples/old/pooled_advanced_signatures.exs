#!/usr/bin/env elixir

# Pooled Advanced DSPy-Integrated Signatures Example
# Demonstrates complex multi-step reasoning with 5-worker pool for concurrent processing
# Run with: elixir examples/pooled_advanced_signatures_fixed.exs

# Configure pooling with 5 workers BEFORE loading DSPex
Application.put_env(:dspex, :pooling_enabled, true)
Application.put_env(:dspex, :pool_config, %{
  v2_enabled: false,
  v3_enabled: true,
  pool_size: 5  # 5 workers for concurrent signature processing
})

Mix.install([
  {:dspex, path: "."}
])

# Configure logging and test mode
Logger.configure(level: :info)
System.put_env("TEST_MODE", "mock_adapter")

# Start the application
{:ok, _} = Application.ensure_all_started(:dspex)

defmodule PooledAdvancedSignatureExample do
  @moduledoc """
  Pooled version of Advanced DSPy signature examples with 5 concurrent workers:
  
  1. Document Intelligence Pipeline - Multi-step analysis with reasoning chains
  2. Customer Support Assistant - Context-aware response generation
  3. Financial Risk Assessment - Data-driven decision making
  4. Product Recommendation Engine - Personalized ML-driven suggestions
  
  Demonstrates concurrent processing of multiple requests using pool workers.
  """

  require Logger

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
    Logger.info("📄 Advanced Document Intelligence Pipeline (Pooled)")
    Logger.info("=================================================")
    
    # Configure language model via pool
    configure_language_model()
    
    signature = document_intelligence_signature()
    
    # Use a consistent session for this entire signature workflow
    session_id = "doc_intel_session_#{System.unique_integer([:positive])}"
    {:ok, prog_id_result} = DSPex.Python.Pool.execute_in_session(session_id, "create_program", %{
      id: "doc_intel_#{System.unique_integer([:positive])}",
      signature: signature
    })
    prog_id = prog_id_result["program_id"]
    
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
        business_context: "legal",
        worker_id: 1
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
        business_context: "compliance",
        worker_id: 2
      },
      
      %{
        document_text: """
        Q3 2024 FINANCIAL REPORT - PRELIMINARY
        
        Revenue: $45.3M (+23% YoY, +8% QoQ)
        Operating Expenses: $38.7M (R&D: $18.2M, Sales: $12.3M, Admin: $8.2M)
        EBITDA: $6.6M (14.6% margin)
        
        Key Highlights:
        - New product line exceeded targets by 47%
        - Customer acquisition cost reduced by 18%
        - Churn rate improved to 5.2% (from 7.8%)
        - International expansion on track
        
        Concerns:
        - Supply chain disruptions impacting Q4 forecast
        - Competitor launched similar product at 30% lower price
        - Key engineering talent retention challenges
        """,
        analysis_depth: "deep",
        business_context: "financial",
        worker_id: 3
      }
    ]
    
    # Process documents concurrently using pool workers
    Logger.info("\n⚡ Processing #{length(documents)} documents concurrently...")
    start_time = System.monotonic_time(:millisecond)
    
    tasks = Enum.map(documents, fn doc ->
      Task.async(fn ->
        Logger.info("   🔄 Worker #{doc.worker_id} processing document...")
        
        # Use the same session as program creation
        case DSPex.Python.Pool.execute_in_session(session_id, "execute_program", %{
          program_id: prog_id,
          inputs: Map.delete(doc, :worker_id)
        }) do
          {:ok, result} ->
            {doc, result}
          {:error, reason} ->
            {doc, {:error, reason}}
        end
      end)
    end)
    
    results = Task.await_many(tasks, 30_000)
    elapsed = System.monotonic_time(:millisecond) - start_time
    
    Logger.info("✅ All documents processed in #{elapsed}ms using pool workers")
    
    # Display results
    Enum.each(results, fn {doc, result} ->
      case result do
        {:error, reason} ->
          Logger.warning("❌ Document analysis failed: #{inspect(reason)}")
        
        outputs when is_map(outputs) ->
          Logger.info("\n📊 Document Intelligence Results (Worker #{doc.worker_id}):")
          Logger.info("   Context: #{doc.business_context} | Depth: #{doc.analysis_depth}")
          Logger.info("   📋 Type: #{get_output(outputs, "document_type")}")
          Logger.info("   👥 Entities: #{get_output(outputs, "key_entities")}")
          Logger.info("   ⚠️  Risk: #{get_output(outputs, "risk_assessment")}")
          Logger.info("   🎯 Actions: #{get_output(outputs, "action_items")}")
          Logger.info("   ⏰ Urgency: #{get_output(outputs, "urgency_level")}")
          Logger.info("   📊 Confidence: #{get_output(outputs, "confidence_score")}")
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
    Logger.info("\n🎧 Advanced Customer Support Assistant (Pooled)")
    Logger.info("==============================================")
    
    signature = customer_support_signature()
    
    # Use consistent session for this signature workflow
    session_id = "support_session_#{System.unique_integer([:positive])}"
    {:ok, prog_id_result} = DSPex.Python.Pool.execute_in_session(session_id, "create_program", %{
      id: "support_#{System.unique_integer([:positive])}",
      signature: signature
    })
    prog_id = prog_id_result["program_id"]
    
    # Multiple customer support cases for concurrent processing
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
        product_context: "Enterprise authentication system with 2FA, account lockout after 5 failed attempts, premium SLA: 1-hour response time",
        case_id: "CASE-001"
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
        product_context: "Dashboard v2.3 released last week, known issue with CSV export filters, workaround available via API",
        case_id: "CASE-002"
      },
      
      %{
        customer_message: """
        Your billing is completely wrong AGAIN. I was charged $299 but my plan is only $199. 
        This is the third time this has happened. I want a full refund for the overcharges 
        and I want to know what you're going to do to fix this permanently.
        """,
        customer_tier: "standard",
        interaction_history: "Billing disputes 2 months ago (resolved with credit), 4 months ago (resolved with refund). Customer getting increasingly frustrated.",
        product_context: "Known billing system bug affecting legacy accounts during plan migrations. Fix scheduled for next sprint.",
        case_id: "CASE-003"
      },
      
      %{
        customer_message: """
        We're evaluating your platform for our 500-person company. Can you provide 
        information about bulk licensing, SSO integration, and compliance certifications? 
        We need SOC2 and HIPAA compliance for our healthcare division.
        """,
        customer_tier: "trial",
        interaction_history: "New prospect, signed up for trial 3 days ago. Fortune 500 company in healthcare sector.",
        product_context: "Enterprise features available, SOC2 certified, HIPAA compliance in beta, SSO via SAML/OIDC",
        case_id: "CASE-004"
      },
      
      %{
        customer_message: """
        The mobile app keeps crashing whenever I try to upload photos. I've tried 
        reinstalling but it didn't help. Using iPhone 13, iOS 17.2.
        """,
        customer_tier: "standard",
        interaction_history: "First support contact. Active user for 8 months.",
        product_context: "Known iOS 17.2 compatibility issue with photo uploads. Patch released yesterday, not all users updated yet.",
        case_id: "CASE-005"
      }
    ]
    
    # Process all support cases concurrently
    Logger.info("\n⚡ Processing #{length(support_cases)} support cases concurrently...")
    start_time = System.monotonic_time(:millisecond)
    
    tasks = Enum.map(support_cases, fn case_data ->
      Task.async(fn ->
        Logger.info("   🔄 Processing #{case_data.case_id}...")
        
        inputs = Map.delete(case_data, :case_id)
        
        # Use the same session as program creation
        case DSPex.Python.Pool.execute_in_session(session_id, "execute_program", %{
          program_id: prog_id,
          inputs: inputs
        }) do
          {:ok, result} ->
            {case_data.case_id, result}
          {:error, reason} ->
            {case_data.case_id, {:error, reason}}
        end
      end)
    end)
    
    results = Task.await_many(tasks, 30_000)
    elapsed = System.monotonic_time(:millisecond) - start_time
    
    Logger.info("✅ All support cases processed in #{elapsed}ms")
    
    # Display results
    Enum.each(results, fn {case_id, result} ->
      case result do
        {:error, reason} ->
          Logger.warning("❌ #{case_id} analysis failed: #{inspect(reason)}")
        
        outputs when is_map(outputs) ->
          Logger.info("\n📊 Support Analysis Results for #{case_id}:")
          Logger.info("   😊 Sentiment: #{get_output(outputs, "sentiment_analysis")}")
          Logger.info("   🏷️  Issue Type: #{get_output(outputs, "issue_classification")}")
          Logger.info("   💬 Response: #{String.slice(get_output(outputs, "suggested_response"), 0, 150)}...")
          Logger.info("   ⬆️  Escalation: #{get_output(outputs, "escalation_needed")}")
          Logger.info("   🔧 Steps: #{get_output(outputs, "resolution_steps")}")
          Logger.info("   📅 Follow-up: #{get_output(outputs, "follow_up_timeline")}")
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
    Logger.info("\n💰 Advanced Financial Risk Assessment (Pooled)")
    Logger.info("=============================================")
    
    signature = financial_risk_signature()
    
    # Use consistent session for this signature workflow
    session_id = "finance_session_#{System.unique_integer([:positive])}"
    {:ok, prog_id_result} = DSPex.Python.Pool.execute_in_session(session_id, "create_program", %{
      id: "finance_#{System.unique_integer([:positive])}",
      signature: signature
    })
    prog_id = prog_id_result["program_id"]
    
    # Multiple financial scenarios for parallel analysis
    financial_cases = generate_financial_scenarios()
    
    # Process all financial cases concurrently
    Logger.info("\n⚡ Analyzing #{length(financial_cases)} financial scenarios concurrently...")
    start_time = System.monotonic_time(:millisecond)
    
    tasks = Enum.map(financial_cases, fn case_data ->
      Task.async(fn ->
        Logger.info("   🔄 Analyzing #{case_data.company_name}...")
        
        inputs = Map.delete(case_data, :company_name)
        
        # Use the same session as program creation
        case DSPex.Python.Pool.execute_in_session(session_id, "execute_program", %{
          program_id: prog_id,
          inputs: inputs
        }) do
          {:ok, result} ->
            {case_data.company_name, result}
          {:error, reason} ->
            {case_data.company_name, {:error, reason}}
        end
      end)
    end)
    
    results = Task.await_many(tasks, 30_000)
    elapsed = System.monotonic_time(:millisecond) - start_time
    
    Logger.info("✅ All financial analyses completed in #{elapsed}ms")
    
    # Display results
    Enum.each(results, fn {company_name, result} ->
      case result do
        {:error, reason} ->
          Logger.warning("❌ #{company_name} analysis failed: #{inspect(reason)}")
        
        outputs when is_map(outputs) ->
          Logger.info("\n📊 Financial Risk Assessment for #{company_name}:")
          Logger.info("   🎯 Risk Score: #{get_output(outputs, "risk_score")}")
          Logger.info("   ⚠️  Key Risks: #{get_output(outputs, "key_risks")}")
          Logger.info("   📈 Scenarios: #{String.slice(get_output(outputs, "scenario_analysis"), 0, 150)}...")
          Logger.info("   💡 Recommendation: #{String.slice(get_output(outputs, "investment_recommendation"), 0, 150)}...")
          Logger.info("   🛡️  Hedging: #{get_output(outputs, "hedge_strategies")}")
          Logger.info("   📊 Monitoring: #{get_output(outputs, "monitoring_metrics")}")
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
    Logger.info("\n🛒 Advanced Product Recommendation Engine (Pooled)")
    Logger.info("=================================================")
    
    signature = product_recommendation_signature()
    
    # Use consistent session for this signature workflow
    session_id = "recommend_session_#{System.unique_integer([:positive])}"
    {:ok, prog_id_result} = DSPex.Python.Pool.execute_in_session(session_id, "create_program", %{
      id: "recommendations_#{System.unique_integer([:positive])}",
      signature: signature
    })
    prog_id = prog_id_result["program_id"]
    
    # Generate multiple user sessions for concurrent recommendation
    user_sessions = generate_user_sessions()
    
    # Process all recommendation requests concurrently
    Logger.info("\n⚡ Generating recommendations for #{length(user_sessions)} users concurrently...")
    start_time = System.monotonic_time(:millisecond)
    
    tasks = Enum.map(user_sessions, fn session ->
      Task.async(fn ->
        Logger.info("   🔄 Processing user #{session.user_id}...")
        
        inputs = Map.delete(session, :user_id)
        
        # Use the same session as program creation
        case DSPex.Python.Pool.execute_in_session(session_id, "execute_program", %{
          program_id: prog_id,
          inputs: inputs
        }) do
          {:ok, result} ->
            {session.user_id, result}
          {:error, reason} ->
            {session.user_id, {:error, reason}}
        end
      end)
    end)
    
    results = Task.await_many(tasks, 30_000)
    elapsed = System.monotonic_time(:millisecond) - start_time
    
    Logger.info("✅ All recommendations generated in #{elapsed}ms")
    
    # Display results
    Enum.each(results, fn {user_id, result} ->
      case result do
        {:error, reason} ->
          Logger.warning("❌ #{user_id} recommendation failed: #{inspect(reason)}")
        
        outputs when is_map(outputs) ->
          Logger.info("\n📊 Recommendations for #{user_id}:")
          Logger.info("   🏆 Primary: #{String.slice(get_output(outputs, "primary_recommendations"), 0, 150)}...")
          Logger.info("   🔗 Cross-sell: #{String.slice(get_output(outputs, "cross_sell_opportunities"), 0, 150)}...")
          Logger.info("   🧠 Insights: #{String.slice(get_output(outputs, "personalization_insights"), 0, 150)}...")
          Logger.info("   📊 Conversion: #{get_output(outputs, "conversion_probability")}")
          Logger.info("   ⏰ Timing: #{get_output(outputs, "optimal_timing")}")
          Logger.info("   🧪 A/B Test: #{get_output(outputs, "a_b_test_variant")}")
      end
    end)
  end

  # ====================================================================
  # CONCURRENT SIGNATURE DEMO
  # Demonstrates all 4 signature types running simultaneously
  # ====================================================================

  def run_concurrent_signature_demo do
    Logger.info("\n🚀 Concurrent Multi-Signature Demo")
    Logger.info("==================================")
    Logger.info("Running all 4 signature types simultaneously using 5 pool workers...")
    
    start_time = System.monotonic_time(:millisecond)
    
    # Create sessions and programs for each signature type
    doc_session = "conc_doc_session_#{System.unique_integer([:positive])}"
    {:ok, doc_prog_result} = DSPex.Python.Pool.execute_in_session(doc_session, "create_program", %{
      id: "concurrent_doc_#{System.unique_integer([:positive])}",
      signature: document_intelligence_signature()
    })
    doc_prog_id = doc_prog_result["program_id"]
    
    support_session = "conc_support_session_#{System.unique_integer([:positive])}"
    {:ok, support_prog_result} = DSPex.Python.Pool.execute_in_session(support_session, "create_program", %{
      id: "concurrent_support_#{System.unique_integer([:positive])}",
      signature: customer_support_signature()
    })
    support_prog_id = support_prog_result["program_id"]
    
    finance_session = "conc_finance_session_#{System.unique_integer([:positive])}"
    {:ok, finance_prog_result} = DSPex.Python.Pool.execute_in_session(finance_session, "create_program", %{
      id: "concurrent_finance_#{System.unique_integer([:positive])}",
      signature: financial_risk_signature()
    })
    finance_prog_id = finance_prog_result["program_id"]
    
    recommend_session = "conc_recommend_session_#{System.unique_integer([:positive])}"
    {:ok, recommend_prog_result} = DSPex.Python.Pool.execute_in_session(recommend_session, "create_program", %{
      id: "concurrent_recommend_#{System.unique_integer([:positive])}",
      signature: product_recommendation_signature()
    })
    recommend_prog_id = recommend_prog_result["program_id"]
    
    # Execute all signature types concurrently using their respective sessions
    tasks = [
      Task.async(fn ->
        DSPex.Python.Pool.execute_in_session(doc_session, "execute_program", %{
          program_id: doc_prog_id,
          inputs: %{
            document_text: "URGENT CONTRACT: $50M acquisition deal closing tomorrow. Critical terms need review.",
            analysis_depth: "forensic",
            business_context: "legal"
          }
        })
      end),
      
      Task.async(fn ->
        DSPex.Python.Pool.execute_in_session(support_session, "execute_program", %{
          program_id: support_prog_id,
          inputs: %{
            customer_message: "My enterprise account is down! This is affecting 1000+ users!",
            customer_tier: "premium",
            interaction_history: "VIP customer, $1M annual contract",
            product_context: "Known server issue being investigated"
          }
        })
      end),
      
      Task.async(fn ->
        DSPex.Python.Pool.execute_in_session(finance_session, "execute_program", %{
          program_id: finance_prog_id,
          inputs: %{
            financial_data: "Revenue: $100M, Debt: $20M, Cash: $15M, Growth: 45% YoY",
            market_conditions: "High volatility, recession fears, sector outperforming",
            investment_timeline: "medium_term",
            risk_tolerance: "moderate"
          }
        })
      end),
      
      Task.async(fn ->
        DSPex.Python.Pool.execute_in_session(recommend_session, "execute_program", %{
          program_id: recommend_prog_id,
          inputs: %{
            user_profile: "Premium customer, tech enthusiast, $5K annual spend",
            browsing_session: "Viewing high-end laptops for 30 minutes",
            inventory_context: "New models launching, clearance on current stock",
            recommendation_goal: "upsell"
          }
        })
      end)
    ]
    
    results = Task.await_many(tasks, 30_000)
    elapsed = System.monotonic_time(:millisecond) - start_time
    
    success_count = Enum.count(results, &match?({:ok, _}, &1))
    
    Logger.info("\n✅ Concurrent execution complete!")
    Logger.info("   ⏱️  Total time: #{elapsed}ms")
    Logger.info("   📊 Success rate: #{success_count}/#{length(tasks)} tasks")
    Logger.info("   🚀 All 4 signature types processed simultaneously by pool workers")
  end

  # ====================================================================
  # POOL PERFORMANCE DEMONSTRATION
  # ====================================================================

  def demonstrate_pool_performance do
    Logger.info("\n📊 Pool Performance Demonstration")
    Logger.info("=================================")
    
    # Test pool efficiency with rapid-fire requests
    Logger.info("\n1️⃣ Rapid-fire test: 20 requests across 5 workers")
    
    start_time = System.monotonic_time(:millisecond)
    
    tasks = for i <- 1..20 do
      Task.async(fn ->
        {i, DSPex.Python.Pool.execute_in_session("ping_#{i}", "ping", %{request_id: i})}
      end)
    end
    
    results = Task.await_many(tasks, 10_000)
    elapsed = System.monotonic_time(:millisecond) - start_time
    
    success_count = Enum.count(results, fn {_, result} -> match?({:ok, _}, result) end)
    
    Logger.info("   ✅ Completed: #{success_count}/20 requests")
    Logger.info("   ⏱️  Time: #{elapsed}ms")
    Logger.info("   🚀 Throughput: #{Float.round(20 / (elapsed / 1000), 2)} req/sec")
    
    # Show pool distribution
    Logger.info("\n2️⃣ Worker distribution analysis:")
    
    worker_counts = Enum.reduce(results, %{}, fn {_i, {:ok, response}}, acc ->
      worker_id = response["worker_id"] || "unknown"
      Map.update(acc, worker_id, 1, &(&1 + 1))
    end)
    
    Enum.each(worker_counts, fn {worker_id, count} ->
      Logger.info("   Worker #{worker_id}: handled #{count} requests")
    end)
  end

  # ====================================================================
  # MASTER EXAMPLE RUNNER
  # ====================================================================

  def run_all_pooled_examples do
    Logger.info("🚀 Pooled Advanced DSPy-Integrated Signatures Showcase")
    Logger.info("======================================================")
    Logger.info("Using 5-worker pool for concurrent processing\n")
    
    # Verify pool is running
    pool_pid = Process.whereis(DSPex.Python.Pool)
    
    if pool_pid do
      Logger.info("✅ Pool is running with PID: #{inspect(pool_pid)}")
      
      # Run individual examples
      run_document_intelligence_example()
      Process.sleep(2000)
      
      run_customer_support_example()
      Process.sleep(2000)
      
      run_financial_risk_example()
      Process.sleep(2000)
      
      run_product_recommendation_example()
      Process.sleep(2000)
      
      # Run concurrent demo
      run_concurrent_signature_demo()
      Process.sleep(2000)
      
      # Demonstrate pool performance
      demonstrate_pool_performance()
      
      Logger.info("\n🎉 Pooled Examples Complete!")
      Logger.info("💡 Key advantages demonstrated:")
      Logger.info("   • Concurrent processing of multiple signatures")
      Logger.info("   • Efficient resource utilization with worker pool")
      Logger.info("   • Scalable architecture for high-throughput scenarios")
      Logger.info("   • Reduced latency through parallel execution")
      Logger.info("   • Load balancing across 5 pool workers")
    else
      Logger.error("❌ Pool not found! Make sure pooling is enabled.")
    end
  end

  # ====================================================================
  # HELPER FUNCTIONS
  # ====================================================================

  defp configure_language_model do
    api_key = System.get_env("GEMINI_API_KEY")
    
    if is_nil(api_key) or api_key == "" do
      Logger.warning("⚠️  GEMINI_API_KEY not set, using mock responses")
    end
    
    # Use a temporary session for configuration
    config_session_id = "config_lm_#{System.unique_integer([:positive])}"
    case DSPex.Python.Pool.execute_in_session(config_session_id, "configure_lm", %{
      model: "gemini-1.5-flash",
      api_key: api_key || "mock-key",
      provider: "google"
    }) do
      {:ok, _} -> 
        Logger.info("✅ Language model configured successfully via pool")
      {:error, reason} -> 
        Logger.warning("⚠️  LM configuration issue: #{inspect(reason)}")
    end
  end

  defp get_output(outputs, key) when is_map(outputs) do
    outputs = outputs["outputs"] || outputs[:outputs] || outputs
    outputs[key] || outputs[String.to_atom(key)] || "N/A"
  end
  
  defp get_output(_outputs, _key), do: "N/A"

  defp generate_financial_scenarios do
    [
      %{
        company_name: "TechStartup AI Inc.",
        financial_data: """
        Revenue (TTM): $45M (180% YoY growth)
        Burn Rate: $7M/month, Runway: 3.3 months
        Valuation: $800M, Recent Funding: Series B $80M
        """,
        market_conditions: "High interest rates, VC funding down 60% YoY",
        investment_timeline: "medium_term",
        risk_tolerance: "aggressive"
      },
      %{
        company_name: "StableRetail Corp",
        financial_data: """
        Revenue: $890M (+3% YoY), EBITDA: $134M (15% margin)
        Debt/Equity: 0.4, Current Ratio: 2.1
        15 years profitable, 200 stores nationwide
        """,
        market_conditions: "Consumer spending flat, e-commerce competition rising",
        investment_timeline: "long_term",
        risk_tolerance: "conservative"
      },
      %{
        company_name: "BioTech Innovations",
        financial_data: """
        Pre-revenue, $120M cash, burn $5M/month
        3 drugs in Phase II trials, 2 in Phase III
        Key patent expires 2027
        """,
        market_conditions: "FDA approval rates improving, biotech valuations recovering",
        investment_timeline: "long_term",
        risk_tolerance: "speculative"
      },
      %{
        company_name: "GreenEnergy Solutions",
        financial_data: """
        Revenue: $230M (+65% YoY), Gross Margin: 42%
        Heavy CapEx requirements, government subsidies = 30% revenue
        Backlog: $1.2B over 3 years
        """,
        market_conditions: "Policy support strong, commodity prices volatile",
        investment_timeline: "medium_term",
        risk_tolerance: "moderate"
      },
      %{
        company_name: "DataCenter REIT",
        financial_data: """
        FFO: $450M, Occupancy: 96%, Debt: $2.1B @ 4.5% avg
        10-year average lease term, investment grade tenants
        Dividend yield: 4.8%
        """,
        market_conditions: "AI driving demand, interest rates elevated, power costs rising",
        investment_timeline: "long_term",
        risk_tolerance: "moderate"
      }
    ]
  end

  defp generate_user_sessions do
    [
      %{
        user_id: "premium_8473",
        user_profile: "34F, Software Engineer, $145K income, eco-conscious, fitness enthusiast",
        browsing_session: "Smartwatches → Compare 3 models → Reviews (23 min)",
        inventory_context: "Black Friday sale, high smartwatch inventory",
        recommendation_goal: "conversion"
      },
      %{
        user_id: "business_2847", 
        user_profile: "B2B Office Manager, 150 employees, $2M budget, first-time buyer",
        browsing_session: "Office furniture → Standing desks → Bulk pricing (47 min)",
        inventory_context: "Q4 clearance, volume discounts, high installation capacity",
        recommendation_goal: "upsell"
      },
      %{
        user_id: "fashion_9281",
        user_profile: "28F, Fashion blogger, 50K followers, trendsetter, $800/mo spend",
        browsing_session: "New arrivals → Designer bags → Shoes → Accessories (35 min)",
        inventory_context: "Spring collection launch, influencer partnerships available",
        recommendation_goal: "discovery"
      },
      %{
        user_id: "gamer_5647",
        user_profile: "22M, College student, gaming enthusiast, budget-conscious",
        browsing_session: "Gaming laptops → Under $1000 filter → Specs comparison (28 min)",
        inventory_context: "Student discounts active, refurbished units available",
        recommendation_goal: "conversion"
      },
      %{
        user_id: "home_3924",
        user_profile: "45M, New homeowner, DIY enthusiast, project-based shopper",
        browsing_session: "Power tools → How-to guides → Project bundles (19 min)",
        inventory_context: "Tool rental program, bundle deals, seasonal projects",
        recommendation_goal: "cross_sell"
      }
    ]
  end
end

# ====================================================================
# MAIN EXECUTION
# ====================================================================

IO.puts("🎯 Pooled Advanced DSPy-Integrated Signatures Example")
IO.puts("===================================================")
IO.puts("This example demonstrates sophisticated business scenarios")
IO.puts("processed concurrently using a 5-worker pool:\n")

IO.puts("📄 Document Intelligence - Complex multi-step analysis")
IO.puts("🎧 Customer Support - Context-aware response generation")  
IO.puts("💰 Financial Risk Assessment - Data-driven decision making")
IO.puts("🛒 Product Recommendations - Personalized ML suggestions")
IO.puts("⚡ Concurrent Processing - All signatures running simultaneously")
IO.puts("")

IO.puts("🔧 Pool Configuration:")
IO.puts("   • Pool size: 5 workers")
IO.puts("   • Pool type: V3 (optimized)")
IO.puts("   • Concurrency: Full parallel processing")
IO.puts("   • Load balancing: Automatic worker distribution")
IO.puts("")

IO.puts("🚀 Starting pooled examples...")
IO.puts("================================")

PooledAdvancedSignatureExample.run_all_pooled_examples()

# Ensure proper cleanup by explicitly stopping the application
IO.puts("\n🛑 Stopping DSPex application to ensure cleanup...")
Application.stop(:dspex)
IO.puts("\n🎉 All examples complete - application stopped cleanly!")
IO.puts("💡 Pool and workers cleaned up automatically!")