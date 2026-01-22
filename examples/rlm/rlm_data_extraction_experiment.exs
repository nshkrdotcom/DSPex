# RLM Data Extraction Experiment - Real-World Structured Data Analysis
#
# This experiment demonstrates RLM's core strength: accurate extraction from
# large structured contexts where direct LLM calls fail or hallucinate.
#
# Dataset: NYC 311 Service Requests (real government data, auto-downloaded)
# Source: https://data.cityofnewyork.us/resource/erm2-nwe9.csv
#
# Run with: mix run --no-start examples/rlm/rlm_data_extraction_experiment.exs
#
# Requires:
#   - GEMINI_API_KEY (or other LLM provider)
#   - Deno for PythonInterpreter (install via `asdf install` or deno.land/install)
#   - Internet connection (first run downloads ~15MB CSV, then cached)

alias Dspy.Predict.RLMClass
alias SnakeBridge.ConfigHelper
alias Snakepit.Bridge.SessionStore

defmodule RLMExperiment.DataExtraction do
  @moduledoc """
  RLM Data Extraction Experiment

  Tests RLM's ability to accurately answer quantitative questions about
  large structured datasets where direct LLM approaches fail due to:
    1. Context truncation (can't fit 50K rows in prompt)
    2. Context rot (accuracy degrades with long context)
    3. Approximation (LLMs guess instead of computing)

  RLM solves this by storing data as a Python variable and letting the
  model write code to explore/query it.
  """
  require SnakeBridge

  # ============================================================================
  # Configuration
  # ============================================================================

  @model "gemini/gemini-flash-lite-latest"

  # Dataset configuration
  @dataset_url "https://data.cityofnewyork.us/resource/erm2-nwe9.csv"
  # Rows to download (50K = ~100K tokens when textualized)
  @dataset_limit 50_000
  @cache_dir "priv/rlm_cache"
  @cache_file "nyc_311_data.csv"

  # RLM configuration (tuned for data analysis)
  @rlm_signature "context, query -> output"
  # More iterations for complex data queries
  @rlm_max_iterations 8
  # Allow thorough exploration
  @rlm_max_llm_calls 20
  @rlm_max_output_chars 8_000
  # Trace controls (enabled by default). Set DSPY_TRACE=0 to disable.
  @trace_enabled (case System.get_env("DSPY_TRACE") do
                    nil ->
                      true

                    value ->
                      String.downcase(value) not in ["0", "false", "off", "no"]
                  end)

  @trace_history_limit (case System.get_env("DSPY_TRACE_LIMIT") do
                          nil ->
                            0

                          value ->
                            case Integer.parse(value) do
                              {num, _} -> num
                              :error -> 0
                            end
                        end)

  @trace_prompt_chars (case System.get_env("DSPY_TRACE_PROMPT_CHARS") do
                         nil ->
                           0

                         value ->
                           case Integer.parse(value) do
                             {num, _} -> num
                             :error -> 0
                           end
                       end)

  # Show RLM's reasoning/code
  @rlm_verbose (case System.get_env("DSPY_RLM_VERBOSE") do
                  nil -> @trace_enabled
                  value -> String.downcase(value) not in ["0", "false", "off", "no"]
                end)

  # Pool configuration
  @pools [
    %{name: :rlm_pool, pool_size: 2, affinity: :strict_queue},
    %{name: :direct_pool, pool_size: 2, affinity: :strict_queue},
    %{name: :analytics_pool, pool_size: 2, affinity: :hint}
  ]

  # ============================================================================
  # Entry Point
  # ============================================================================

  def run do
    # Check for Deno first
    unless deno_available?() do
      print_deno_missing()
      System.halt(1)
    end

    configure_snakepit!()

    SnakeBridge.script restart: true do
      banner()

      # Step 1: Download and cache the dataset
      IO.puts("\n#{section("Step 1: Data Acquisition")}")
      {:ok, csv_path} = ensure_dataset()
      {:ok, data_stats} = compute_data_stats(csv_path)
      print_data_stats(data_stats)

      # Step 2: Build the long context (simulate document)
      IO.puts("\n#{section("Step 2: Context Construction")}")
      {:ok, context, context_stats} = build_context(csv_path)
      print_context_stats(context_stats)

      # Step 3: Define queries with computable ground truth
      IO.puts("\n#{section("Step 3: Query Definition")}")
      queries = define_queries(data_stats)
      print_queries(queries)

      # Step 4: Run RLM on queries
      IO.puts("\n#{section("Step 4: RLM Execution")}")
      rlm_session = build_rlm_session()
      rlm_results = run_rlm_queries(rlm_session, context, queries)

      # Step 5: Run direct LLM for comparison (truncated context)
      IO.puts("\n#{section("Step 5: Direct LLM Comparison")}")
      direct_session = build_direct_session()
      direct_results = run_direct_queries(direct_session, context, queries)

      # Step 6: Evaluate accuracy
      IO.puts("\n#{section("Step 6: Accuracy Evaluation")}")
      evaluation = evaluate_results(queries, rlm_results, direct_results)

      # Step 7: Trace review
      IO.puts("\n#{section("Step 7: Trace Review")}")

      if trace_enabled?() do
        print_trace_settings()
        print_session_workers("RLM session", [rlm_session])
        print_session_workers("Direct session", [direct_session])

        IO.puts("\n  LM History via Graceful Serialization (RLM)")
        print_prompt_history("RLM", rlm_session)

        IO.puts("\n  LM History via Graceful Serialization (Direct)")
        print_prompt_history("Direct", direct_session)
      else
        IO.puts("  Tracing disabled. Set DSPY_TRACE=1 to enable.")
      end

      # Step 8: Summary
      IO.puts("\n#{section("Step 8: Summary")}")
      print_summary(evaluation, context_stats)
    end
  end

  # ============================================================================
  # Data Acquisition
  # ============================================================================

  defp ensure_dataset do
    cache_path = Path.join(@cache_dir, @cache_file)

    if File.exists?(cache_path) do
      IO.puts("  Using cached dataset: #{cache_path}")
      {:ok, cache_path}
    else
      IO.puts("  Downloading NYC 311 data (#{@dataset_limit} rows)...")
      download_dataset(cache_path)
    end
  end

  defp download_dataset(cache_path) do
    File.mkdir_p!(@cache_dir)

    # Socrata API with limit and select specific columns for smaller download
    url =
      "#{@dataset_url}?$limit=#{@dataset_limit}&$select=" <>
        "unique_key,created_date,agency,agency_name,complaint_type," <>
        "descriptor,borough,incident_address,city,status,resolution_description"

    IO.puts("  Fetching from: #{@dataset_url}")
    IO.puts("  Limit: #{@dataset_limit} rows")

    # Use :httpc from Erlang stdlib (always available)
    :inets.start()
    :ssl.start()

    case :httpc.request(:get, {String.to_charlist(url), []}, [{:timeout, 120_000}], [
           {:body_format, :binary}
         ]) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        File.write!(cache_path, body)
        size_mb = byte_size(body) / 1_000_000
        IO.puts("  Downloaded #{Float.round(size_mb, 2)} MB -> #{cache_path}")
        {:ok, cache_path}

      {:ok, {{_, status, _}, _, _}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp compute_data_stats(csv_path) do
    # Use Python (stdlib csv) for accurate stats computation
    session_id = unique_session("stats")
    ensure_session(session_id)
    runtime_opts = runtime(:analytics_pool, session_id)
    csv_abs = Path.expand(csv_path)

    code = """
    import csv
    from collections import Counter

    with open('#{csv_abs}', newline='', encoding='utf-8', errors='replace') as f:
        reader = csv.DictReader(f)
        columns = reader.fieldnames or []
        boroughs = Counter()
        agencies = Counter()
        complaint_types = Counter()
        total_rows = 0
        brooklyn_count = 0
        nypd_count = 0
        noise_count = 0
        closed_count = 0
        brooklyn_noise_closed = 0

        for row in reader:
            total_rows += 1
            borough = (row.get('borough') or '').strip()
            agency = (row.get('agency') or '').strip()
            complaint = (row.get('complaint_type') or '').strip()
            status = (row.get('status') or '').strip()

            if borough:
                boroughs[borough] += 1
            if agency:
                agencies[agency] += 1
            if complaint:
                complaint_types[complaint] += 1

            if borough == 'BROOKLYN':
                brooklyn_count += 1
            if agency == 'NYPD':
                nypd_count += 1
            if 'noise' in complaint.lower():
                noise_count += 1
            if status == 'Closed':
                closed_count += 1
            if borough == 'BROOKLYN' and 'noise' in complaint.lower() and status == 'Closed':
                brooklyn_noise_closed += 1

    top_complaint = 'Unknown'
    top_complaint_count = 0
    if complaint_types:
        top_complaint, top_complaint_count = complaint_types.most_common(1)[0]

    result = {
        'total_rows': int(total_rows),
        'columns': list(columns),
        'brooklyn_count': int(brooklyn_count),
        'nypd_count': int(nypd_count),
        'noise_count': int(noise_count),
        'closed_count': int(closed_count),
        'top_complaint': top_complaint,
        'top_complaint_count': int(top_complaint_count),
        'brooklyn_noise_closed': int(brooklyn_noise_closed),
        'boroughs': dict(boroughs),
        'agencies': dict(agencies)
    }
    """

    globals = %{"_code" => code}
    expr = "(lambda _ns: (exec(_code, _ns, _ns), _ns['result'])[1])({})"

    {:ok, stats} =
      SnakeBridge.call("builtins", "eval", [expr, globals], __runtime__: runtime_opts)

    {:ok, stats}
  rescue
    e ->
      IO.puts("  Warning: Stats computation failed: #{Exception.message(e)}")
      IO.puts("  Using fallback stats...")

      {:ok,
       %{
         "total_rows" => @dataset_limit,
         "columns" => ["unknown"],
         "brooklyn_count" => 0,
         "nypd_count" => 0,
         "noise_count" => 0,
         "closed_count" => 0,
         "top_complaint" => "Unknown",
         "top_complaint_count" => 0,
         "brooklyn_noise_closed" => 0,
         "boroughs" => %{},
         "agencies" => %{}
       }}
  end

  defp print_data_stats(stats) do
    IO.puts("  Total rows: #{stats["total_rows"]}")
    IO.puts("  Columns: #{Enum.join(stats["columns"], ", ")}")
    IO.puts("  Boroughs: #{map_size(stats["boroughs"] || %{})}")
    IO.puts("  Agencies: #{map_size(stats["agencies"] || %{})}")
  end

  # ============================================================================
  # Context Construction
  # ============================================================================

  defp build_context(csv_path) do
    session_id = unique_session("context")
    ensure_session(session_id)
    runtime_opts = runtime(:analytics_pool, session_id)
    csv_abs = Path.expand(csv_path)

    # Read CSV and build text representation using Python (stdlib csv)
    # This creates a "document-like" version of the data
    # Note: \# escapes the hash so Elixir doesn't interpret as interpolation
    code = """
    import csv

    with open('#{csv_abs}', newline='', encoding='utf-8', errors='replace') as f:
        reader = csv.DictReader(f)
        columns = reader.fieldnames or []

        lines = ['NYC 311 SERVICE REQUESTS DATA DUMP', '=' * 60]
        lines.append('Total Records: 0')
        lines.append(f'Columns: {", ".join(columns)}')
        lines.append('')
        lines.append('DATA RECORDS:')
        lines.append('-' * 60)

        total_rows = 0
        for idx, row in enumerate(reader):
            total_rows += 1
            parts = [f'Record \#{idx + 1}']
            for col in columns:
                val = row.get(col)
                if val is None:
                    continue
                val = str(val).strip()
                if not val:
                    continue
                val = val.replace('\\n', ' ').replace('\\r', ' ')
                parts.append(f'  {col}: {val}')
            lines.append('\\n'.join(parts))
            lines.append('')

        lines[2] = f'Total Records: {total_rows}'

    result = '\\n'.join(lines)
    """

    globals = %{"_code" => code}
    expr = "(lambda _ns: (exec(_code, _ns, _ns), _ns['result'])[1])({})"

    {:ok, context} =
      SnakeBridge.call("builtins", "eval", [expr, globals], __runtime__: runtime_opts)

    stats = %{
      char_count: String.length(context),
      estimated_tokens: div(String.length(context), 4),
      row_count: @dataset_limit
    }

    {:ok, context, stats}
  rescue
    e ->
      IO.puts("  Warning: Context build failed: #{Exception.message(e)}")
      # Fallback: just read the CSV as-is
      context = File.read!(csv_path)

      stats = %{
        char_count: String.length(context),
        estimated_tokens: div(String.length(context), 4),
        row_count: @dataset_limit
      }

      {:ok, context, stats}
  end

  defp print_context_stats(stats) do
    IO.puts("  Character count: #{Number.Delimit.number_to_delimited(stats.char_count)}")
    IO.puts("  Estimated tokens: ~#{Number.Delimit.number_to_delimited(stats.estimated_tokens)}")
    IO.puts("  Row count: #{stats.row_count}")
    IO.puts("  Context size: #{context_size_category(stats.estimated_tokens)}")
  end

  defp context_size_category(tokens) when tokens < 10_000, do: "Small (fits in most contexts)"
  defp context_size_category(tokens) when tokens < 50_000, do: "Medium (may cause truncation)"

  defp context_size_category(tokens) when tokens < 100_000,
    do: "Large (will cause issues for direct LLM)"

  defp context_size_category(_), do: "Very Large (RLM territory)"

  # ============================================================================
  # Query Definition
  # ============================================================================

  defp define_queries(data_stats) do
    [
      %{
        id: "Q1",
        description: "Simple count by borough",
        query: "How many service requests were made in Brooklyn?",
        ground_truth: data_stats["brooklyn_count"],
        difficulty: :easy
      },
      %{
        id: "Q2",
        description: "Count by agency",
        query: "How many requests were handled by NYPD?",
        ground_truth: data_stats["nypd_count"],
        difficulty: :easy
      },
      %{
        id: "Q3",
        description: "Pattern matching count",
        query: "How many complaints are related to noise (contain 'Noise' in complaint type)?",
        ground_truth: data_stats["noise_count"],
        difficulty: :medium
      },
      %{
        id: "Q4",
        description: "Status filtering",
        query: "How many requests have status 'Closed'?",
        ground_truth: data_stats["closed_count"],
        difficulty: :easy
      },
      %{
        id: "Q5",
        description: "Aggregation + ranking",
        query: "What is the most common complaint type and how many occurrences does it have?",
        ground_truth: "#{data_stats["top_complaint"]} (#{data_stats["top_complaint_count"]})",
        difficulty: :medium,
        exact_match: false
      },
      %{
        id: "Q6",
        description: "Complex multi-condition",
        query: "How many noise complaints in Brooklyn were closed?",
        ground_truth: data_stats["brooklyn_noise_closed"],
        difficulty: :hard
      }
    ]
  end

  defp print_queries(queries) do
    Enum.each(queries, fn q ->
      gt = if q.ground_truth == :compute, do: "(computed)", else: inspect(q.ground_truth)
      IO.puts("  #{q.id} [#{q.difficulty}]: #{q.description}")
      IO.puts("      Query: #{q.query}")
      IO.puts("      Ground truth: #{gt}")
    end)
  end

  # ============================================================================
  # RLM Execution
  # ============================================================================

  defp build_rlm_session do
    session_id = unique_session("rlm_main")
    ensure_session(session_id)

    {:ok, lm} = Dspy.LM.new(@model, [], with_runtime([temperature: 0.1], :rlm_pool, session_id))

    {:ok, _} = Dspy.configure(with_runtime([lm: lm], :rlm_pool, session_id))

    {:ok, rlm} =
      RLMClass.new(
        @rlm_signature,
        @rlm_max_iterations,
        @rlm_max_llm_calls,
        @rlm_max_output_chars,
        @rlm_verbose,
        # tools
        [],
        # sub_lm
        nil,
        # interpreter
        nil,
        with_runtime([], :rlm_pool, session_id)
      )

    %{
      label: "rlm",
      session_id: session_id,
      pool: :rlm_pool,
      rlm: rlm,
      lm: lm
    }
  end

  defp run_rlm_queries(session, context, queries) do
    IO.puts("\n  Running RLM on #{length(queries)} queries...")
    IO.puts("  (RLM will store context as Python variable and write code to query it)\n")

    Enum.map(queries, fn query ->
      IO.puts("  #{query.id}: #{query.query}")
      start_time = System.monotonic_time(:millisecond)

      result = run_single_rlm_query(session, context, query.query)

      elapsed = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, answer} ->
          IO.puts("      RLM Answer: #{answer}")
          IO.puts("      Time: #{elapsed}ms")
          %{query_id: query.id, answer: answer, elapsed_ms: elapsed, error: nil}

        {:error, reason} ->
          IO.puts("      RLM Error: #{inspect(reason)}")
          %{query_id: query.id, answer: nil, elapsed_ms: elapsed, error: reason}
      end
    end)
  end

  defp run_single_rlm_query(session, context, query) do
    # Add instructions for data analysis
    augmented_query = """
    #{query}

    The context contains NYC 311 service request data in text format.
    Each record has fields like: borough, agency, complaint_type, status, etc.
    Write Python code to parse and analyze the data to find the exact answer.
    Return ONLY the numeric answer or a brief factual response.
    """

    opts =
      with_runtime(
        [context: context, query: augmented_query],
        session.pool,
        session.session_id
      )

    case RLMClass.forward(session.rlm, opts) do
      {:ok, result} ->
        runtime_opts = runtime(session.pool, session.session_id)
        {:ok, answer} = SnakeBridge.attr(result, "output", __runtime__: runtime_opts)
        {:ok, to_string(answer)}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # ============================================================================
  # Direct LLM Comparison
  # ============================================================================

  defp build_direct_session do
    session_id = unique_session("direct_main")
    ensure_session(session_id)

    {:ok, lm} =
      Dspy.LM.new(@model, [], with_runtime([temperature: 0.1], :direct_pool, session_id))

    {:ok, _} = Dspy.configure(with_runtime([lm: lm], :direct_pool, session_id))

    {:ok, predictor} =
      Dspy.PredictClass.new(
        "context, question -> answer",
        [],
        with_runtime([], :direct_pool, session_id)
      )

    %{
      label: "direct",
      session_id: session_id,
      pool: :direct_pool,
      predictor: predictor,
      lm: lm
    }
  end

  defp run_direct_queries(session, context, queries) do
    IO.puts("\n  Running Direct LLM on #{length(queries)} queries...")
    IO.puts("  (Direct approach: pass truncated context in prompt)\n")

    # Truncate context to fit typical context window
    # Most models can handle ~100K tokens, but we simulate realistic limits
    # ~7.5K tokens - simulating a smaller model
    max_context_chars = 30_000
    truncated_context = String.slice(context, 0, max_context_chars)
    truncated_pct = Float.round(max_context_chars / String.length(context) * 100, 1)

    IO.puts("  Context truncated to #{max_context_chars} chars (#{truncated_pct}% of full data)")

    Enum.map(queries, fn query ->
      IO.puts("  #{query.id}: #{query.query}")
      start_time = System.monotonic_time(:millisecond)

      result = run_single_direct_query(session, truncated_context, query.query)

      elapsed = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, answer} ->
          IO.puts("      Direct Answer: #{answer}")
          IO.puts("      Time: #{elapsed}ms")
          %{query_id: query.id, answer: answer, elapsed_ms: elapsed, error: nil}

        {:error, reason} ->
          IO.puts("      Direct Error: #{inspect(reason)}")
          %{query_id: query.id, answer: nil, elapsed_ms: elapsed, error: reason}
      end
    end)
  end

  defp run_single_direct_query(session, context, question) do
    augmented_question = """
    #{question}

    Answer with ONLY the numeric value or brief factual response.
    If you cannot determine the exact answer from the context, say "UNKNOWN".
    """

    opts =
      with_runtime(
        [context: context, question: augmented_question],
        session.pool,
        session.session_id
      )

    case Dspy.PredictClass.forward(session.predictor, opts) do
      {:ok, result} ->
        runtime_opts = runtime(session.pool, session.session_id)
        {:ok, answer} = SnakeBridge.attr(result, "answer", __runtime__: runtime_opts)
        {:ok, to_string(answer)}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # ============================================================================
  # Evaluation
  # ============================================================================

  defp evaluate_results(queries, rlm_results, direct_results) do
    evaluations =
      Enum.map(queries, fn query ->
        rlm_result = Enum.find(rlm_results, &(&1.query_id == query.id))
        direct_result = Enum.find(direct_results, &(&1.query_id == query.id))

        rlm_correct = evaluate_answer(query, rlm_result)
        direct_correct = evaluate_answer(query, direct_result)

        IO.puts("  #{query.id}:")
        IO.puts("      Ground truth: #{inspect(query.ground_truth)}")
        IO.puts("      RLM: #{rlm_result.answer || "ERROR"} -> #{status_emoji(rlm_correct)}")

        IO.puts(
          "      Direct: #{direct_result.answer || "ERROR"} -> #{status_emoji(direct_correct)}"
        )

        %{
          query_id: query.id,
          difficulty: query.difficulty,
          rlm_correct: rlm_correct,
          direct_correct: direct_correct,
          rlm_answer: rlm_result.answer,
          direct_answer: direct_result.answer,
          ground_truth: query.ground_truth
        }
      end)

    rlm_accuracy = Enum.count(evaluations, & &1.rlm_correct) / length(evaluations) * 100
    direct_accuracy = Enum.count(evaluations, & &1.direct_correct) / length(evaluations) * 100

    %{
      evaluations: evaluations,
      rlm_accuracy: rlm_accuracy,
      direct_accuracy: direct_accuracy,
      rlm_correct_count: Enum.count(evaluations, & &1.rlm_correct),
      direct_correct_count: Enum.count(evaluations, & &1.direct_correct),
      total_queries: length(queries)
    }
  end

  defp evaluate_answer(_query, %{error: error}) when not is_nil(error), do: false
  defp evaluate_answer(_query, %{answer: nil}), do: false

  defp evaluate_answer(%{ground_truth: gt, exact_match: false}, %{answer: answer}) do
    gt_str = to_string(gt)
    answer_str = to_string(answer)

    gt_norm = normalize_text(gt_str)
    answer_norm = normalize_text(answer_str)

    check_fuzzy_match(gt_str, answer_str, gt_norm, answer_norm)
  end

  defp evaluate_answer(%{ground_truth: gt}, %{answer: answer}) when is_integer(gt) do
    # Extract numbers from answer and compare
    case extract_number(answer) do
      {:ok, num} -> num == gt
      :error -> false
    end
  end

  defp evaluate_answer(%{ground_truth: gt}, %{answer: answer}) do
    to_string(gt) == to_string(answer)
  end

  defp check_fuzzy_match(_gt_str, _answer_str, gt_norm, answer_norm)
       when gt_norm == "" or answer_norm == "",
       do: false

  defp check_fuzzy_match(_gt_str, _answer_str, gt_norm, answer_norm)
       when gt_norm == answer_norm,
       do: true

  defp check_fuzzy_match(gt_str, answer_str, gt_norm, answer_norm) do
    if String.contains?(answer_norm, gt_norm) do
      true
    else
      check_label_and_count_match(gt_str, answer_str)
    end
  end

  defp check_label_and_count_match(gt_str, answer_str) do
    {gt_label, gt_count} = split_label_and_count(gt_str)
    {answer_label, answer_count} = split_label_and_count(answer_str)

    label_match? = labels_match?(gt_label, answer_label)
    count_match? = counts_match?(gt_count, answer_count, answer_str)

    label_match? and count_match?
  end

  defp labels_match?(gt_label, answer_label) do
    gt_label != "" and answer_label != "" and
      normalize_text(gt_label) == normalize_text(answer_label)
  end

  defp counts_match?(nil, _, _), do: false
  defp counts_match?(count, nil, answer_str), do: extract_and_compare(answer_str, count)
  defp counts_match?(count, num, _), do: count == num

  defp extract_and_compare(answer_str, count) do
    case extract_number(answer_str) do
      {:ok, num} -> num == count
      :error -> false
    end
  end

  defp extract_number(text) do
    # Extract the first number from text
    case Regex.run(~r/[\d,]+/, to_string(text)) do
      [match] ->
        clean = String.replace(match, ",", "")

        case Integer.parse(clean) do
          {num, _} -> {:ok, num}
          :error -> :error
        end

      nil ->
        :error
    end
  end

  defp split_label_and_count(text) do
    label =
      text
      |> String.replace(~r/[\d,]+/, " ")
      |> String.trim()

    count =
      case Regex.run(~r/(\d[\d,]*)/, text) do
        [_, match] ->
          match
          |> String.replace(",", "")
          |> Integer.parse()
          |> case do
            {num, _} -> num
            :error -> nil
          end

        _ ->
          nil
      end

    {label, count}
  end

  defp normalize_text(text) do
    text
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, " ")
    |> String.trim()
  end

  defp status_emoji(true), do: "✅ CORRECT"
  defp status_emoji(false), do: "❌ WRONG"

  # ============================================================================
  # Summary
  # ============================================================================

  defp print_summary(evaluation, context_stats) do
    IO.puts("""

    ╔══════════════════════════════════════════════════════════════════╗
    ║                    RLM EXPERIMENT RESULTS                         ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║  Context Size: ~#{String.pad_leading(to_string(context_stats.estimated_tokens), 6)} tokens (#{context_stats.row_count} rows)              ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║                                                                   ║
    ║  RLM Accuracy:    #{format_accuracy(evaluation.rlm_accuracy)} (#{evaluation.rlm_correct_count}/#{evaluation.total_queries})                           ║
    ║  Direct Accuracy: #{format_accuracy(evaluation.direct_accuracy)} (#{evaluation.direct_correct_count}/#{evaluation.total_queries})                           ║
    ║                                                                   ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║  CONCLUSION:                                                      ║
    ║  #{conclusion(evaluation)}
    ╚══════════════════════════════════════════════════════════════════╝
    """)

    # Per-difficulty breakdown
    IO.puts("  Breakdown by difficulty:")

    for diff <- [:easy, :medium, :hard] do
      subset = Enum.filter(evaluation.evaluations, &(&1.difficulty == diff))

      if subset != [] do
        rlm_acc = Enum.count(subset, & &1.rlm_correct) / length(subset) * 100
        direct_acc = Enum.count(subset, & &1.direct_correct) / length(subset) * 100

        IO.puts(
          "    #{diff}: RLM #{Float.round(rlm_acc, 0)}% vs Direct #{Float.round(direct_acc, 0)}%"
        )
      end
    end
  end

  defp format_accuracy(acc), do: String.pad_leading("#{Float.round(acc, 1)}%", 6)

  defp conclusion(eval) do
    cond do
      eval.rlm_accuracy > eval.direct_accuracy + 20 ->
        "RLM significantly outperforms direct LLM on structured data. ║"

      eval.rlm_accuracy > eval.direct_accuracy ->
        "RLM outperforms direct LLM as expected.                      ║"

      eval.rlm_accuracy == eval.direct_accuracy ->
        "Tie - try with larger context to see RLM advantage.          ║"

      true ->
        "Unexpected: Direct beat RLM. Check RLM configuration.        ║"
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp configure_snakepit! do
    ConfigHelper.snakepit_config(pools: @pools)
    |> Enum.each(fn {key, value} ->
      Application.put_env(:snakepit, key, value)
    end)
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

  defp print_prompt_history(label, session) do
    runtime_opts = runtime(session.pool, session.session_id)
    IO.puts("  #{label}:")

    case fetch_prompt_history(session, runtime_opts, trace_history_limit()) do
      {:ok, []} ->
        IO.puts("    (no history)")

      {:ok, history} ->
        Enum.with_index(history, 1)
        |> Enum.each(fn {entry, idx} ->
          print_history_entry(idx, entry, runtime_opts)
        end)

      {:error, reason} ->
        IO.puts("    (history fetch failed: #{reason})")
    end
  end

  defp fetch_prompt_history(session, runtime_opts, limit) do
    lm = Map.fetch!(session, :lm)

    code =
      case limit do
        :all -> "list(lm.history)"
        _ -> "list(lm.history[-#{limit}:])"
      end

    {:ok, history} =
      SnakeBridge.call("builtins", "eval", [code, %{"lm" => lm}], __runtime__: runtime_opts)

    if is_list(history) do
      {:ok, history}
    else
      {:ok, []}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp print_history_entry(idx, entry, runtime_opts) when is_map(entry) do
    model = entry["model"] || "unknown"
    cost = format_cost(entry["cost"])
    usage = format_usage(entry["usage"])

    IO.puts("    [#{idx}] model=#{model}, cost=#{cost}, #{usage}")

    if prompt = entry["prompt"] do
      prompt_str = render_history_value(prompt, runtime_opts)
      print_trace_block("prompt", prompt_str, trace_prompt_limit())
    end

    if response = entry["response"] do
      response_str = render_history_value(response, runtime_opts)
      print_trace_block("response", response_str, trace_prompt_limit())
    end

    meta = Map.drop(entry, ["model", "cost", "usage", "prompt", "response"])

    if map_size(meta) > 0 do
      meta_str = inspect(meta, limit: :infinity, printable_limit: 2_000)
      print_trace_block("meta", meta_str, trace_prompt_limit())
    end
  end

  defp print_history_entry(idx, _entry, _runtime_opts) do
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

  defp render_history_value(value, runtime_opts) do
    cond do
      is_binary(value) ->
        value

      SnakeBridge.ref?(value) ->
        render_ref_value(value, runtime_opts)

      true ->
        inspect(value, limit: :infinity, printable_limit: :infinity)
    end
  end

  defp render_ref_value(ref, runtime_opts) do
    case SnakeBridge.call("builtins", "repr", [ref], __runtime__: runtime_opts) do
      {:ok, repr} -> to_string(repr)
      {:error, _} -> "<#{ref.type_name}> (ref)"
    end
  rescue
    _ -> "<ref>"
  end

  defp print_trace_block(label, text, limit) do
    {snippet, truncated?} = maybe_truncate(text, limit)
    header = if truncated?, do: "#{label} (truncated)", else: label

    IO.puts("        #{header}:")

    snippet
    |> String.split("\n")
    |> Enum.each(fn line ->
      IO.puts("          #{line}")
    end)
  end

  defp maybe_truncate(text, :all), do: {text, false}

  defp maybe_truncate(text, limit) when is_integer(limit) and limit > 0 do
    if String.length(text) > limit do
      {String.slice(text, 0, limit) <> " ...", true}
    else
      {text, false}
    end
  end

  defp maybe_truncate(text, _limit), do: {text, false}

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

  defp trace_enabled?, do: @trace_enabled

  defp trace_history_limit do
    if @trace_history_limit > 0, do: @trace_history_limit, else: :all
  end

  defp trace_prompt_limit do
    if @trace_prompt_chars > 0, do: @trace_prompt_chars, else: :all
  end

  defp print_trace_settings do
    IO.puts("  Trace: on")

    history =
      case trace_history_limit() do
        :all -> "all"
        limit -> Integer.to_string(limit)
      end

    prompt =
      case trace_prompt_limit() do
        :all -> "full"
        limit -> Integer.to_string(limit)
      end

    IO.puts("  History limit: #{history}")
    IO.puts("  Prompt chars: #{prompt}")
  end

  defp section(title) do
    width = 64
    padding = div(width - String.length(title) - 4, 2)
    "#{String.duplicate("=", padding)} #{title} #{String.duplicate("=", padding)}"
  end

  defp deno_available? do
    System.find_executable("deno") != nil
  end

  defp print_deno_missing do
    IO.puts("""

    ╔══════════════════════════════════════════════════════════════════╗
    ║  ERROR: Deno Runtime Not Found                                    ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║                                                                   ║
    ║  RLM requires Deno for its PythonInterpreter sandbox.             ║
    ║                                                                   ║
    ║  Install via asdf (recommended):                                  ║
    ║    asdf plugin add deno https://github.com/asdf-community/asdf-deno.git
    ║    asdf install                                                   ║
    ║                                                                   ║
    ║  Or install directly:                                             ║
    ║    curl -fsSL https://deno.land/install.sh | sh                   ║
    ║    export PATH="$HOME/.deno/bin:$PATH"                            ║
    ║                                                                   ║
    ║  Then rerun this experiment.                                      ║
    ╚══════════════════════════════════════════════════════════════════╝
    """)
  end

  defp banner do
    IO.puts("""

    ╔══════════════════════════════════════════════════════════════════╗
    ║           RLM DATA EXTRACTION EXPERIMENT                          ║
    ║                                                                   ║
    ║  Testing Recursive Language Model's ability to accurately         ║
    ║  extract information from large structured datasets where         ║
    ║  direct LLM approaches fail due to context limitations.           ║
    ║                                                                   ║
    ║  Dataset: NYC 311 Service Requests (50,000 records)               ║
    ║  Source:  data.cityofnewyork.us (Socrata Open Data API)           ║
    ╚══════════════════════════════════════════════════════════════════╝
    """)
  end
end

# Simple number formatting helper (avoiding deps)
defmodule Number.Delimit do
  def number_to_delimited(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  def number_to_delimited(number), do: to_string(number)
end

# Run the experiment
RLMExperiment.DataExtraction.run()
