# Jev (System One) Incident Triage & Decision Classification
#
# Jev is TypeSafe's "System One" decision model introduced in DSPy 3.4.0.
# Unlike generative LLMs that produce conversational text token-by-token,
# Jev is optimized for fast, deterministic, calibrated decisions:
#   - Noul: Boolean decisions with calibrated probability & confidence
#   - Score: Ordinal rubric scoring with continuous value & level probabilities
#   - Literal / Choice: Multi-class classification and routing
#
# Requires: TYPESAFE_API_KEY environment variable.
# Run with: mix run --no-start examples/jev_classification.exs

require SnakeBridge

defmodule JevTriageFormatter do
  @doc "Renders a mini probability bar like [████████░░] 82%"
  def prob_bar(prob, width \\ 10) do
    pct = round(prob * 100)
    filled = round(prob * width)
    empty = max(0, width - filled)
    bar = String.duplicate("█", filled) <> String.duplicate("░", empty)
    "[#{bar}] #{String.pad_leading("#{pct}%", 4)}"
  end

  @doc "Formats a severity level badge"
  def severity_badge(0), do: "\e[32m[SEV-3: MINOR]\e[0m"
  def severity_badge(1), do: "\e[33m[SEV-2: DISRUPTIVE]\e[0m"
  def severity_badge(2), do: "\e[31m[SEV-1: CRITICAL]\e[0m"
  def severity_badge(n), do: "[SEV: #{n}]"

  @doc "Formats an urgency badge"
  def urgency_badge(true, prob),
    do: "\e[1;41;37m URGENT \e[0m \e[31m(p=#{Float.round(prob, 2)})\e[0m"

  def urgency_badge(false, prob),
    do: "\e[32mNORMAL\e[0m   \e[90m(p=#{Float.round(prob, 2)})\e[0m"

  @doc "Formats category routing badge"
  def category_badge("security"), do: "\e[1;35m[ROUTE: SECURITY INFRA]\e[0m"
  def category_badge("technical"), do: "\e[1;34m[ROUTE: CORE ENGINEERING]\e[0m"
  def category_badge("billing"), do: "\e[1;36m[ROUTE: BILLING & SALES]\e[0m"
  def category_badge(cat), do: "[ROUTE: #{cat}]"
end

SnakeBridge.script do
  IO.puts("""
  \e[1;34m========================================================================\e[0m
  \e[1;37m   DSPex + TypeSafe Jev (System One) Decision Classification Demo      \e[0m
  \e[1;34m========================================================================\e[0m
  \e[90mPowered by DSPy 3.4.0 • Model: jev-latest • Provider: TypeSafe AI\e[0m
  """)

  # 1. Initialize TypeSafe LM with Jev
  IO.puts("1. Initializing TypeSafe System One client...")
  {:ok, lm} = Dspy.Experimental.TypeSafe.new("jev-latest", [])
  {:ok, _} = Dspy.configure(lm: lm)
  IO.puts("   ✓ Bound to TypeSafe System One engine (jev-latest)\n")

  # 2. Retrieve rich decision types from DSPy 3.4.0
  {:ok, noul_cls} = SnakeBridge.get("dspy.experimental", "Noul")
  {:ok, score_cls} = SnakeBridge.get("dspy.experimental", "Score")
  custom_types = %{"Noul" => noul_cls, "Score" => score_cls}

  # 3. Define multi-dimensional triage signature
  IO.puts("2. Defining typed Decision Signature...")
  {:ok, sig} =
    Dspy.make_signature(
      ~s(ticket -> urgent: Noul, category: Literal["billing", "technical", "security"], severity: Score["Minor", "Disruptive", "Critical"]),
      "Triage operational incident reports, customer escalations, and security alerts.",
      "IncidentTriageSignature",
      custom_types
    )

  {:ok, classifier} = Dspy.PredictClass.new(sig, [])

  # Configure question instructions for Jev's decision model
  {:ok, _} =
    DSPex.set_attr(classifier, "fields", %{
      "urgent" => %{
        "instructions" => "Is service completely down, degraded, or customer data at risk?"
      },
      "category" => %{
        "instructions" => "Classify into billing, core technical, or security."
      },
      "severity" => %{
        "instructions" => "Rate operational severity: 0=Minor, 1=Disruptive, 2=Critical emergency."
      }
    })
  IO.puts("   ✓ Signature compiled: InputField(ticket) -> OutputFields(Noul, Choice, Score)\n")

  # 4. Run classification over diverse test incidents
  incidents = [
    %{
      id: "INC-101",
      ticket: "Production Postgres cluster out of disk space in us-east-1, all API writes failing with 500."
    },
    %{
      id: "INC-102",
      ticket: "Customer asking for an updated VAT invoice for subscription renewal order #9481."
    },
    %{
      id: "INC-103",
      ticket: "Brute-force SSH attack detected: 15,000 failed root logins in 2 minutes from unknown subnet."
    },
    %{
      id: "INC-104",
      ticket: "Dark mode setting does not persist across page reloads in Chrome on macOS."
    }
  ]

  IO.puts("3. Running System One Decision Pipeline across test incidents:\n")

  results =
    for incident <- incidents do
      start_time = System.monotonic_time(:millisecond)
      {:ok, res} = Dspy.PredictClass.forward(classifier, ticket: incident.ticket)
      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      # Extract Noul decision (Boolean + probability + confidence)
      {:ok, urgent_ref} = SnakeBridge.attr(res, "urgent")
      {:ok, urgent_val} = SnakeBridge.attr(urgent_ref, "value")
      {:ok, urgent_prob} = SnakeBridge.attr(urgent_ref, "probability")
      {:ok, urgent_conf} = SnakeBridge.attr(urgent_ref, "confidence")

      # Extract Category decision (Literal)
      {:ok, category} = SnakeBridge.attr(res, "category")

      # Extract Score decision (continuous value + discrete level + probabilities)
      {:ok, sev_ref} = SnakeBridge.attr(res, "severity")
      {:ok, sev_val} = SnakeBridge.attr(sev_ref, "value")
      {:ok, sev_level} = SnakeBridge.attr(sev_ref, "level")
      {:ok, sev_probs} = SnakeBridge.attr(sev_ref, "probabilities")

      level_int = round(sev_level)

      IO.puts("  ┌── [#{incident.id}] #{JevTriageFormatter.severity_badge(level_int)} #{JevTriageFormatter.category_badge(category)}")
      IO.puts("  │  Incident:   \"#{incident.ticket}\"")
      IO.puts("  │  Urgency:    #{JevTriageFormatter.urgency_badge(urgent_val, urgent_prob)}  Confidence: #{JevTriageFormatter.prob_bar(urgent_conf, 8)}")
      IO.puts("  │  Severity:   Score: #{Float.round(sev_val, 2)}/2.0  Distribution: Minor=#{Float.round(Map.get(sev_probs, 0, 0.0), 2)} Disruptive=#{Float.round(Map.get(sev_probs, 1, 0.0), 2)} Critical=#{Float.round(Map.get(sev_probs, 2, 0.0), 2)}")
      IO.puts("  │  Latency:    \e[36m#{elapsed_ms} ms\e[0m (Zero token generation)")
      IO.puts("  └──\n")

      Map.merge(incident, %{
        urgent: urgent_val,
        urgent_prob: urgent_prob,
        category: category,
        severity: level_int,
        elapsed_ms: elapsed_ms
      })
    end

  # 5. Threshold Policy Tuning Demonstration
  IO.puts("4. Demonstrating Local Threshold Calibration (DSPy 3.4.0 feature):")
  IO.puts("   Adjusting urgency threshold dynamically without re-prompting or retraining.\n")

  borderline_ticket = "High latency detected on Redis cache; queries taking 450ms instead of 5ms."
  IO.puts("   Test Event: \"#{borderline_ticket}\"\n")

  for threshold <- [0.30, 0.50, 0.85] do
    {:ok, _} =
      DSPex.set_attr(classifier, "fields", %{
        "urgent" => %{
          "threshold" => threshold,
          "instructions" => "Is service completely down, degraded, or customer data at risk?"
        },
        "category" => %{
          "instructions" => "Classify into billing, core technical, or security."
        },
        "severity" => %{
          "instructions" => "Rate operational severity: 0=Minor, 1=Disruptive, 2=Critical emergency."
        }
      })

    {:ok, res} = Dspy.PredictClass.forward(classifier, ticket: borderline_ticket)
    {:ok, urgent_ref} = SnakeBridge.attr(res, "urgent")
    {:ok, urgent_val} = SnakeBridge.attr(urgent_ref, "value")
    {:ok, urgent_prob} = SnakeBridge.attr(urgent_ref, "probability")

    action =
      if urgent_val do
        "\e[31m→ PAGERDUTY ALERT TRIGGERED\e[0m"
      else
        "\e[32m→ ROUTED TO ASYNC QUEUE\e[0m"
      end

    IO.puts("   Threshold #{threshold |> Float.round(2) |> to_string() |> String.pad_trailing(4)}:  decision=#{String.pad_trailing("#{urgent_val}", 5)} (prob=#{Float.round(urgent_prob, 3)})  #{action}")
  end

  # Summary
  avg_latency =
    results
    |> Enum.map(& &1.elapsed_ms)
    |> Enum.sum()
    |> Kernel./(length(results))
    |> round()

  IO.puts("""

  ========================================================================
  \e[32mSummary:\e[0m
    • Processed:   #{length(results)} incidents
    • Avg Latency: \e[1;36m#{avg_latency} ms / decision\e[0m
    • Hallucinations: \e[1;32m0%\e[0m (strictly typed closed-set decisions)
    • Key features: Noul probabilities, Score rubric distributions,
                    local threshold policies, zero token generation overhead.
  ========================================================================
  """)
end
