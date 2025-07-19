defmodule ElixirML.Process.DatasetManager do
  @moduledoc """
  Manager for training datasets and evaluation data.
  Handles data loading, preprocessing, and caching for ML workflows.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    state = %{
      datasets: %{},
      cache: %{},
      preprocessing_pipelines: %{},
      stats: %{loads: 0, cache_hits: 0, cache_misses: 0}
    }

    {:ok, state}
  end

  @doc """
  Register a dataset for use in ML workflows.
  """
  def register_dataset(dataset_id, dataset_spec) do
    GenServer.call(__MODULE__, {:register_dataset, dataset_id, dataset_spec})
  end

  @doc """
  Load a dataset with optional preprocessing.
  """
  def load_dataset(dataset_id, opts \\ []) do
    GenServer.call(__MODULE__, {:load_dataset, dataset_id, opts})
  end

  @doc """
  Cache processed dataset for future use.
  """
  def cache_dataset(cache_key, processed_data) do
    GenServer.cast(__MODULE__, {:cache_dataset, cache_key, processed_data})
  end

  @doc """
  Register a preprocessing pipeline.
  """
  def register_preprocessing_pipeline(pipeline_id, pipeline_function) do
    GenServer.call(__MODULE__, {:register_pipeline, pipeline_id, pipeline_function})
  end

  @doc """
  Get dataset manager statistics.
  """
  def dataset_stats do
    GenServer.call(__MODULE__, :dataset_stats)
  end

  # Server callbacks

  def handle_call({:register_dataset, dataset_id, dataset_spec}, _from, state) do
    dataset_info = %{
      spec: dataset_spec,
      registered_at: System.monotonic_time(:millisecond),
      load_count: 0
    }

    datasets = Map.put(state.datasets, dataset_id, dataset_info)

    {:reply, {:ok, dataset_id}, %{state | datasets: datasets}}
  end

  def handle_call({:load_dataset, dataset_id, opts}, _from, state) do
    case Map.get(state.datasets, dataset_id) do
      nil ->
        {:reply, {:error, :dataset_not_found}, state}

      dataset_info ->
        # Check cache first
        cache_key = generate_cache_key(dataset_id, opts)

        case Map.get(state.cache, cache_key) do
          nil ->
            # Cache miss - load and process dataset
            case load_and_process_dataset(dataset_info.spec, opts) do
              {:ok, processed_data} ->
                # Update cache and stats
                cache = Map.put(state.cache, cache_key, processed_data)

                datasets =
                  put_in(state.datasets[dataset_id].load_count, dataset_info.load_count + 1)

                stats = %{
                  state.stats
                  | loads: state.stats.loads + 1,
                    cache_misses: state.stats.cache_misses + 1
                }

                new_state = %{state | cache: cache, datasets: datasets, stats: stats}
                {:reply, {:ok, processed_data}, new_state}

              {:error, _} = error ->
                {:reply, error, state}
            end

          cached_data ->
            # Cache hit
            stats = %{state.stats | cache_hits: state.stats.cache_hits + 1}
            {:reply, {:ok, cached_data}, %{state | stats: stats}}
        end
    end
  end

  def handle_call({:register_pipeline, pipeline_id, pipeline_function}, _from, state) do
    pipelines = Map.put(state.preprocessing_pipelines, pipeline_id, pipeline_function)

    {:reply, {:ok, pipeline_id}, %{state | preprocessing_pipelines: pipelines}}
  end

  def handle_call(:dataset_stats, _from, state) do
    stats = %{
      registered_datasets: map_size(state.datasets),
      cached_datasets: map_size(state.cache),
      preprocessing_pipelines: map_size(state.preprocessing_pipelines),
      load_stats: state.stats,
      cache_hit_rate: calculate_cache_hit_rate(state.stats),
      memory_usage: estimate_memory_usage(state.cache)
    }

    {:reply, stats, state}
  end

  def handle_cast({:cache_dataset, cache_key, processed_data}, state) do
    cache = Map.put(state.cache, cache_key, processed_data)
    {:noreply, %{state | cache: cache}}
  end

  # Private functions

  defp load_and_process_dataset(dataset_spec, opts) do
    try do
      # Mock dataset loading - in practice this would load from files, databases, etc.
      raw_data =
        case dataset_spec do
          %{type: :file, path: path} ->
            load_from_file(path)

          %{type: :generator, size: size} ->
            generate_mock_data(size)

          %{type: :memory, data: data} ->
            data

          _ ->
            {:error, :unsupported_dataset_type}
        end

      case raw_data do
        {:error, _} = error ->
          error

        data ->
          # Apply preprocessing if specified
          preprocessing_pipeline = Keyword.get(opts, :preprocessing)

          processed_data =
            case preprocessing_pipeline do
              nil ->
                data

              pipeline_id when is_atom(pipeline_id) ->
                # Look up registered pipeline
                # For now, just return data as-is
                data

              pipeline_function when is_function(pipeline_function) ->
                pipeline_function.(data)
            end

          {:ok, processed_data}
      end
    rescue
      error -> {:error, error}
    end
  end

  defp load_from_file(path) do
    # Mock file loading
    if File.exists?(path) do
      case Path.extname(path) do
        ".json" ->
          case File.read(path) do
            {:ok, content} -> Jason.decode(content)
            error -> error
          end

        ".csv" ->
          # Mock CSV parsing
          {:ok, [%{id: 1, text: "sample", label: "positive"}]}

        _ ->
          {:error, :unsupported_file_format}
      end
    else
      {:error, :file_not_found}
    end
  end

  defp generate_mock_data(size) do
    data =
      Enum.map(1..size, fn i ->
        %{
          id: i,
          text: "Sample text #{i}",
          label: Enum.random(["positive", "negative", "neutral"]),
          score: :rand.uniform()
        }
      end)

    {:ok, data}
  end

  defp generate_cache_key(dataset_id, opts) do
    # Create a cache key based on dataset ID and options
    opts_hash = :crypto.hash(:md5, :erlang.term_to_binary(opts)) |> Base.encode16(case: :lower)
    "#{dataset_id}_#{opts_hash}"
  end

  defp calculate_cache_hit_rate(stats) do
    total_requests = stats.cache_hits + stats.cache_misses

    if total_requests > 0 do
      stats.cache_hits / total_requests
    else
      0.0
    end
  end

  defp estimate_memory_usage(cache) do
    # Rough estimate of cache memory usage
    cache
    |> Enum.map(fn {_key, data} ->
      :erlang.external_size(data)
    end)
    |> Enum.sum()
  end
end
