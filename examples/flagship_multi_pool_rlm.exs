# Flagship Multi-Pool + RLM Demo
#
# Run with: mix run --no-start examples/flagship_multi_pool_rlm.exs
#
# Requires: GEMINI_API_KEY environment variable
# Requires: Deno for PythonInterpreter (install via asdf or https://deno.land/install)

alias Dspy.Predict.RLMClass
alias SnakeBridge.ConfigHelper
alias SnakeBridge.Runtime
alias Snakepit.Bridge.SessionStore

defmodule DSPex.FlagshipMultiPoolRlm do
  @moduledoc false

  @model "gemini/gemini-flash-lite-latest"
  @triage_signature "ticket -> category, urgency, action"
  @rlm_signature "context, query -> output"
  @rlm_max_iterations 4
  @rlm_max_llm_calls 12
  @rlm_max_output_chars 4_000
  @rlm_verbose false
  @rlm_tools []
  @rlm_sub_lm nil
  @rlm_interpreter nil

  @pools [
    %{name: :triage_pool, pool_size: 2, affinity: :strict_queue},
    %{name: :rlm_pool, pool_size: 2, affinity: :strict_queue},
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
        rlm_session = build_rlm_session()
        analytics_session = build_analytics_session()

        print_session_workers("Triage sessions", triage_sessions)
        print_session_workers("RLM session", [rlm_session])
        print_session_workers("Analytics session", [analytics_session])

        IO.puts("\n==> Step 2: Run triage predictions in parallel")
        triage_results = run_triage_predictions(triage_sessions, tickets)

        IO.puts("\n==> Step 3: RLM analysis over long context")
        rlm_result = run_rlm_analysis(rlm_session, triage_results)

        IO.puts("\n==> Step 4: Evaluate with numpy in the analytics pool")
        analytics = run_numpy_eval(analytics_session, triage_results)

        IO.puts("\n==> Step 5: Baseline vs holdout triage")
        baseline = triage_ticket(List.first(triage_sessions), holdout)
        IO.puts("  Holdout -> #{baseline.category}/#{baseline.urgency}")

        IO.puts("\n==> LM History via Graceful Serialization (triage pool)")

        Enum.each(triage_sessions, fn session ->
          print_prompt_history("Triage #{session.label}", session)
        end)

        IO.puts("\n==> LM History via Graceful Serialization (RLM pool)")
        print_prompt_history("RLM", rlm_session)

        summary(triage_results, rlm_result, analytics)
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
    IO.puts("DSPex Flagship Demo: Multi-Pool RLM + Analytics")
    IO.puts(String.duplicate("=", 64))
    IO.puts("This demo uses strict affinity for DSPy sessions,")
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
        id: "INC-101",
        text: "Checkout fails with a 500 error for EU users after last deploy.",
        category: "outage",
        urgency: "high"
      },
      %{
        id: "INC-102",
        text: "Refund still not received after 10 business days.",
        category: "billing",
        urgency: "medium"
      },
      %{
        id: "INC-103",
        text: "Requesting a bulk export feature for analytics dashboards.",
        category: "feature",
        urgency: "low"
      },
      %{
        id: "INC-104",
        text: "Admin login locked after SSO update; multiple users blocked.",
        category: "account",
        urgency: "high"
      },
      %{
        id: "INC-105",
        text: "CSV export shows incorrect timezone offsets in reports.",
        category: "bug",
        urgency: "medium"
      }
    ]
  end

  defp holdout_ticket do
    %{
      id: "HOLDOUT-02",
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

  defp build_rlm_session do
    session_id = unique_session("rlm")
    ensure_session(session_id)

    lm = DSPex.lm!(@model, with_runtime([temperature: 0.3], :rlm_pool, session_id))
    :ok = DSPex.configure!(with_runtime([lm: lm], :rlm_pool, session_id))

    {:ok, rlm} =
      RLMClass.new(
        @rlm_signature,
        @rlm_max_iterations,
        @rlm_max_llm_calls,
        @rlm_max_output_chars,
        @rlm_verbose,
        @rlm_tools,
        @rlm_sub_lm,
        @rlm_interpreter,
        with_runtime([], :rlm_pool, session_id)
      )

    %{
      label: "rlm",
      pool: :rlm_pool,
      session_id: session_id,
      rlm: rlm,
      lm: lm
    }
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

  defp run_rlm_analysis(session, triage_results) do
    if deno_available?() do
      context = build_rlm_context(triage_results)
      query = "Identify the top two recurring issues and recommend next actions."

      case call_rlm_with_retry(session, context, query) do
        {:ok, answer} ->
          IO.puts("  RLM answer: #{answer}")
          %{query: query, answer: answer}

        {:error, reason} ->
          raise "RLM error: #{inspect(reason)}"
      end
    else
      print_deno_missing()
      %{query: nil, answer: nil}
    end
  end

  defp call_rlm_with_retry(session, context, query) do
    case call_rlm(session, context, query) do
      {:ok, answer} ->
        {:ok, answer}

      {:error, :session_worker_unavailable} ->
        new_session = rehydrate_rlm_session(session)
        call_rlm(new_session, context, query)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call_rlm(session, context, query) do
    opts = with_runtime([context: context, query: query], session.pool, session.session_id)

    case DSPex.method(session.rlm, "forward", [], opts) do
      {:ok, result} ->
        runtime_opts = runtime(session.pool, session.session_id)
        answer = DSPex.attr!(result, "output", __runtime__: runtime_opts)
        {:ok, to_string(answer)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp rehydrate_rlm_session(session) do
    IO.puts("  WARNING: RLM session worker unavailable; rehydrating session state.")
    new_session = build_rlm_session()
    print_session_workers("Rehydrated RLM session", [new_session])
    Map.put(new_session, :label, session.label)
  end

  defp build_rlm_context(triage_results) do
    incidents =
      Enum.map_join(triage_results, "\n\n", fn item ->
        """
        Ticket #{item.id}:
          - Report: #{item.text}
          - Category: #{item.category}
          - Urgency: #{item.urgency}
          - Action: #{item.action}
        """
      end)

    timeline = """
    Timeline notes:
      09:05 - EU checkout errors spike.
      09:30 - Support queue flooded with billing delays.
      10:00 - SSO rollout triggers admin lockouts.
      10:20 - Data exports show timezone offset drift.
    """

    base =
      """
      Incident digest:
      #{incidents}

      #{timeline}
      """

    String.duplicate(base, 2)
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
    e -> {:error, Exception.message(e)}
  end

  defp print_history_entry(idx, entry) when is_map(entry) do
    model = entry["model"] || "unknown"
    cost = format_cost(entry["cost"])
    usage = format_usage(entry["usage"])

    IO.puts("    [#{idx}] model=#{model}, cost=#{cost}, #{usage}")

    if prompt = entry["prompt"] do
      prompt_str =
        case prompt do
          text when is_binary(text) -> text
          _ -> inspect(prompt, limit: 2, printable_limit: 200)
        end

      preview = prompt_str |> String.slice(0..60) |> String.replace(~r/\s+/, " ")
      IO.puts("        prompt: #{preview}...")
    end

    if response = entry["response"] do
      if SnakeBridge.ref?(response) do
        IO.puts("        response: <#{response.type_name}> (ref)")
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

  defp summary(triage_results, rlm_result, analytics) do
    IO.puts("\n==> Summary")
    IO.puts("  Triage results: #{length(triage_results)}")

    if rlm_result.answer do
      IO.puts("  RLM summary: #{String.slice(rlm_result.answer, 0..80)}...")
    else
      IO.puts("  RLM summary: (skipped)")
    end

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

  defp deno_available? do
    System.find_executable("deno") != nil
  end

  defp print_deno_missing do
    IO.puts(ansi(:yellow, "  Deno not found; skipping RLM step."))

    Enum.each(deno_install_instructions(), fn line ->
      IO.puts(line)
    end)
  end

  defp deno_install_instructions do
    [
      "  Deno is an external runtime binary used by DSPy RLM's default interpreter.",
      "  Install (asdf):",
      "    asdf plugin add deno https://github.com/asdf-community/asdf-deno.git",
      "    asdf install",
      "  Or install directly:",
      "    curl -fsSL https://deno.land/install.sh | sh",
      "    export PATH=\"$HOME/.deno/bin:$PATH\"",
      "  Then rerun: mix run --no-start examples/flagship_multi_pool_rlm.exs"
    ]
  end

  defp ansi(color, text) do
    if IO.ANSI.enabled?() do
      IO.ANSI.format([color, :bright, text, :reset]) |> IO.iodata_to_binary()
    else
      text
    end
  end
end

DSPex.FlagshipMultiPoolRlm.run()
