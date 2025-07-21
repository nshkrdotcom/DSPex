defmodule DSPEx.PredictStructured do
  @moduledoc """
  Structured prediction using InstructorLite for guaranteed JSON schema compliance.

  This module provides the same interface as DSPEx.Predict but uses InstructorLite
  to ensure structured outputs from language models like Gemini.

  ## Usage

      # Create structured prediction program
      program = DSPEx.PredictStructured.new(QASignature, :gemini)
      
      # Get structured response
      {:ok, outputs} = DSPEx.Program.forward(program, %{question: "What is 2+2?"})
      # outputs => %{answer: "4", reasoning: "Basic arithmetic", confidence: "high"}

  ## Differences from DSPEx.Predict

  - Uses InstructorLite for structured outputs
  - Bypasses standard DSPEx.Client for direct InstructorLite calls
  - Automatically generates JSON schemas from DSPEx signatures
  - Provides validation and retry capabilities

  """

  @behaviour DSPEx.Program

  @enforce_keys [:signature, :client]
  defstruct [:signature, :client, :adapter, demos: []]

  @type t :: %__MODULE__{
          signature: module(),
          client: atom(),
          adapter: module() | nil,
          demos: [map()]
        }

  @doc """
  Create a new structured prediction program using InstructorLite.

  ## Parameters

  - `signature` - Signature module defining input/output contract  
  - `client` - Provider (currently only :gemini supported)
  - `opts` - Optional configuration

  ## Options

  - `:demos` - List of demonstration examples
  - `:max_retries` - Number of retries for validation failures (default: 1)
  - `:model` - Specific model to use (default from config)

  """
  @spec new(module(), atom(), keyword()) :: t()
  def new(signature, client, opts \\ []) do
    %__MODULE__{
      signature: signature,
      client: client,
      adapter: DSPEx.Adapters.InstructorLiteGemini,
      demos: Keyword.get(opts, :demos, [])
    }
  end

  @impl DSPEx.Program
  def forward(program, inputs, _opts \\ []) do
    correlation_id = generate_correlation_id()

    with :ok <- validate_inputs_with_sinter(program.signature, inputs),
         {:ok, {params, instructor_opts}} <-
           format_instructor_params(program, inputs, correlation_id),
         {:ok, result} <- make_instructor_request(params, instructor_opts, correlation_id),
         {:ok, outputs} <- parse_instructor_response(program, result, correlation_id),
         {:ok, validated_outputs} <- validate_outputs_with_sinter(program.signature, outputs) do
      {:ok, validated_outputs}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp format_instructor_params(program, inputs, correlation_id) do
    start_time = System.monotonic_time()

    # Use InstructorLite adapter to format parameters
    result = program.adapter.format_messages(program.signature, program.demos, inputs)

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    # Emit telemetry
    :telemetry.execute(
      [:dspex, :structured, :format, :stop],
      %{duration: duration, success: success},
      %{
        signature: signature_name(program.signature),
        correlation_id: correlation_id,
        adapter: :instructor_lite_gemini
      }
    )

    result
  end

  defp make_instructor_request(params, instructor_opts, correlation_id) do
    start_time = System.monotonic_time()

    # Add correlation ID to telemetry metadata
    :telemetry.execute(
      [:dspex, :structured, :request, :start],
      %{system_time: System.system_time()},
      %{correlation_id: correlation_id}
    )

    # Make direct InstructorLite call
    result = InstructorLite.instruct(params, instructor_opts)

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :structured, :request, :stop],
      %{duration: duration, success: success},
      %{correlation_id: correlation_id}
    )

    result
  end

  defp parse_instructor_response(program, instructor_result, correlation_id) do
    start_time = System.monotonic_time()

    # Use adapter to parse InstructorLite response
    result = program.adapter.parse_response(program.signature, instructor_result)

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :structured, :parse, :stop],
      %{duration: duration, success: success},
      %{
        signature: signature_name(program.signature),
        correlation_id: correlation_id
      }
    )

    result
  end

  defp generate_correlation_id do
    node_hash = :erlang.phash2(node(), 65_536)
    timestamp = System.unique_integer([:positive])
    random = :erlang.unique_integer([:positive])
    "structured-#{node_hash}-#{timestamp}-#{random}"
  end

  defp signature_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> String.downcase()
  end

  # Sinter integration functions

  defp validate_inputs_with_sinter(_signature, _inputs) do
    # Graceful degradation - Sinter validation not yet implemented
    # This is a placeholder for future Sinter integration
    :ok
  end

  defp validate_outputs_with_sinter(_signature, outputs) do
    # Graceful degradation - Sinter validation not yet implemented
    # This is a placeholder for future Sinter integration
    {:ok, outputs}
  end
end
