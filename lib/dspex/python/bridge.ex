defmodule DSPex.Python.Bridge do
  @moduledoc """
  Bridge between DSPex operations and Snakepit Python pools.

  Handles request/response protocol, error handling, and streaming support.
  """

  require Logger

  @default_timeout 30_000

  @doc """
  Execute a Python operation through Snakepit.
  """
  @spec execute(atom(), String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def execute(_pool_name, operation, args, opts \\ []) do
    # Snakepit manages its own pool, so we ignore pool_name for now
    request = build_request(operation, args, opts)

    if opts[:stream] do
      stream_execute(request, opts)
    else
      sync_execute(request, opts)
    end
  end

  @doc """
  Execute with a specific session for stateful operations.
  """
  @spec execute_in_session(String.t(), atom(), String.t(), map(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def execute_in_session(session_id, _pool_name, operation, args, opts \\ []) do
    # Use Snakepit's session support
    Snakepit.execute_in_session(session_id, operation, args, opts)
  end

  # Private functions

  defp build_request(operation, args, opts) do
    %{
      id: generate_request_id(),
      operation: operation,
      args: prepare_args(args),
      opts: prepare_opts(opts),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp generate_request_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp prepare_args(args) do
    # Convert Elixir data structures to Python-friendly format
    args
    |> maybe_convert_signature()
    |> maybe_convert_atoms_to_strings()
  end

  defp maybe_convert_signature(%{signature: %DSPex.Native.Signature{} = sig} = args) do
    # Convert native signature to Python format
    Map.put(args, :signature, serialize_signature(sig))
  end

  defp maybe_convert_signature(args), do: args

  defp serialize_signature(signature) do
    %{
      inputs: Enum.map(signature.inputs, &serialize_field/1),
      outputs: Enum.map(signature.outputs, &serialize_field/1),
      docstring: signature.docstring
    }
  end

  defp serialize_field(field) do
    %{
      name: to_string(field.name),
      type: serialize_type(field.type),
      description: field.description
    }
  end

  defp serialize_type(:string), do: "str"
  defp serialize_type(:integer), do: "int"
  defp serialize_type(:float), do: "float"
  defp serialize_type(:boolean), do: "bool"
  defp serialize_type({:list, inner}), do: "list[#{serialize_type(inner)}]"
  defp serialize_type({:dict, inner}), do: "dict[str, #{serialize_type(inner)}]"
  defp serialize_type({:optional, inner}), do: "optional[#{serialize_type(inner)}]"
  defp serialize_type(other), do: to_string(other)

  defp maybe_convert_atoms_to_strings(data) when is_map(data) do
    Map.new(data, fn {k, v} ->
      {to_string(k), maybe_convert_atoms_to_strings(v)}
    end)
  end

  defp maybe_convert_atoms_to_strings(data) when is_list(data) do
    Enum.map(data, &maybe_convert_atoms_to_strings/1)
  end

  defp maybe_convert_atoms_to_strings(data) when is_atom(data) and not is_boolean(data) do
    to_string(data)
  end

  defp maybe_convert_atoms_to_strings(data), do: data

  defp prepare_opts(opts) do
    opts
    |> Keyword.take([:temperature, :max_tokens, :model, :top_p, :stop])
    |> Map.new()
  end

  defp sync_execute(request, opts) do
    timeout = opts[:timeout] || @default_timeout

    start_time = System.monotonic_time(:millisecond)

    try do
      # Use Snakepit.execute
      case Snakepit.execute(request.operation, request.args, timeout: timeout) do
        {:ok, response} ->
          duration = System.monotonic_time(:millisecond) - start_time

          :telemetry.execute(
            [:dspex, :python, :execute],
            %{duration: duration},
            %{operation: request.operation}
          )

          handle_response(response)

        {:error, reason} ->
          duration = System.monotonic_time(:millisecond) - start_time

          :telemetry.execute(
            [:dspex, :python, :error],
            %{duration: duration},
            %{operation: request.operation, error: reason}
          )

          handle_error(reason)
      end
    catch
      kind, reason ->
        Logger.error("Python bridge error: #{kind} #{inspect(reason)}")
        {:error, {kind, reason}}
    end
  end

  defp stream_execute(_request, _opts) do
    # Streaming not yet implemented in Snakepit
    # For now, return an error
    {:error, :streaming_not_implemented}
  end

  defp handle_response(%{"success" => true, "result" => result}) do
    {:ok, convert_response(result)}
  end

  defp handle_response(%{"success" => false, "error" => error}) do
    {:error, error}
  end

  defp handle_response(%{"status" => "ok", "result" => result}) do
    {:ok, convert_response(result)}
  end

  defp handle_response(%{"status" => "error"} = response) do
    {:error, response}
  end

  defp handle_response(response) do
    Logger.warning("Unexpected response format: #{inspect(response)}")
    {:ok, response}
  end

  defp convert_response(result) when is_map(result) do
    # Convert string keys to atoms for common fields
    result
    |> Map.new(fn {k, v} ->
      key =
        if k in ["answer", "confidence", "reasoning", "output"],
          do: String.to_atom(k),
          else: k

      {key, v}
    end)
  end

  defp convert_response(result), do: result

  defp handle_error(:timeout), do: {:error, :timeout}
  defp handle_error({:worker_error, reason}), do: {:error, {:python_error, reason}}
  defp handle_error(reason), do: {:error, reason}
end
