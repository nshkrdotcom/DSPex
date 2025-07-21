defmodule ElixirML.Process.SchemaRegistry do
  @moduledoc """
  High-performance registry for schema validation and caching.
  Uses ETS tables for fast lookup and LRU eviction.
  """

  use GenServer

  @default_max_size 10_000
  # 1 hour in milliseconds
  @default_ttl 3_600_000

  defstruct [
    :table,
    :max_size,
    :current_size,
    :access_order,
    :ttl
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    table_name = Keyword.get(opts, :table_name, :schema_cache)
    max_size = Keyword.get(opts, :max_size, @default_max_size)
    ttl = Keyword.get(opts, :ttl, @default_ttl)

    :ets.new(table_name, [:named_table, :public, :set])

    state = %__MODULE__{
      table: table_name,
      max_size: max_size,
      current_size: 0,
      access_order: :queue.new(),
      ttl: ttl
    }

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_expired, ttl)

    {:ok, state}
  end

  @doc """
  Get cached validation result for a schema and data hash.
  """
  def get_cached_validation(schema_module, data_hash, table_name \\ :schema_cache) do
    case :ets.lookup(table_name, {schema_module, data_hash}) do
      [{_, result, timestamp}] ->
        if not expired?(timestamp) do
          GenServer.cast(__MODULE__, {:access, schema_module, data_hash})
          {:hit, result}
        else
          GenServer.cast(__MODULE__, {:remove, schema_module, data_hash})
          :miss
        end

      [] ->
        :miss
    end
  end

  @doc """
  Cache a validation result.
  """
  def cache_validation_result(schema_module, data_hash, result, table_name \\ :schema_cache) do
    if table_name == :schema_cache do
      GenServer.cast(__MODULE__, {:cache, schema_module, data_hash, result})
    else
      # Direct ETS insertion for test tables
      timestamp = System.monotonic_time(:millisecond)
      :ets.insert(table_name, {{schema_module, data_hash}, result, timestamp})
    end
  end

  @doc """
  Clear all cached results.
  """
  def clear_cache do
    GenServer.call(__MODULE__, :clear_cache)
  end

  @doc """
  Get cache statistics.
  """
  def cache_stats do
    GenServer.call(__MODULE__, :cache_stats)
  end

  # Server callbacks

  def handle_cast({:access, schema_module, data_hash}, state) do
    # Update access order for LRU
    key = {schema_module, data_hash}
    new_access_order = :queue.in(key, state.access_order)

    {:noreply, %{state | access_order: new_access_order}}
  end

  def handle_cast({:cache, schema_module, data_hash, result}, state) do
    key = {schema_module, data_hash}
    timestamp = System.monotonic_time(:millisecond)

    # Check if we need to evict
    state =
      if state.current_size >= state.max_size do
        evict_lru(state)
      else
        state
      end

    # Insert new entry
    :ets.insert(state.table, {key, result, timestamp})

    new_state = %{
      state
      | current_size: state.current_size + 1,
        access_order: :queue.in(key, state.access_order)
    }

    {:noreply, new_state}
  end

  def handle_cast({:remove, schema_module, data_hash}, state) do
    key = {schema_module, data_hash}
    :ets.delete(state.table, key)

    new_state = %{state | current_size: max(0, state.current_size - 1)}

    {:noreply, new_state}
  end

  def handle_call(:clear_cache, _from, state) do
    :ets.delete_all_objects(state.table)

    new_state = %{state | current_size: 0, access_order: :queue.new()}

    {:reply, :ok, new_state}
  end

  def handle_call(:cache_stats, _from, state) do
    total_memory = :ets.info(state.table, :memory) * :erlang.system_info(:wordsize)

    stats = %{
      current_size: state.current_size,
      max_size: state.max_size,
      memory_bytes: total_memory,
      hit_rate: calculate_hit_rate(state.table),
      oldest_entry_age: get_oldest_entry_age(state.table)
    }

    {:reply, stats, state}
  end

  def handle_info(:cleanup_expired, state) do
    # Remove expired entries
    now = System.monotonic_time(:millisecond)

    expired_keys =
      :ets.select(state.table, [
        {{{:"$1", :"$2"}, :"$3", :"$4"}, [{:<, {:+, :"$4", state.ttl}, now}], [{{:"$1", :"$2"}}]}
      ])

    Enum.each(expired_keys, fn key ->
      :ets.delete(state.table, key)
    end)

    new_state = %{state | current_size: max(0, state.current_size - length(expired_keys))}

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_expired, state.ttl)

    {:noreply, new_state}
  end

  # Private functions

  defp expired?(timestamp) do
    now = System.monotonic_time(:millisecond)
    now - timestamp > @default_ttl
  end

  defp evict_lru(state) do
    case :queue.out(state.access_order) do
      {{:value, key}, new_queue} ->
        :ets.delete(state.table, key)
        %{state | access_order: new_queue, current_size: state.current_size - 1}

      {:empty, _} ->
        state
    end
  end

  defp calculate_hit_rate(table) do
    # This is a simplified implementation
    # In practice, you'd want to track hits/misses
    case :ets.info(table, :size) do
      0 -> 0.0
      size -> min(1.0, size / 1000.0)
    end
  end

  defp get_oldest_entry_age(table) do
    now = System.monotonic_time(:millisecond)

    case :ets.select(table, [{{:"$1", :"$2", :"$3"}, [], [:"$3"]}]) do
      [] ->
        0

      timestamps ->
        oldest = Enum.min(timestamps)
        now - oldest
    end
  end
end
