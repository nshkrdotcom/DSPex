# DSPy API Introspection - RLM over generated Elixir wrapper
#
# Run with:
#   mix run --no-start examples/introspect/dspy_api_introspect.exs
#
# Requires:
#   - GEMINI_API_KEY (or other LLM provider)
#   - Deno for PythonInterpreter (install via `asdf install` or deno.land/install)
#
# Examples:
#   mix run --no-start examples/introspect/dspy_api_introspect.exs
#   mix run --no-start examples/introspect/dspy_api_introspect.exs --preset rlm
#   mix run --no-start examples/introspect/dspy_api_introspect.exs \
#     --prompt "Summarize RLM usage only" --signature "context, query -> output"

alias Dspy.Predict.RLM
alias SnakeBridge.ConfigHelper
alias Snakepit.Bridge.SessionStore

defmodule DSPex.DspyApiIntrospect do
  @moduledoc false
  require SnakeBridge

  @default_model "gemini/gemini-flash-lite-latest"
  @default_signature "context, query -> output"
  @default_file "lib/snakebridge_generated/dspy"
  @default_preset "api"
  @default_temperature 0.1
  @default_max_iterations 6
  @default_max_llm_calls 30
  @default_max_output_chars 6_000
  @default_pool "rlm_pool"
  @default_pool_size 1
  @default_trace_limit 30
  @default_trace_prompt_chars 2000
  @default_result_chars 0
  @hard_trace_prompt_chars 8000
  @hard_result_chars 500_000
  @default_context_header_lines 200
  @default_context_window_before 6
  @default_context_window_after 12

  @prompt_rules """
  Rules:
  - Prefer evidence from the wrapper sources; cite line numbers when possible.
  - If the context spans multiple files, include the file path in citations (path:L123).
  - Prefer full-context scans over sampling; if you sample, say so explicitly.
  - If an item is missing, say "not found".
  - Output only the final answer; no reasoning, planning, or meta commentary.
  - Do not mention limitations, slowness, or the analysis process.
  - Output plain text with headings and bullets; no JSON, YAML, or Python dicts.
  """

  @prompt_rules_full """
  Additional rules for comprehensive requests:
  - Cover all major sections and key entry points, but avoid full function dumps.
  - Use counts + representative examples when the surface is large.
  """

  @prompt_rules_summary """
  Additional rules for focused summaries:
  - Use the FACTS section to anchor names and line numbers.
  - Cover only the requested scope (RLM + basics like signatures and LM).
  - Exclude internal wrappers (names starting with "__", "__snakebridge", "__functions__", "__classes__").
  - Organize by sections and list only key entry points per section.
  """

  @prompt_api """
              Build a compact API cheat sheet from the Elixir wrapper sources.

              Requirements:
              - List core modules and functions (configure, LM.new, PredictClass, RLM).
              - Explain how __runtime__ (pool_name/session_id) is passed.
              - Mention history inspection (Dspy.inspect_history or lm.history).
              - Output 8-12 short bullets.
              - Include two CLI examples for this script using --prompt and --signature.
              """ <> @prompt_rules

  @prompt_predict """
                  From the Elixir wrapper sources, show a minimal Predict workflow.
                  Return a short list plus a tiny code snippet.
                  """ <> @prompt_rules

  @prompt_rlm """
              From the Elixir wrapper sources, show a minimal RLM workflow.
              Return a compact summary with a tiny code snippet.
              """ <> @prompt_rules

  @prompt_history """
                  Identify history and tracing APIs in the wrapper sources.
                  Return a compact reference with a tiny code snippet.
                  """ <> @prompt_rules

  def run(argv \\ System.argv()) do
    {opts, parsed} = parse_args(argv)

    if opts.help do
      print_help()
      System.halt(0)
    end

    unless deno_available?() do
      print_deno_missing()
      System.halt(1)
    end

    configure_snakepit!(opts)

    SnakeBridge.script restart: true do
      {:ok, context, stats, sources} = load_context(opts.file, opts)
      query = augment_query(opts.query, sources, opts)
      opts = %{opts | query: query}

      banner(opts)
      print_file_stats(stats)

      session = build_rlm_session(opts)

      case run_query(session, context, opts.query) do
        {:ok, answer} ->
          print_section("Result")
          print_result(answer, opts, session)

        {:error, reason} ->
          raise "RLM error: #{inspect(reason)}"
      end

      if trace_enabled?(opts, parsed) do
        print_section("Trace Review")
        print_trace_settings(opts)
        print_session_workers("RLM session", [session])
        print_prompt_history("RLM", session, opts)
      else
        print_section("Trace Review")
        IO.puts("  Tracing disabled. Use --trace to enable.")
      end
    end
  end

  defp parse_args(argv) do
    switches = [
      preset: :string,
      prompt: :string,
      query: :string,
      signature: :string,
      file: :string,
      model: :string,
      temperature: :float,
      max_iterations: :integer,
      max_llm_calls: :integer,
      max_output_chars: :integer,
      pool: :string,
      pool_size: :integer,
      full_context: :boolean,
      trace: :boolean,
      trace_limit: :integer,
      trace_prompt_chars: :integer,
      result_chars: :integer,
      rlm_verbose: :boolean,
      rules: :boolean,
      facts: :boolean,
      help: :boolean
    ]

    aliases = [
      p: :prompt,
      q: :query,
      s: :signature,
      f: :file,
      m: :model,
      h: :help
    ]

    {parsed, _args, _invalid} = OptionParser.parse(argv, switches: switches, aliases: aliases)
    parsed_map = Map.new(parsed)

    defaults = %{
      preset: @default_preset,
      prompt: nil,
      query: nil,
      query_source: :preset,
      signature: @default_signature,
      file: @default_file,
      model: @default_model,
      temperature: @default_temperature,
      max_iterations: @default_max_iterations,
      max_llm_calls: @default_max_llm_calls,
      max_output_chars: @default_max_output_chars,
      pool: @default_pool,
      pool_size: @default_pool_size,
      trace: true,
      trace_limit: @default_trace_limit,
      trace_prompt_chars: @default_trace_prompt_chars,
      result_chars: @default_result_chars,
      full_context: true,
      rlm_verbose: :inherit,
      rules: :inherit,
      facts: :inherit,
      help: false
    }

    opts =
      defaults
      |> Map.merge(parsed_map)
      |> normalize_preset()
      |> normalize_query()
      |> normalize_rules(parsed_map)
      |> normalize_facts(parsed_map)
      |> normalize_rlm_verbose(parsed_map)

    {opts, parsed_map}
  end

  defp normalize_preset(opts) do
    preset = opts.preset |> to_string() |> String.downcase()

    if preset in preset_keys() do
      %{opts | preset: preset}
    else
      %{opts | preset: @default_preset}
    end
  end

  defp normalize_query(opts) do
    {query, source} =
      cond do
        is_binary(opts.prompt) and opts.prompt != "" ->
          {opts.prompt, :user}

        is_binary(opts.query) and opts.query != "" ->
          {opts.query, :user}

        true ->
          {preset_prompt(opts.preset), :preset}
      end

    %{opts | query: query, query_source: source}
  end

  defp normalize_rules(opts, parsed_map) do
    rules =
      case Map.fetch(parsed_map, :rules) do
        {:ok, value} -> value
        :error -> opts.query_source == :preset
      end

    query = if rules, do: ensure_prompt_rules(opts.query), else: opts.query
    %{opts | rules: rules, query: query}
  end

  defp normalize_facts(opts, parsed_map) do
    facts =
      case Map.fetch(parsed_map, :facts) do
        {:ok, value} -> value
        :error -> opts.query_source == :preset
      end

    %{opts | facts: facts}
  end

  defp ensure_prompt_rules(query) do
    base =
      if String.contains?(query, "Rules:") do
        query
      else
        query <> "\n\n" <> @prompt_rules
      end

    cond do
      basics_query?(query) ->
        base <> "\n\n" <> @prompt_rules_summary

      comprehensive_query?(query) ->
        base <> "\n\n" <> @prompt_rules_full

      true ->
        base
    end
  end

  defp comprehensive_query?(query) do
    down = String.downcase(query)
    Regex.match?(~r/\bcomprehensive\b|\bfull\b|\ball\b/, down)
  end

  defp basics_query?(query) do
    down = String.downcase(query)
    Regex.match?(~r/\brlm\b|\bsignature\b|\bbasics\b/, down)
  end

  defp augment_query(query, sources, opts) do
    if opts.facts do
      facts = build_fact_pack(sources, query)

      if facts == "" do
        query
      else
        query <> "\n\nFACTS (extracted from full context):\n" <> facts
      end
    else
      query
    end
  end

  defp build_fact_pack(sources, query) do
    patterns = [
      {"Module Dspy", ~r/^defmodule Dspy\b/},
      {"Runtime Options", ~r/## Runtime Options/},
      {"__runtime__ doc", ~r/__runtime__/},
      {"configure/1", ~r/^\s+def\s+configure\b/},
      {"inspect_history/0", ~r/^\s+def\s+inspect_history\b/},
      {"LM module", ~r/^\s*defmodule\s+Dspy\.LM\b/},
      {"PredictClass module", ~r/^\s*defmodule\s+Dspy\.PredictClass\b/},
      {"Predict.PredictClass3 module", ~r/^\s*defmodule\s+Dspy\.Predict\.PredictClass3\b/},
      {"Predict.RLM module", ~r/^\s*defmodule\s+Dspy\.Predict\.RLM\b/},
      {"Signature module", ~r/^\s*defmodule\s+Dspy\.Signature\b/},
      {"Signatures.Signature module", ~r/^\s*defmodule\s+Dspy\.Signatures\.Signature\b/},
      {"make_signature/1", ~r/^\s+def\s+make_signature\b/},
      {"ensure_signature/1", ~r/^\s+def\s+ensure_signature\b/}
    ]

    base_hits =
      patterns
      |> Enum.flat_map(fn {label, regex} ->
        format_hits(sources, label, regex, 3)
      end)

    rlm_defs =
      if basics_query?(query),
        do: extract_module_defs(sources, "Dspy.Predict.RLM", :all),
        else: []

    sig_defs =
      if basics_query?(query),
        do: extract_module_defs(sources, "Dspy.Signatures.Signature", :all),
        else: []

    signature_defs =
      if basics_query?(query), do: extract_module_defs(sources, "Dspy.Signature", :all), else: []

    inventory =
      if comprehensive_query?(query) do
        module_inventory(sources) ++ function_inventory(sources)
      else
        []
      end

    facts =
      base_hits ++
        format_block("RLM defs", rlm_defs) ++
        format_block("Signature defs", sig_defs) ++
        format_block("Signature (class) defs", signature_defs) ++
        inventory

    facts
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp format_hits(sources, label, regex, max_hits) do
    matches =
      sources
      |> Enum.flat_map(fn source ->
        source_lines(source)
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _idx} -> Regex.match?(regex, line) end)
        |> Enum.map(fn {line, idx} -> {source.path, idx, line} end)
      end)
      |> Enum.take(max_hits)

    if matches == [] do
      ["#{label}: not found"]
    else
      ["#{label}:"] ++ Enum.map(matches, &format_fact_line/1)
    end
  end

  defp format_block(_label, []), do: []

  defp format_block(label, lines) do
    [label <> ":"] ++ Enum.map(lines, &format_fact_line/1)
  end

  defp format_fact_line({path, idx, line}) do
    "  #{relative_path(path)}:L#{idx}: #{String.trim(line)}"
  end

  defp format_fact_line({idx, line}) do
    "  L#{idx}: #{line}"
  end

  defp module_inventory(sources) do
    modules =
      sources
      |> Enum.flat_map(&modules_from_source/1)

    prefixes =
      modules
      |> Enum.map(fn mod -> mod |> String.split(".", parts: 2) |> List.first() end)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_name, count} -> -count end)
      |> Enum.take(12)
      |> Enum.map(fn {name, count} -> "  #{name}: #{count} modules" end)

    ["Module inventory (top prefixes):" | prefixes]
  end

  defp function_inventory(sources) do
    defs =
      sources
      |> Enum.map(&count_function_defs/1)
      |> Enum.sum()

    internal =
      sources
      |> Enum.map(&count_internal_defs/1)
      |> Enum.sum()

    [
      "Function inventory:",
      "  total defs: #{defs}",
      "  internal defs (__*): #{internal}"
    ]
  end

  defp extract_module_defs(sources, module_name, max_hits) do
    sources
    |> Enum.flat_map(&extract_module_defs_from_source(&1, module_name))
    |> take_hits(max_hits)
  end

  defp extract_module_defs_from_source(source, module_name) do
    lines = source_lines(source)

    case find_module_start(lines, module_name) do
      nil ->
        []

      {start_idx, indent} ->
        extract_defs_from_module(source.path, lines, start_idx, indent)
    end
  end

  defp find_module_start(lines, module_name) do
    pattern = ~r/^\s*defmodule\s+#{Regex.escape(module_name)}\b/

    Enum.find_value(Enum.with_index(lines), fn {line, idx} ->
      if Regex.match?(pattern, line), do: {idx, leading_spaces(line)}
    end)
  end

  defp extract_defs_from_module(path, lines, start_idx, indent) do
    end_idx = find_module_end(lines, start_idx + 1, indent)

    lines
    |> Enum.slice(start_idx, end_idx - start_idx + 1)
    |> Enum.with_index(start_idx + 1)
    |> Enum.filter(fn {line, _idx} -> Regex.match?(~r/^\s+def\s+/, line) end)
    |> Enum.map(fn {line, idx} -> {path, idx, String.trim(line)} end)
    |> Enum.reject(&internal_def?/1)
  end

  defp internal_def?({_path, _idx, line}) do
    String.starts_with?(line, "def __snakebridge") or String.starts_with?(line, "def __")
  end

  defp take_hits(lines, :all), do: lines
  defp take_hits(lines, max_hits) when is_integer(max_hits), do: Enum.take(lines, max_hits)

  defp find_module_end(lines, idx, indent) do
    last = length(lines) - 1
    prefix = String.duplicate(" ", indent)

    Enum.reduce_while(idx..last, last, fn i, _acc ->
      line = Enum.at(lines, i)

      if String.starts_with?(line, prefix <> "end") do
        {:halt, i}
      else
        {:cont, last}
      end
    end)
  end

  defp leading_spaces(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 == " "))
    |> length()
  end

  defp normalize_rlm_verbose(opts, parsed_map) do
    rlm_verbose =
      case Map.fetch(parsed_map, :rlm_verbose) do
        {:ok, value} -> value
        :error -> trace_enabled?(opts, parsed_map)
      end

    %{opts | rlm_verbose: rlm_verbose}
  end

  defp preset_keys, do: ["api", "predict", "rlm", "history"]

  defp preset_prompt("predict"), do: @prompt_predict
  defp preset_prompt("rlm"), do: @prompt_rlm
  defp preset_prompt("history"), do: @prompt_history
  defp preset_prompt(_), do: @prompt_api

  defp trace_enabled?(opts, parsed_map) do
    case Map.fetch(parsed_map, :trace) do
      {:ok, value} -> value
      :error -> opts.trace
    end
  end

  defp banner(opts) do
    {inputs, outputs} = signature_fields(opts.signature)
    IO.puts(ansi(:cyan, "DSPy API Introspect (RLM)"))
    IO.puts(ansi(:cyan, String.duplicate("=", 64)))
    print_kv("Preset", opts.preset)
    print_kv("Model", opts.model)
    print_kv("Path", opts.file)
    print_kv("Signature", opts.signature)
    print_kv("Inputs", Enum.join(inputs, ", "))
    print_kv("Outputs", Enum.join(outputs, ", "))
    print_kv("Query source", opts.query_source)
    print_kv("Rules", if(opts.rules, do: "on", else: "off"))
    print_kv("Facts", if(opts.facts, do: "on", else: "off"))
    print_kv("Query chars", String.length(opts.query))
    print_kv("Query preview", preview(opts.query, 160))
    IO.puts("  Tip: use --prompt or --signature to override the defaults.")
  end

  defp load_context(file, opts) do
    path = Path.expand(file)
    sources = load_sources(path)
    stats = sources_stats(path, sources)

    context =
      if opts.full_context do
        build_full_context(sources)
      else
        build_digest_context(sources, stats)
      end

    stats =
      Map.merge(stats, %{
        context_mode: if(opts.full_context, do: "full", else: "digest"),
        context_chars: String.length(context)
      })

    {:ok, context, stats, sources}
  end

  defp load_sources(path) do
    cond do
      File.dir?(path) ->
        files =
          path
          |> Path.join("**/*.ex")
          |> Path.wildcard()
          |> Enum.sort()

        if files == [] do
          raise "No .ex files found under: #{path}"
        end

        Enum.map(files, &source_from_file/1)

      File.exists?(path) ->
        [source_from_file(path)]

      true ->
        raise "Path not found: #{path}"
    end
  end

  defp source_from_file(path) do
    content = File.read!(path)

    %{
      path: path,
      content: content,
      bytes: byte_size(content),
      lines: count_lines(content)
    }
  end

  defp count_lines(content) do
    content
    |> String.split("\n", trim: false)
    |> length()
  end

  defp source_lines(source) do
    String.split(source.content, "\n", trim: false)
  end

  defp relative_path(path) do
    cwd = File.cwd!()
    rel = Path.relative_to(path, cwd)
    if rel == "", do: path, else: rel
  rescue
    _ -> path
  end

  defp sources_stats(path, sources) do
    modules =
      sources
      |> Enum.flat_map(&modules_from_source/1)
      |> MapSet.new()
      |> MapSet.size()

    %{
      path: path,
      files: length(sources),
      bytes: Enum.reduce(sources, 0, fn source, acc -> acc + source.bytes end),
      lines: Enum.reduce(sources, 0, fn source, acc -> acc + source.lines end),
      modules: modules,
      functions: Enum.reduce(sources, 0, fn source, acc -> acc + count_function_defs(source) end)
    }
  end

  defp modules_from_source(source) do
    Regex.scan(~r/^\s*defmodule\s+([A-Za-z0-9_.]+)/m, source.content)
    |> Enum.map(fn [_, name] -> name end)
  end

  defp count_function_defs(source) do
    Regex.scan(~r/^\s+defp?\s+[A-Za-z0-9_?!]+/m, source.content)
    |> length()
  end

  defp count_internal_defs(source) do
    Regex.scan(~r/^\s+def\s+__/m, source.content)
    |> length()
  end

  defp build_full_context(sources) do
    sources
    |> Enum.map_join("\n\n", fn source ->
      header = "== File: #{relative_path(source.path)} =="
      [header, source.content] |> Enum.join("\n")
    end)
  end

  defp build_digest_context(sources, stats) do
    header = """
    DSPy Elixir wrapper digest (selected sections).
    Path: #{stats.path}
    Files: #{stats.files}
    Lines: #{stats.lines}
    Modules: #{stats.modules}
    Functions: #{stats.functions}
    Note: Digest mode keeps the context small. Use --full-context for the entire wrapper set.
    """

    sections =
      sources
      |> Enum.map(&build_digest_section/1)
      |> Enum.reject(&(&1 == ""))

    [header | sections]
    |> Enum.join("\n\n")
  end

  defp build_digest_section(source) do
    lines = source_lines(source)
    total_lines = length(lines)

    header_lines = Enum.slice(lines, 0, min(@default_context_header_lines, total_lines))

    ranges =
      find_context_ranges(
        lines,
        [
          ~r/^\s+def\s+configure\b/,
          ~r/^\s+def\s+inspect_history\b/,
          ~r/^\s*defmodule\s+Dspy\.LM\b/,
          ~r/^\s*defmodule\s+Dspy\.Predict\.RLM\b/,
          ~r/^\s*defmodule\s+Dspy\.PredictClass\b/,
          ~r/## Runtime Options/,
          ~r/__runtime__/
        ],
        @default_context_window_before,
        @default_context_window_after
      )

    selected =
      ranges
      |> Enum.flat_map(fn {start_idx, end_idx} ->
        ["", "-----", "lines #{start_idx + 1}-#{end_idx + 1}"] ++
          Enum.slice(lines, start_idx, end_idx - start_idx + 1)
      end)

    [
      "== File: #{relative_path(source.path)} (lines=#{total_lines}) ==",
      "== Header ==",
      Enum.join(header_lines, "\n"),
      "== Selected Sections ==",
      Enum.join(selected, "\n")
    ]
    |> Enum.join("\n")
  end

  defp find_context_ranges(lines, patterns, before, after_lines) do
    last_idx = length(lines) - 1

    ranges =
      lines
      |> Enum.with_index()
      |> Enum.filter(fn {line, _idx} ->
        Enum.any?(patterns, &Regex.match?(&1, line))
      end)
      |> Enum.map(fn {_line, idx} ->
        {max(0, idx - before), min(last_idx, idx + after_lines)}
      end)

    merge_ranges(ranges)
  end

  defp merge_ranges(ranges) do
    ranges
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce([], fn {start_idx, end_idx}, acc ->
      case acc do
        [] ->
          [{start_idx, end_idx}]

        [{prev_start, prev_end} | rest] when start_idx <= prev_end + 1 ->
          [{prev_start, max(prev_end, end_idx)} | rest]

        _ ->
          [{start_idx, end_idx} | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp print_file_stats(stats) do
    print_section("File Stats")
    print_kv("Path", stats.path)
    print_kv("Files", stats.files)
    print_kv("Bytes", stats.bytes)
    print_kv("Lines", stats.lines)
    print_kv("Modules", stats.modules)
    print_kv("Functions", stats.functions)
    print_kv("Context mode", stats.context_mode)
    print_kv("Context chars", stats.context_chars)
  end

  defp build_rlm_session(opts) do
    pool = pool_atom(opts.pool)
    session_id = unique_session("dspy_api")
    ensure_session(session_id)
    {inputs, outputs} = signature_fields(opts.signature)
    input_fields = Enum.map(inputs, &String.to_atom/1)
    output_field = List.first(outputs) || "output"

    {:ok, lm} =
      Dspy.LM.new(
        opts.model,
        [],
        with_runtime([temperature: opts.temperature], pool, session_id)
      )

    {:ok, _} = Dspy.configure(with_runtime([lm: lm], pool, session_id))

    {:ok, rlm} =
      RLM.new(
        opts.signature,
        opts.max_iterations,
        opts.max_llm_calls,
        opts.max_output_chars,
        opts.rlm_verbose,
        [],
        nil,
        nil,
        with_runtime([], pool, session_id)
      )

    %{
      label: "rlm",
      session_id: session_id,
      pool: pool,
      rlm: rlm,
      lm: lm,
      input_fields: input_fields,
      output_field: output_field
    }
  end

  defp run_query(session, context, query) do
    input_opts = build_input_opts(session.input_fields, context, query)
    opts = with_runtime(input_opts, session.pool, session.session_id)

    case RLM.forward(session.rlm, opts) do
      {:ok, result} ->
        runtime_opts = runtime(session.pool, session.session_id)
        {:ok, answer} = SnakeBridge.attr(result, session.output_field, __runtime__: runtime_opts)
        {:ok, to_string(answer)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp print_prompt_history(label, session, opts) do
    runtime_opts = runtime(session.pool, session.session_id)
    IO.puts("  History: #{label}")

    case fetch_prompt_history(session, runtime_opts, trace_history_limit(opts)) do
      {:ok, []} ->
        IO.puts("    (no history)")

      {:ok, history} ->
        Enum.with_index(history, 1)
        |> Enum.each(fn {entry, idx} ->
          print_history_entry(idx, entry, runtime_opts, trace_prompt_limit(opts))
          IO.puts("")
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

  defp print_history_entry(idx, entry, runtime_opts, prompt_limit) when is_map(entry) do
    model = entry["model"] || "unknown"
    cost = format_cost(entry["cost"])
    usage = format_usage(entry["usage"])

    IO.puts("    [#{idx}] model=#{model} cost=#{cost} #{usage}")

    if prompt = entry["prompt"] do
      {prompt_str, prompt_meta} = format_prompt_block(prompt, runtime_opts, prompt_limit)
      print_trace_block("prompt", prompt_str, prompt_limit, prompt_meta)
    end

    if response = entry["response"] do
      {response_str, response_meta} = format_response_block(response, runtime_opts, prompt_limit)
      print_trace_block("response", response_str, prompt_limit, response_meta)
    end

    meta =
      entry
      |> Map.drop(["model", "cost", "usage", "prompt", "response"])
      |> sanitize_meta(prompt_limit)

    if map_size(meta) > 0 do
      meta_lines = format_meta_lines(meta)
      print_trace_block("meta", meta_lines, min(prompt_limit, 800))
    end
  end

  defp print_history_entry(idx, _entry, _runtime_opts, _prompt_limit) do
    IO.puts("    [#{idx}] (invalid entry)")
  end

  defp render_history_value(value, runtime_opts, limit) do
    cond do
      is_binary(value) ->
        value

      SnakeBridge.ref?(value) ->
        render_ref_value(value, runtime_opts)

      true ->
        inspect(value, limit: 20, printable_limit: limit)
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

  defp print_trace_block(label, text, limit, meta \\ %{}) do
    {snippet, truncated?} = maybe_truncate(text, limit)
    header = if truncated?, do: "#{label} (truncated)", else: label
    header = append_meta(header, meta)
    print_block(color_trace_label(label, header), snippet, limit, 6, 8, raw: true)
  end

  defp color_trace_label("prompt", label), do: ansi(:yellow, label)
  defp color_trace_label("response", label), do: ansi(:green, label)
  defp color_trace_label("meta", label), do: ansi(:magenta, label)
  defp color_trace_label(_label, label), do: label

  defp maybe_truncate(text, limit) when is_integer(limit) and limit > 0 do
    length = String.length(text)

    if length > limit do
      marker = "\n... <#{length - limit} chars truncated> ...\n"
      marker_len = String.length(marker)
      keep = max(limit - marker_len, 0)
      head_len = max(div(keep * 2, 3), 0)
      tail_len = max(keep - head_len, 0)
      head = String.slice(text, 0, head_len)
      tail = if tail_len > 0, do: String.slice(text, length - tail_len, tail_len), else: ""
      {head <> marker <> tail, true}
    else
      {text, false}
    end
  end

  defp maybe_truncate(text, _limit), do: {text, false}

  defp maybe_truncate_inline(text, limit) when is_integer(limit) and limit > 0 do
    length = String.length(text)

    if length > limit do
      marker = " ... <#{length - limit} chars truncated> ... "
      marker_len = String.length(marker)
      keep = max(limit - marker_len, 0)
      head_len = max(div(keep * 2, 3), 0)
      tail_len = max(keep - head_len, 0)
      head = String.slice(text, 0, head_len)
      tail = if tail_len > 0, do: String.slice(text, length - tail_len, tail_len), else: ""
      {head <> marker <> tail, true}
    else
      {text, false}
    end
  end

  defp maybe_truncate_inline(text, _limit), do: {text, false}

  defp format_cost(nil), do: "$0.00"

  defp format_cost(cost) when is_number(cost),
    do: "$#{:erlang.float_to_binary(cost * 1.0, decimals: 4)}"

  defp format_cost(_), do: "$?.??"

  defp format_usage(nil), do: "tokens=?"
  defp format_usage(%{"total_tokens" => total}), do: "tokens=#{total}"
  defp format_usage(%{"prompt_tokens" => p, "completion_tokens" => c}), do: "tokens=#{p}+#{c}"
  defp format_usage(_), do: "tokens=?"

  defp sanitize_meta(meta, limit) do
    meta
    |> Enum.map(fn {key, value} ->
      {key, summarize_value(value, limit)}
    end)
    |> Enum.into(%{})
  end

  defp summarize_value(value, limit) do
    cond do
      is_binary(value) ->
        {snippet, truncated?} = maybe_truncate(value, min(limit, 600))
        if truncated?, do: snippet <> " (len=#{String.length(value)})", else: snippet

      is_list(value) ->
        "list(len=#{length(value)})"

      is_map(value) ->
        "map(size=#{map_size(value)})"

      SnakeBridge.ref?(value) ->
        "<#{value.type_name}> (ref)"

      true ->
        inspect(value, limit: 5, printable_limit: min(limit, 200))
    end
  end

  defp print_trace_settings(opts) do
    history = format_limit(trace_history_limit(opts))
    prompt = format_limit(trace_prompt_limit(opts))

    print_kv("History limit", history)
    print_kv("Prompt chars", prompt)
    print_kv("RLM verbose", opts.rlm_verbose)
  end

  defp format_limit(:all), do: "all"
  defp format_limit(limit) when is_integer(limit), do: Integer.to_string(limit)

  defp trace_history_limit(opts) do
    cond do
      opts.trace_limit == 0 -> :all
      opts.trace_limit < 0 -> :all
      opts.trace_limit > 0 -> opts.trace_limit
      true -> @default_trace_limit
    end
  end

  defp trace_prompt_limit(opts) do
    cond do
      opts.trace_prompt_chars == 0 -> :all
      opts.trace_prompt_chars < 0 -> :all
      opts.trace_prompt_chars > 0 -> min(opts.trace_prompt_chars, @hard_trace_prompt_chars)
      true -> min(@default_trace_prompt_chars, @hard_trace_prompt_chars)
    end
  end

  defp result_limit(opts) do
    cond do
      opts.result_chars == 0 ->
        :all

      opts.result_chars < 0 ->
        :all

      opts.result_chars > 0 ->
        min(opts.result_chars, @hard_result_chars)

      true ->
        min(@default_result_chars, @hard_result_chars)
    end
  end

  defp print_result(answer, opts, session) do
    normalized = normalize_result_output(answer, session)
    print_kv("Chars", String.length(normalized))
    truncated? = print_block("Output", normalized, result_limit(opts), 2, 4)
    print_kv("Truncated", if(truncated?, do: "yes", else: "no"))
  end

  defp normalize_result_output(answer, session) do
    trimmed = String.trim(answer || "")

    cond do
      trimmed == "" ->
        answer

      String.length(trimmed) > 200_000 ->
        answer

      String.starts_with?(trimmed, "{") or String.starts_with?(trimmed, "[") ->
        runtime_opts = runtime(session.pool, session.session_id)

        case parse_literal(trimmed, runtime_opts) do
          {:ok, value} -> format_parsed_result(value)
          _ -> answer
        end

      true ->
        answer
    end
  end

  defp parse_literal(text, runtime_opts) do
    SnakeBridge.call("ast", "literal_eval", [text], __runtime__: runtime_opts)
  rescue
    _ -> {:error, :parse_failed}
  end

  defp format_parsed_result(%{} = map) do
    entries = Enum.sort_by(map, fn {k, _} -> to_string(k) end)

    case entries do
      [{title, %{} = body}] ->
        header = to_string(title)
        lines = [header, String.duplicate("-", min(String.length(header), 72))]
        Enum.join(lines ++ format_kv_lines(body, 0), "\n")

      _ ->
        Enum.join(format_kv_lines(map, 0), "\n")
    end
  end

  defp format_parsed_result(value) when is_list(value) do
    Enum.map_join(value, "\n", fn v -> "- " <> format_value_inline(v) end)
  end

  defp format_parsed_result(value), do: format_value_inline(value)

  defp format_kv_lines(map, indent) do
    prefix = String.duplicate(" ", indent)

    map
    |> Enum.sort_by(fn {k, _} -> to_string(k) end)
    |> Enum.flat_map(fn {key, value} ->
      label = "#{prefix}- #{key}:"

      cond do
        is_map(value) and map_size(value) > 0 ->
          [label | format_kv_lines(value, indent + 2)]

        is_list(value) and value != [] ->
          [label | Enum.map(value, fn item -> "#{prefix}  - #{format_value_inline(item)}" end)]

        true ->
          ["#{label} #{format_value_inline(value)}"]
      end
    end)
  end

  defp format_value_inline(value) do
    cond do
      is_binary(value) -> value
      is_number(value) -> to_string(value)
      is_atom(value) -> Atom.to_string(value)
      true -> inspect(value, limit: 10, printable_limit: 200)
    end
  end

  defp print_session_workers(title, sessions) do
    IO.puts("")
    IO.puts("  #{title} workers:")

    Enum.each(sessions, fn session ->
      case SessionStore.get_session(session.session_id) do
        {:ok, %{last_worker_id: worker_id}} when is_binary(worker_id) ->
          print_kv(session.label, worker_id, indent: 4, key_width: 10)

        _ ->
          print_kv(session.label, "(not assigned)", indent: 4, key_width: 10)
      end
    end)
  end

  defp preview(text, limit) do
    trimmed = text |> String.replace(~r/\s+/, " ") |> String.trim()
    {snippet, _truncated?} = maybe_truncate_inline(trimmed, limit)
    snippet
  end

  defp signature_fields(signature) do
    case String.split(signature, "->", parts: 2) do
      [left, right] ->
        inputs = split_signature_fields(left)
        outputs = split_signature_fields(right)

        {
          if(inputs == [], do: ["context", "query"], else: inputs),
          if(outputs == [], do: ["output"], else: outputs)
        }

      _ ->
        {["context", "query"], ["output"]}
    end
  end

  defp split_signature_fields(segment) do
    segment
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp build_input_opts(input_fields, context, query) do
    use_combined? = length(input_fields) < 2

    Enum.with_index(input_fields)
    |> Enum.map(fn {field, idx} ->
      value =
        cond do
          idx == 0 and use_combined? ->
            context <> "\n\n" <> query

          idx == 0 ->
            context

          idx == 1 ->
            query

          true ->
            ""
        end

      {field, value}
    end)
  end

  defp configure_snakepit!(opts) do
    pool_name = pool_atom(opts.pool)
    pools = [%{name: pool_name, pool_size: opts.pool_size, affinity: :strict_queue}]

    ConfigHelper.snakepit_config(pools: pools)
    |> Enum.each(fn {key, value} ->
      Application.put_env(:snakepit, key, value)
    end)
  end

  defp pool_atom(pool) do
    pool
    |> to_string()
    |> String.trim()
    |> case do
      "" -> String.to_atom(@default_pool)
      name -> String.to_atom(name)
    end
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
    IO.puts("Deno not found; RLM requires the PythonInterpreter runtime.")
    IO.puts("Install via asdf:")
    IO.puts("  asdf plugin add deno https://github.com/asdf-community/asdf-deno.git")
    IO.puts("  asdf install")
    IO.puts("Or install directly:")
    IO.puts("  curl -fsSL https://deno.land/install.sh | sh")
    IO.puts("  export PATH=\"$HOME/.deno/bin:$PATH\"")
  end

  defp print_help do
    IO.puts("""
    Usage:
      mix run --no-start examples/introspect/dspy_api_introspect.exs [options]

    Options:
      --preset api|predict|rlm|history   Choose a default prompt (api is default)
      --prompt TEXT                     Override the prompt/query
      --query TEXT                      Alias for --prompt
      --signature TEXT                  Override the RLM signature
      --file PATH                       Wrapper file or directory to introspect
      --model MODEL                     LM model id
      --temperature FLOAT               LM temperature (default #{@default_temperature})
      --max-iterations N                RLM max iterations (default #{@default_max_iterations})
      --max-llm-calls N                  RLM max LLM calls (default #{@default_max_llm_calls})
      --max-output-chars N              RLM max output chars (default #{@default_max_output_chars})
      --pool NAME                       Pool name (default #{@default_pool})
      --pool-size N                     Pool size (default #{@default_pool_size})
      --full-context / --no-full-context
                                       Use full wrapper context (default: full)
      --trace / --no-trace              Show LM history (default: on)
      --trace-limit N                   Limit history entries (default #{@default_trace_limit})
      --trace-prompt-chars N            Truncate prompt/response text (0 disables; default #{@default_trace_prompt_chars})
      --result-chars N                  Truncate final result text (0 disables; default #{@default_result_chars})
      --rlm-verbose / --no-rlm-verbose  Show RLM reasoning loop (default: on)
      --rules / --no-rules              Append default prompt rules (default: on for presets)
      --facts / --no-facts              Append extracted FACTS (default: on for presets)
      --help                            Show this help

    Signature mapping:
      - First input field receives the wrapper context (all files).
      - Second input field receives the prompt/query.
      - First output field is read as the answer.

    Common scenarios:
      mix run --no-start examples/introspect/dspy_api_introspect.exs
      mix run --no-start examples/introspect/dspy_api_introspect.exs --prompt "Summarize RLM + signatures"
      mix run --no-start examples/introspect/dspy_api_introspect.exs --facts --prompt "Map core entry points with line numbers"
      mix run --no-start examples/introspect/dspy_api_introspect.exs --trace-limit 10 --trace-prompt-chars 1200
      mix run --no-start examples/introspect/dspy_api_introspect.exs --result-chars 0 --trace-prompt-chars 0
    """)
  end

  defp print_section(title) do
    IO.puts("")
    IO.puts(ansi(:cyan, "==> #{title}"))
  end

  defp print_kv(label, value, opts \\ []) do
    indent = Keyword.get(opts, :indent, 2)
    key_width = Keyword.get(opts, :key_width, 12)
    key_width = max(key_width, String.length("#{label}:"))
    key = String.pad_trailing("#{label}:", key_width)
    IO.puts("#{String.duplicate(" ", indent)}#{key} #{value}")
  end

  defp print_block(label, text, limit, indent, line_indent, opts \\ []) do
    raw = Keyword.get(opts, :raw, false)
    {snippet, truncated?} = if raw, do: {text, false}, else: maybe_truncate(text, limit)

    IO.puts("#{String.duplicate(" ", indent)}#{label}:")

    snippet
    |> String.split("\n")
    |> Enum.each(fn line ->
      IO.puts("#{String.duplicate(" ", line_indent)}#{line}")
    end)

    truncated?
  end

  defp append_meta(label, meta) when map_size(meta) == 0, do: label

  defp append_meta(label, meta) do
    meta_str = Enum.map_join(meta, ", ", fn {key, value} -> "#{key}=#{value}" end)
    "#{label} [#{meta_str}]"
  end

  defp format_prompt_block(prompt, runtime_opts, limit) do
    cond do
      is_list(prompt) and Enum.all?(prompt, &is_map/1) ->
        messages =
          Enum.map(prompt, fn msg ->
            format_message_line(msg, min(limit, 600))
          end)

        {Enum.join(messages, "\n"), %{"messages" => length(messages)}}

      is_binary(prompt) ->
        {prompt, %{"chars" => String.length(prompt)}}

      SnakeBridge.ref?(prompt) ->
        {render_ref_value(prompt, runtime_opts), %{"type" => prompt.type_name}}

      true ->
        {render_history_value(prompt, runtime_opts, limit), %{}}
    end
  end

  defp format_message_line(msg, limit) do
    role =
      Map.get(msg, "role") ||
        Map.get(msg, :role) ||
        "unknown"

    content =
      Map.get(msg, "content") ||
        Map.get(msg, :content) ||
        Map.get(msg, "text") ||
        Map.get(msg, :text) ||
        inspect(msg, limit: 3)

    normalized =
      content
      |> to_string()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    {snippet, _truncated?} = maybe_truncate_inline(normalized, limit)
    "#{role}: #{snippet}"
  end

  defp format_response_block(response, runtime_opts, limit) do
    cond do
      SnakeBridge.ref?(response) ->
        case summarize_response(response, runtime_opts) do
          {:ok, summary} when is_map(summary) ->
            format_response_summary(summary, limit)

          _ ->
            {render_ref_value(response, runtime_opts), %{"type" => response.type_name}}
        end

      is_binary(response) ->
        case extract_response_from_string(response) do
          {:ok, content, meta} ->
            meta = Map.put(meta, "chars", String.length(content))
            {content, meta}

          :error ->
            {response, %{"chars" => String.length(response)}}
        end

      true ->
        {render_history_value(response, runtime_opts, limit), %{}}
    end
  end

  defp format_response_summary(summary, limit) do
    content =
      summary["content"] ||
        summary["repr"] ||
        inspect(summary, limit: 5, printable_limit: min(limit, 200))

    content_str = to_string(content)

    meta =
      %{}
      |> maybe_put_meta("type", summary["type"])
      |> maybe_put_meta("model", summary["model"])
      |> maybe_put_meta("finish", summary["finish_reason"])
      |> maybe_put_meta("chars", String.length(content_str))

    {content_str, meta}
  end

  defp extract_response_from_string(response) do
    case extract_message_content(response) do
      {:ok, content} ->
        meta =
          %{}
          |> maybe_put_meta("type", "ModelResponse")
          |> maybe_put_meta("model", extract_attr(response, "model"))
          |> maybe_put_meta("finish", extract_attr(response, "finish_reason"))

        {:ok, content, meta}

      _ ->
        :error
    end
  end

  defp extract_message_content(response) do
    regexes = [
      ~r/Message\(content='(?<content>(?:\\.|[^'\\])*)'/s,
      ~r/Message\(content="(?<content>(?:\\.|[^"\\])*)"/s,
      ~r/"content"\s*:\s*"(?<content>(?:\\.|[^"\\])*)"/s
    ]

    Enum.reduce_while(regexes, :error, fn regex, _acc ->
      case Regex.named_captures(regex, response) do
        %{"content" => content} -> {:halt, {:ok, content}}
        _ -> {:cont, :error}
      end
    end)
  end

  defp extract_attr(response, attr) do
    regex = ~r/#{attr}='(?<value>[^']+)'/

    case Regex.named_captures(regex, response) do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp summarize_response(ref, runtime_opts) do
    code = """
    def _summarize_response(resp):
        out = {}
        try:
            out["type"] = type(resp).__name__
        except Exception:
            out["type"] = "unknown"

        for attr in ("model", "id", "object"):
            val = getattr(resp, attr, None)
            if val is not None:
                out[attr] = val

        choices = getattr(resp, "choices", None)
        if choices:
            try:
                first = choices[0]
            except Exception:
                first = None

            if first is not None:
                finish = getattr(first, "finish_reason", None)
                if finish is not None:
                    out["finish_reason"] = finish

                msg = getattr(first, "message", None)
                content = None
                if msg is not None:
                    content = getattr(msg, "content", None)

                if content is None:
                    content = getattr(first, "text", None)

                if content is not None:
                    out["content"] = content

        if "content" not in out:
            out["repr"] = repr(resp)

        return out
    """

    globals = %{"_code" => code, "_resp" => ref}
    expr = "(lambda _ns: (exec(_code, _ns, _ns), _ns['_summarize_response'](_resp))[1])({})"

    SnakeBridge.call("builtins", "eval", [expr, globals], __runtime__: runtime_opts)
  rescue
    _ -> {:error, :summary_failed}
  end

  defp maybe_put_meta(meta, _key, nil), do: meta
  defp maybe_put_meta(meta, _key, ""), do: meta
  defp maybe_put_meta(meta, key, value), do: Map.put(meta, key, value)

  defp format_meta_lines(meta) do
    Enum.map_join(meta, "\n", fn {key, value} -> "#{key}: #{value}" end)
  end

  defp ansi(color, text) do
    if IO.ANSI.enabled?() do
      IO.ANSI.format([color, :bright, text, :reset]) |> IO.iodata_to_binary()
    else
      text
    end
  end
end

DSPex.DspyApiIntrospect.run()
