defmodule DSPex do
  @moduledoc """
  DSPex - DSPy for Elixir via SnakeBridge.

  Minimal wrapper that provides transparent access to DSPy through SnakeBridge's
  Universal FFI. No code generation needed - just call Python directly.

  ## Quick Start

      DSPex.run(fn ->
        # Configure LM
        lm = DSPex.lm!("gemini/gemini-flash-lite-latest")
        DSPex.configure!(lm: lm)

        # Create predictor and run
        predict = DSPex.call!("dspy", "Predict", ["question -> answer"])
        result = DSPex.method!(predict, "forward", [], question: "What is 2+2?")

        # Get the answer
        answer = DSPex.attr!(result, "answer")
        IO.puts("Answer: \#{answer}")
      end)

  ## Timeout Configuration

  DSPex leverages SnakeBridge 0.7.7+'s timeout architecture for LLM workloads.
  By default, all DSPy calls use the `:ml_inference` profile (10 minute timeout).

  ### Timeout Profiles

  | Profile         | Timeout  | Use Case                              |
  |-----------------|----------|---------------------------------------|
  | `:default`      | 2 min    | Standard Python calls                 |
  | `:streaming`    | 30 min   | Streaming responses                   |
  | `:ml_inference` | 10 min   | LLM inference (DSPex default)         |
  | `:batch_job`    | 1 hour   | Long-running batch operations         |

  ### Per-Call Timeout Override

  Override timeout for individual calls using `__runtime__` option:

      # Use a different profile
      DSPex.method!(predict, "forward", [],
        question: "Complex question",
        __runtime__: [timeout_profile: :batch_job]
      )

      # Set exact timeout in milliseconds
      DSPex.method!(predict, "forward", [],
        question: "Quick question",
        __runtime__: [timeout: 30_000]  # 30 seconds
      )

  ### Global Configuration

  Configure timeouts in `config/config.exs`:

      config :snakebridge,
        runtime: [
          library_profiles: %{"dspy" => :ml_inference},
          # Or set global default:
          # timeout_profile: :ml_inference
        ]

  ## Architecture

  DSPex uses SnakeBridge's Universal FFI to call DSPy directly:

      Elixir (DSPex.call/4)
          ↓
      SnakeBridge.call/4
          ↓
      Snakepit gRPC
          ↓
      Python DSPy
          ↓
      LLM Providers

  All Python lifecycle is managed automatically by Snakepit.
  """

  @doc """
  Run DSPex code with automatic Python lifecycle management.

  Wraps your code in `Snakepit.run_as_script/2` which:
  - Starts the Python process pool
  - Runs your code
  - Cleans up on exit

  Pass `halt: true` in opts if you need to force the BEAM to exit
  (for example, when running inside wrapper scripts).

  DSPex restarts Snakepit by default so it owns the runtime and can close
  persistent resources (like DETS) cleanly. Pass `restart: false` to reuse an
  already-started Snakepit instance.

  ## Example

      DSPex.run(fn ->
        lm = DSPex.lm!("gemini/gemini-flash-lite-latest")
        DSPex.configure!(lm: lm)
        # ... your DSPy code
      end)
  """
  def run(fun, opts \\ []) when is_function(fun, 0) do
    opts = Keyword.put_new(opts, :restart, true)

    Snakepit.run_as_script(
      fn ->
        ensure_snakebridge_started!()
        fun.()
      end,
      opts
    )
  end

  defp ensure_snakebridge_started! do
    case Application.ensure_all_started(:snakebridge) do
      {:ok, _started} ->
        :ok

      {:error, {:snakebridge, reason}} ->
        raise "Failed to start snakebridge: #{inspect(reason)}"

      {:error, reason} ->
        raise "Failed to start snakebridge: #{inspect(reason)}"
    end
  end

  # ---------------------------------------------------------------------------
  # DSPy-specific helpers
  # ---------------------------------------------------------------------------

  @doc """
  Create a DSPy language model.

  ## Examples

      {:ok, lm} = DSPex.lm("gemini/gemini-flash-lite-latest")
      {:ok, lm} = DSPex.lm("anthropic/claude-3-sonnet-20240229", temperature: 0.7)
  """
  def lm(model, opts \\ []) do
    SnakeBridge.call("dspy", "LM", [model], opts)
  end

  @doc "Bang version of lm/2 - raises on error."
  def lm!(model, opts \\ []) do
    SnakeBridge.call!("dspy", "LM", [model], opts)
  end

  @doc """
  Configure DSPy global settings.

  ## Examples

      :ok = DSPex.configure(lm: lm)
      :ok = DSPex.configure(lm: lm, rm: retriever)
  """
  def configure(opts \\ []) do
    case SnakeBridge.call("dspy", "configure", [], opts) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc "Bang version of configure/1 - raises on error."
  def configure!(opts \\ []) do
    SnakeBridge.call!("dspy", "configure", [], opts)
    :ok
  end

  @doc """
  Create a Predict module.

  ## Examples

      {:ok, predict} = DSPex.predict("question -> answer")
      {:ok, predict} = DSPex.predict("context, question -> answer")
  """
  def predict(signature, opts \\ []) do
    SnakeBridge.call("dspy", "Predict", [signature], opts)
  end

  @doc "Bang version of predict/2."
  def predict!(signature, opts \\ []) do
    SnakeBridge.call!("dspy", "Predict", [signature], opts)
  end

  @doc """
  Create a ChainOfThought module.

  ## Examples

      {:ok, cot} = DSPex.chain_of_thought("question -> answer")
  """
  def chain_of_thought(signature, opts \\ []) do
    SnakeBridge.call("dspy", "ChainOfThought", [signature], opts)
  end

  @doc "Bang version of chain_of_thought/2."
  def chain_of_thought!(signature, opts \\ []) do
    SnakeBridge.call!("dspy", "ChainOfThought", [signature], opts)
  end

  # ---------------------------------------------------------------------------
  # Timeout helpers
  # ---------------------------------------------------------------------------

  @doc """
  Add timeout configuration to options.

  This is a convenience helper for adding `__runtime__` timeout options.

  ## Options

    * `:timeout` - Exact timeout in milliseconds
    * `:timeout_profile` - Use a predefined profile (`:default`, `:streaming`, `:ml_inference`, `:batch_job`)

  ## Examples

      # Set exact timeout
      opts = DSPex.with_timeout([], timeout: 60_000)  # 1 minute
      DSPex.method!(predict, "forward", [], Keyword.merge(opts, question: "..."))

      # Use batch profile for long operations
      opts = DSPex.with_timeout([question: "complex"], timeout_profile: :batch_job)
      DSPex.method!(predict, "forward", [], opts)

      # Inline usage
      DSPex.method!(predict, "forward", [],
        DSPex.with_timeout([question: "test"], timeout: 30_000)
      )
  """
  def with_timeout(opts, timeout_opts) when is_list(opts) and is_list(timeout_opts) do
    runtime = Keyword.get(opts, :__runtime__, [])
    new_runtime = Keyword.merge(runtime, timeout_opts)
    Keyword.put(opts, :__runtime__, new_runtime)
  end

  @doc """
  Timeout profile atoms for use with `__runtime__` option.

  Returns a keyword list ready to merge into call options.

  ## Examples

      DSPex.method!(predict, "forward", [],
        Keyword.merge([question: "test"], DSPex.timeout_profile(:batch_job))
      )
  """
  def timeout_profile(profile)
      when profile in [:default, :streaming, :ml_inference, :batch_job] do
    [__runtime__: [timeout_profile: profile]]
  end

  @doc """
  Create a timeout option for exact milliseconds.

  Returns a keyword list ready to merge into call options.

  ## Examples

      DSPex.method!(predict, "forward", [],
        Keyword.merge([question: "test"], DSPex.timeout_ms(120_000))
      )
  """
  def timeout_ms(milliseconds) when is_integer(milliseconds) and milliseconds > 0 do
    [__runtime__: [timeout: milliseconds]]
  end

  # ---------------------------------------------------------------------------
  # Universal FFI pass-through (convenience re-exports)
  # ---------------------------------------------------------------------------

  @doc """
  Call any DSPy function or class.

  ## Examples

      {:ok, result} = DSPex.call("dspy", "Predict", ["question -> answer"])
      {:ok, result} = DSPex.call("dspy.teleprompt", "BootstrapFewShot", [], metric: metric)
  """
  defdelegate call(module, function, args \\ [], opts \\ []), to: SnakeBridge

  @doc "Bang version - raises on error, returns value directly."
  defdelegate call!(module, function, args \\ [], opts \\ []), to: SnakeBridge

  @doc "Get a module attribute."
  defdelegate get(module, attr), to: SnakeBridge

  @doc "Bang version of get/2."
  defdelegate get!(module, attr), to: SnakeBridge

  @doc "Call a method on a Python object reference."
  defdelegate method(ref, method, args \\ [], opts \\ []), to: SnakeBridge

  @doc "Bang version of method/4."
  defdelegate method!(ref, method, args \\ [], opts \\ []), to: SnakeBridge

  @doc "Get an attribute from a Python object reference."
  defdelegate attr(ref, attribute, opts \\ []), to: SnakeBridge

  @doc "Bang version of attr/3."
  defdelegate attr!(ref, attribute, opts \\ []), to: SnakeBridge

  @doc "Set an attribute on a Python object reference."
  defdelegate set_attr(ref, attribute, value, opts \\ []), to: SnakeBridge

  @doc "Check if a value is a Python object reference."
  defdelegate ref?(value), to: SnakeBridge

  @doc "Encode binary data as Python bytes."
  defdelegate bytes(data), to: SnakeBridge
end
