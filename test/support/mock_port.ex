defmodule DSPex.Test.MockPort do
  @moduledoc """
  Mock implementation of Erlang ports for testing Python bridge communication.

  This module simulates the behavior of actual Python processes without
  requiring real port spawning, enabling fast and deterministic tests.
  """

  use GenServer

  @packet_header_size 4

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def expect_command(port, command, response) do
    GenServer.call(port, {:expect, command, response})
  end

  def expect_sequence(port, expectations) do
    GenServer.call(port, {:expect_sequence, expectations})
  end

  def simulate_timeout(port) do
    GenServer.call(port, :simulate_timeout)
  end

  def simulate_crash(port) do
    GenServer.call(port, :simulate_crash)
  end

  def simulate_slow_response(port, delay_ms) do
    GenServer.call(port, {:simulate_slow_response, delay_ms})
  end

  def get_history(port) do
    GenServer.call(port, :get_history)
  end

  def healthy do
    {:ok, port} = start_link()
    expect_command(port, "ping", %{"status" => "ok", "timestamp" => System.system_time()})
    port
  end

  def unhealthy do
    {:ok, port} = start_link()
    simulate_timeout(port)
    port
  end

  # Port protocol implementation

  def port_send(port, data) when is_pid(port) do
    GenServer.cast(port, {:port_send, data})
  end

  def command(port, data) when is_pid(port) do
    GenServer.call(port, {:command, data})
  end

  def close(port) when is_pid(port) do
    if Process.alive?(port) do
      ref = Process.monitor(port)
      GenServer.stop(port, :normal, 1000)
      receive do
        {:DOWN, ^ref, :process, ^port, _} -> :ok
      after 100 -> :ok
      end
    end
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    state = %{
      expectations: %{},
      sequence: [],
      history: [],
      mode: :normal,
      slow_delay: 0,
      owner: Keyword.get(opts, :owner, self()),
      buffer: <<>>
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:expect, command, response}, _from, state) do
    expectations = Map.put(state.expectations, command, response)
    {:reply, :ok, %{state | expectations: expectations}}
  end

  @impl true
  def handle_call({:expect_sequence, sequence}, _from, state) do
    {:reply, :ok, %{state | sequence: sequence}}
  end

  @impl true
  def handle_call(:simulate_timeout, _from, state) do
    {:reply, :ok, %{state | mode: :timeout}}
  end

  @impl true
  def handle_call(:simulate_crash, _from, state) do
    {:reply, :ok, %{state | mode: :crash}}
  end

  @impl true
  def handle_call({:simulate_slow_response, delay}, _from, state) do
    {:reply, :ok, %{state | mode: :slow, slow_delay: delay}}
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, Enum.reverse(state.history), state}
  end

  @impl true
  def handle_call({:command, data}, _from, state) do
    # Simulate port command behavior
    handle_cast({:port_send, data}, state)
    # Port commands don't have return values
    {:reply, true, state}
  end

  @impl true
  def handle_cast({:port_send, data}, state) do
    # Record the sent data
    state = %{state | history: [{:sent, data} | state.history]}

    # Parse the command from the data
    case decode_packet(state.buffer <> data) do
      {:ok, payload, rest} ->
        state = %{state | buffer: rest}

        case Jason.decode(payload) do
          {:ok, %{"command" => command} = message} ->
            handle_command(command, message, state)

          {:error, _} ->
            send_error("Invalid JSON", state)
        end

      {:partial, _} ->
        # Need more data
        {:noreply, %{state | buffer: state.buffer <> data}}

      {:error, reason} ->
        send_error(reason, state)
    end
  end

  # Private functions

  defp handle_command(command, message, state) do
    state = %{state | history: [{:command, command, message} | state.history]}

    case state.mode do
      :timeout ->
        # Don't respond
        {:noreply, state}

      :crash ->
        # Simulate port crash
        {:stop, :port_crashed, state}

      :slow ->
        # Delay response
        Process.sleep(state.slow_delay)
        send_response(command, message, state)

      :normal ->
        send_response(command, message, state)
    end
  end

  defp send_response(command, message, state) do
    response = get_response(command, message, state)

    encoded =
      Jason.encode!(%{
        "id" => Map.get(message, "id"),
        "result" => response,
        "error" => nil
      })

    packet = encode_packet(encoded)
    Kernel.send(state.owner, {self(), {:data, packet}})

    state = %{state | history: [{:response, response} | state.history]}
    {:noreply, state}
  end

  defp send_error(error, state) do
    encoded =
      Jason.encode!(%{
        "id" => nil,
        "result" => nil,
        "error" => error
      })

    packet = encode_packet(encoded)
    Kernel.send(state.owner, {self(), {:data, packet}})

    {:noreply, state}
  end

  defp get_response(command, message, state) do
    cond do
      # Check sequence expectations first
      length(state.sequence) > 0 ->
        [{expected_cmd, response} | rest] = state.sequence

        if expected_cmd == command do
          # Consume this expectation
          Process.put(:sequence, rest)
          response
        else
          %{"error" => "Unexpected command: #{command}, expected: #{expected_cmd}"}
        end

      # Check command expectations
      Map.has_key?(state.expectations, command) ->
        state.expectations[command]

      # Default responses for common commands
      true ->
        default_response(command, message)
    end
  end

  defp default_response("ping", _message) do
    %{"status" => "ok", "timestamp" => System.system_time()}
  end

  defp default_response("create_program", message) do
    %{
      "program_id" => "mock_program_#{System.unique_integer([:positive])}",
      "config" => Map.get(message, "args", %{})
    }
  end

  defp default_response("execute_program", message) do
    %{
      "outputs" => %{
        "result" => "Mock result for program #{message["args"]["program_id"]}"
      }
    }
  end

  defp default_response("list_programs", _message) do
    %{"programs" => []}
  end

  defp default_response("cleanup_session", _message) do
    %{"status" => "cleaned"}
  end

  defp default_response(_command, _message) do
    %{"status" => "unknown_command"}
  end

  defp encode_packet(data) when is_binary(data) do
    size = byte_size(data)
    <<size::unsigned-big-integer-size(32), data::binary>>
  end

  defp decode_packet(<<size::unsigned-big-integer-size(32), data::binary>>) do
    if byte_size(data) >= size do
      <<payload::binary-size(size), rest::binary>> = data
      {:ok, payload, rest}
    else
      {:partial, size - byte_size(data)}
    end
  end

  defp decode_packet(data) when byte_size(data) < @packet_header_size do
    {:partial, @packet_header_size - byte_size(data)}
  end

  defp decode_packet(_) do
    {:error, "Invalid packet format"}
  end
end
