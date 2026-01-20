# Flagship Multi-Pool + GEPA Demo
#
# Run with: mix run --no-start examples/flagship_multi_pool_gepa.exs
#
# Requires: GEMINI_API_KEY environment variable

alias Dspy.{Example, GEPA}
alias SnakeBridge.ConfigHelper
alias SnakeBridge.Runtime
alias Snakepit.Bridge.SessionStore

defmodule DSPex.FlagshipMultiPoolGepa do
  @moduledoc false

  @model "gemini/gemini-flash-lite-latest"
  @triage_signature "ticket -> category, urgency, action"
  @insights_signature "ticket -> summary, root_cause"
  @insights_temperature 0.6

  @pools [
    %{name: :triage_pool, pool_size: 2, affinity: :strict_queue},
    %{name: :optimizer_pool, pool_size: 2, affinity: :strict_queue},
    %{name: :analytics_pool, pool_size: 2, affinity: :hint}
  ]

  def run do
    configure_snakepit!()

    DSPex.run(
      fn ->
        banner()
        print_pools()

        tickets = tickets()
        holdout = holdout_ticket()

        IO.puts("\n==> Step 1: Build DSPy modules across pools")
        triage_sessions = build_triage_sessions()
        insights_session = build_insights_session()
        optimizer_session = build_optimizer_session()
        analytics_session = build_analytics_session()

        print_session_workers("Triage sessions", triage_sessions)
        print_session_workers("Insights session", [insights_session])
        print_session_workers("Optimizer session", [optimizer_session])
        print_session_workers("Analytics session", [analytics_session])

        IO.puts("\n==> Step 2: Run triage predictions in parallel")
        triage_results = run_triage_predictions(triage_sessions, tickets)

        IO.puts("\n==> Step 3: Generate insights in a separate DSPy pool")
        insights = run_insights(insights_session, triage_results)

        IO.puts("\n==> Step 4: Evaluate with numpy in the analytics pool")
        analytics = run_numpy_eval(analytics_session, triage_results)

        IO.puts("\n==> Step 5: GEPA optimization (max_metric_calls=3)")
        optimized = run_gepa_optimizer(optimizer_session, tickets)

        IO.puts("\n==> Step 6: Baseline vs optimized on a holdout ticket")
        compare_baseline_vs_optimized(triage_sessions, optimizer_session, optimized, holdout)

        IO.puts("\n==> LM History via Graceful Serialization (triage pool)")
        IO.puts("    (ModelResponse objects become refs, other fields preserved)")

        Enum.each(triage_sessions, fn session ->
          print_prompt_history("Triage #{session.label}", session)
        end)

        IO.puts("\n==> LM History via Graceful Serialization (optimizer pool)")
        print_prompt_history("GEPA", optimizer_session)

        summary(triage_results, insights, analytics)
      end,
      restart: true
    )
  end

  defp configure_snakepit! do
    ConfigHelper.snakepit_config(pools: @pools)
    |> Enum.each(fn {key, value} ->
      Application.put_env(:snakepit, key, value)
    end)
  end

  defp banner do
    IO.puts("DSPex Flagship Demo: Multi-Pool GEPA + Analytics")
    IO.puts(String.duplicate("=", 64))
    IO.puts("This demo uses strict affinity for stateful DSPy sessions,")
    IO.puts("and a hint pool for stateless numpy analytics.")
  end

  defp print_pools do
    IO.puts("\nPools:")

    Enum.each(@pools, fn pool ->
      IO.puts("  #{pool.name} (size=#{pool.pool_size}, affinity=#{pool.affinity})")
    end)
  end

  defp tickets do
    [
      %{
        id: "INC-001",
        text: "Checkout fails with a 500 error for EU users after last deploy.",
        category: "outage",
        urgency: "high"
      },
      %{
        id: "INC-002",
        text: "Refund still not received after 10 business days.",
        category: "billing",
        urgency: "medium"
      },
      %{
        id: "INC-003",
        text: "Requesting a bulk export feature for analytics dashboards.",
        category: "feature",
        urgency: "low"
      },
      %{
        id: "INC-004",
        text: "Admin login locked after SSO update; multiple users blocked.",
        category: "account",
        urgency: "high"
      },
      %{
        id: "INC-005",
        text: "CSV export shows incorrect timezone offsets in reports.",
        category: "bug",
        urgency: "medium"
      }
    ]
  end

  defp holdout_ticket do
    %{
      id: "HOLDOUT-01",
      text: "Customer cannot update billing address in the portal.",
      category: "billing",
      urgency: "medium"
    }
  end

  defp build_triage_sessions do
    Enum.map(1..2, fn idx ->
      setup_predictor(:triage_pool, "triage_#{idx}", @triage_signature, 0.2)
    end)
  end

  defp build_insights_session do
    setup_chain_of_thought(
      :optimizer_pool,
      "insights",
      @insights_signature,
      @insights_temperature
    )
  end

  defp build_optimizer_session do
    setup_predictor(:optimizer_pool, "gepa", @triage_signature, 0.2)
  end

  defp build_analytics_session do
    session_id = unique_session("analytics")
    ensure_session(session_id)

    %{
      label: "analytics",
      pool: :analytics_pool,
      session_id: session_id
    }
  end

  defp setup_predictor(pool, label, signature, temperature) do
    session_id = unique_session(label)
    ensure_session(session_id)
    lm = DSPex.lm!(@model, with_runtime([temperature: temperature], pool, session_id))
    :ok = DSPex.configure!(with_runtime([lm: lm], pool, session_id))
    predictor = DSPex.predict!(signature, with_runtime([], pool, session_id))

    %{
      label: label,
      pool: pool,
      session_id: session_id,
      predictor: predictor,
      # Store LM reference for history access
      lm: lm
    }
  end

  defp setup_chain_of_thought(pool, label, signature, temperature) do
    session_id = unique_session(label)
    ensure_session(session_id)
    lm = DSPex.lm!(@model, with_runtime([temperature: temperature], pool, session_id))
    :ok = DSPex.configure!(with_runtime([lm: lm], pool, session_id))
    module = DSPex.chain_of_thought!(signature, with_runtime([], pool, session_id))

    %{
      label: label,
      pool: pool,
      session_id: session_id,
      module: module,
      # Store LM reference for history access
      lm: lm
    }
  end

  defp run_triage_predictions(sessions, tickets) do
    assignments =
      tickets
      |> Enum.with_index()
      |> Enum.map(fn {ticket, idx} ->
        session = Enum.at(sessions, rem(idx, length(sessions)))
        {session, ticket}
      end)

    assignments
    |> Task.async_stream(
      fn {session, ticket} ->
        triage_ticket(session, ticket)
      end,
      max_concurrency: length(sessions),
      timeout: 300_000
    )
    |> Enum.map(fn {:ok, result} -> result end)
    |> tap(fn results ->
      Enum.each(results, fn item ->
        IO.puts("  #{item.id} -> #{item.category}/#{item.urgency} (#{item.session})")
      end)
    end)
  end

  defp triage_ticket(session, ticket) do
    opts = with_runtime([ticket: ticket.text], session.pool, session.session_id)
    result = DSPex.method!(session.predictor, "forward", [], opts)

    %{
      id: ticket.id,
      text: ticket.text,
      gold_category: ticket.category,
      gold_urgency: ticket.urgency,
      category: to_string(DSPex.attr!(result, "category")),
      urgency: to_string(DSPex.attr!(result, "urgency")),
      action: to_string(DSPex.attr!(result, "action")),
      session: session.label
    }
  end

  defp run_insights(session, triage_results) do
    urgent =
      triage_results
      |> Enum.filter(fn item -> normalize(item.urgency) == "high" end)
      |> case do
        [] -> Enum.take(triage_results, 2)
        items -> items
      end

    {insights, _session} =
      Enum.map_reduce(urgent, session, fn item, session_acc ->
        call_insights_with_retry(session_acc, item)
      end)

    Enum.each(insights, fn item ->
      IO.puts("  #{item.id} summary: #{item.summary}")
      IO.puts("  #{item.id} root_cause: #{item.root_cause}")
    end)

    insights
  end

  defp call_insights_with_retry(session, item) do
    case call_insights(session, item) do
      {:ok, result} ->
        {format_insight(item, result, session), session}

      {:error, :session_worker_unavailable} ->
        retry_insights_after_rehydration(session, item)

      {:error, reason} ->
        raise "SnakeBridge error: #{inspect(reason)}"
    end
  end

  defp retry_insights_after_rehydration(session, item) do
    new_session = rehydrate_insights_session(session)

    case call_insights(new_session, item) do
      {:ok, result} ->
        {format_insight(item, result, new_session), new_session}

      {:error, reason} ->
        raise "SnakeBridge error: #{inspect(reason)}"
    end
  end

  defp call_insights(session, item) do
    opts = with_runtime([ticket: item.text], session.pool, session.session_id)
    DSPex.method(session.module, "forward", [], opts)
  end

  defp format_insight(item, result, session) do
    runtime_opts = runtime(session.pool, session.session_id)

    %{
      id: item.id,
      summary: to_string(DSPex.attr!(result, "summary", __runtime__: runtime_opts)),
      root_cause: to_string(DSPex.attr!(result, "root_cause", __runtime__: runtime_opts))
    }
  end

  defp rehydrate_insights_session(session) do
    IO.puts("  WARNING: Insights session worker unavailable; rehydrating session state.")

    new_session =
      setup_chain_of_thought(
        session.pool,
        session.label,
        @insights_signature,
        @insights_temperature
      )

    print_session_workers("Rehydrated insights session", [new_session])
    new_session
  end

  defp run_numpy_eval(session, triage_results) do
    scores =
      Enum.map(triage_results, fn item ->
        score_prediction(item)
      end)

    runtime = runtime(session.pool, session.session_id)
    {:ok, numpy_version} = Runtime.get_module_attr("numpy", "__version__", __runtime__: runtime)
    mean = DSPex.call!("numpy", "mean", [scores], __runtime__: runtime)
    std = DSPex.call!("numpy", "std", [scores], __runtime__: runtime)
    p80 = DSPex.call!("numpy", "percentile", [scores, 80], __runtime__: runtime)

    IO.puts("  numpy version: #{numpy_version}")
    IO.puts("  mean score: #{Float.round(mean, 3)}")
    IO.puts("  std dev: #{Float.round(std, 3)}")
    IO.puts("  80th percentile: #{Float.round(p80, 3)}")

    %{mean: mean, std: std, p80: p80}
  end

  defp run_gepa_optimizer(session, tickets) do
    train_tickets = Enum.take(tickets, 3)

    metric = build_gepa_metric(session)

    reflection_lm =
      DSPex.lm!(@model, with_runtime([temperature: 0.9], session.pool, session.session_id))

    {:ok, gepa} =
      GEPA.new(
        metric,
        with_runtime(
          [
            reflection_lm: reflection_lm,
            max_metric_calls: 3,
            reflection_minibatch_size: 1,
            track_stats: true
          ],
          session.pool,
          session.session_id
        )
      )

    trainset = build_examples(session, train_tickets)

    {:ok, optimized} =
      GEPA.compile(
        gepa,
        session.predictor,
        with_runtime([trainset: trainset, valset: trainset], session.pool, session.session_id)
      )

    optimized
  end

  defp build_examples(session, tickets) do
    Enum.map(tickets, fn ticket ->
      {:ok, example} =
        Example.new(
          [],
          with_runtime(
            [
              ticket: ticket.text,
              category: ticket.category,
              urgency: ticket.urgency
            ],
            session.pool,
            session.session_id
          )
        )

      {:ok, example} =
        Example.with_inputs(example, ["ticket"],
          __runtime__: runtime(session.pool, session.session_id)
        )

      example
    end)
  end

  defp build_gepa_metric(session) do
    runtime = runtime(session.pool, session.session_id)
    dspy_module = DSPex.call!("importlib", "import_module", ["dspy"], __runtime__: runtime)
    numpy_module = DSPex.call!("importlib", "import_module", ["numpy"], __runtime__: runtime)

    code = ~S"""
    def metric(gold, pred, trace=None, pred_name=None, pred_trace=None):
        gold_cat = str(getattr(gold, "category", "")).strip().lower()
        pred_cat = str(getattr(pred, "category", "")).strip().lower()
        gold_urg = str(getattr(gold, "urgency", "")).strip().lower()
        pred_urg = str(getattr(pred, "urgency", "")).strip().lower()

        cat_score = 1.0 if gold_cat == pred_cat else 0.0
        urg_score = 1.0 if gold_urg == pred_urg else 0.0
        score = float(np.mean([cat_score, urg_score]))

        feedback_parts = []
        if cat_score == 0.0:
            feedback_parts.append(f"Category mismatch: expected '{gold_cat}' got '{pred_cat}'.")
        if urg_score == 0.0:
            feedback_parts.append(f"Urgency mismatch: expected '{gold_urg}' got '{pred_urg}'.")

        feedback = " ".join(feedback_parts) if feedback_parts else "Perfect match. Keep the intent and be concise."
        return dspy.Prediction(score=score, feedback=feedback)
    """

    globals = %{
      "_code" => code,
      "dspy" => dspy_module,
      "np" => numpy_module
    }

    expr = "(lambda _ns: (exec(_code, _ns, _ns), _ns['metric'])[1])({})"

    DSPex.call!("builtins", "eval", [expr, globals], __runtime__: runtime)
  end

  defp compare_baseline_vs_optimized(triage_sessions, optimizer_session, optimized, holdout) do
    baseline_session = List.first(triage_sessions)
    baseline = triage_ticket(baseline_session, holdout)

    optimized_result =
      DSPex.method!(
        optimized,
        "forward",
        [],
        with_runtime([ticket: holdout.text], optimizer_session.pool, optimizer_session.session_id)
      )

    runtime_opts = runtime(optimizer_session.pool, optimizer_session.session_id)

    optimized_category =
      to_string(DSPex.attr!(optimized_result, "category", __runtime__: runtime_opts))

    optimized_urgency =
      to_string(DSPex.attr!(optimized_result, "urgency", __runtime__: runtime_opts))

    IO.puts("  Baseline -> #{baseline.category}/#{baseline.urgency}")
    IO.puts("  Optimized -> #{optimized_category}/#{optimized_urgency}")
  end

  defp print_prompt_history(label, session) do
    runtime_opts = runtime(session.pool, session.session_id)
    IO.puts("  #{label}:")

    case fetch_prompt_history(runtime_opts, 6) do
      {:ok, []} ->
        IO.puts("    (no history)")

      {:ok, history} ->
        Enum.with_index(history, 1)
        |> Enum.each(fn {entry, idx} ->
          print_history_entry(idx, entry)
        end)

      {:error, reason} ->
        IO.puts("    (history fetch failed: #{reason})")
    end
  end

  defp fetch_prompt_history(runtime_opts, limit) do
    history = DSPex.call!("dspy", "inspect_history", [limit], __runtime__: runtime_opts)

    if is_list(history) do
      {:ok, history}
    else
      {:ok, []}
    end
  rescue
    e ->
      {:error, Exception.message(e)}
  end

  defp print_history_entry(idx, entry) when is_map(entry) do
    model = entry["model"] || "unknown"
    cost = format_cost(entry["cost"])
    usage = format_usage(entry["usage"])

    IO.puts("    [#{idx}] model=#{model}, cost=#{cost}, #{usage}")

    # Show prompt preview (truncated)
    if prompt = entry["prompt"] do
      preview = prompt |> String.slice(0..60) |> String.replace(~r/\s+/, " ")
      IO.puts("        prompt: #{preview}...")
    end

    # Demonstrate graceful serialization: response is a ref (not a marker)
    if response = entry["response"] do
      if SnakeBridge.ref?(response) do
        IO.puts("        response: <#{response.type_name}> (ref - callable)")
      else
        IO.puts("        response: (serialized)")
      end
    end
  end

  defp print_history_entry(idx, _entry) do
    IO.puts("    [#{idx}] (invalid entry)")
  end

  defp format_cost(nil), do: "$0.00"

  defp format_cost(cost) when is_number(cost),
    do: "$#{:erlang.float_to_binary(cost * 1.0, decimals: 4)}"

  defp format_cost(_), do: "$?.??"

  defp format_usage(nil), do: "tokens=?"
  defp format_usage(%{"total_tokens" => total}), do: "tokens=#{total}"
  defp format_usage(%{"prompt_tokens" => p, "completion_tokens" => c}), do: "tokens=#{p}+#{c}"
  defp format_usage(_), do: "tokens=?"

  defp print_session_workers(title, sessions) do
    IO.puts("\n#{title} worker routing:")

    Enum.each(sessions, fn session ->
      case SessionStore.get_session(session.session_id) do
        {:ok, %{last_worker_id: worker_id}} when is_binary(worker_id) ->
          IO.puts("  #{session.label} -> #{worker_id}")

        _ ->
          IO.puts("  #{session.label} -> (not assigned)")
      end
    end)
  end

  defp summary(triage_results, insights, analytics) do
    IO.puts("\n==> Summary")
    IO.puts("  Triage results: #{length(triage_results)}")
    IO.puts("  Insights generated: #{length(insights)}")
    IO.puts("  Mean score: #{Float.round(analytics.mean, 3)}")
    IO.puts("  Std dev: #{Float.round(analytics.std, 3)}")
  end

  defp score_prediction(item) do
    category_match = normalize(item.category) == normalize(item.gold_category)
    urgency_match = normalize(item.urgency) == normalize(item.gold_urgency)

    if(category_match, do: 0.5, else: 0.0) + if urgency_match, do: 0.5, else: 0.0
  end

  defp normalize(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp unique_session(label) do
    "#{label}_#{System.unique_integer([:positive])}"
  end

  defp ensure_session(session_id) do
    case SessionStore.create_session(session_id) do
      {:ok, _session} -> :ok
      {:error, :already_exists} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp runtime(pool, session_id, extra \\ []) do
    Keyword.merge([pool_name: pool, session_id: session_id], extra)
  end

  defp with_runtime(opts, pool, session_id, extra_runtime \\ []) do
    Keyword.put(opts, :__runtime__, runtime(pool, session_id, extra_runtime))
  end
end

DSPex.FlagshipMultiPoolGepa.run()
