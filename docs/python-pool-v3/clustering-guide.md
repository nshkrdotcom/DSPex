# Python Pool V3 Clustering Guide

## Overview

The V3 pool design provides a clear path to distributed operation through its Registry-based architecture. This guide shows how to evolve from single-node to multi-node deployment.

## Single Node → Multi Node Evolution

### Phase 1: Current Single-Node Design

```elixir
# Registry for local process lookup
Registry.start_link(keys: :unique, name: DSPex.Python.Registry)

# Workers registered locally
{:via, Registry, {DSPex.Python.Registry, worker_id}}
```

### Phase 2: Cluster-Aware Design

```elixir
# Switch to Horde for distributed registry
defmodule DSPex.Python.DistributedRegistry do
  use Horde.Registry
  
  def start_link(_) do
    Horde.Registry.start_link(
      name: __MODULE__,
      keys: :unique,
      members: :auto,
      distribution_strategy: Horde.UniformDistribution
    )
  end
  
  def via_tuple(worker_id) do
    {:via, Horde.Registry, {__MODULE__, worker_id}}
  end
end

# Switch to Horde.DynamicSupervisor
defmodule DSPex.Python.DistributedSupervisor do
  use Horde.DynamicSupervisor
  
  def start_link(_) do
    Horde.DynamicSupervisor.start_link(
      name: __MODULE__,
      strategy: :one_for_one,
      distribution_strategy: Horde.UniformDistribution,
      members: :auto
    )
  end
end
```

## Distributed Pool Architecture

### Node Types

1. **Python Nodes**: Run Python workers
   - High CPU/memory
   - GPU optional
   - Scale horizontally

2. **Router Nodes**: Handle client requests
   - Low resource usage
   - High network I/O
   - Load balance requests

3. **Coordinator Node**: Manages cluster state
   - Runs pool manager
   - Tracks worker availability
   - Single point of coordination

### Deployment Topology

```
        Load Balancer
             |
      _______________
     |       |       |
  Router1 Router2 Router3    (Request routing)
     |_______|_______|
             |
       Coordinator          (Pool management)
     ________|________
    |        |        |
 Python1  Python2  Python3   (Worker nodes)
```

## Implementation Steps

### Step 1: Cluster Formation

```elixir
defmodule DSPex.Cluster do
  def join(node) do
    Node.connect(node)
    
    # Sync Horde members
    Horde.Cluster.set_members(
      DSPex.Python.DistributedRegistry,
      [DSPex.Python.DistributedRegistry]
    )
    
    Horde.Cluster.set_members(
      DSPex.Python.DistributedSupervisor,
      [DSPex.Python.DistributedSupervisor]
    )
  end
end
```

### Step 2: Distributed Pool Manager

```elixir
defmodule DSPex.Python.DistributedPool do
  use GenServer
  
  defstruct [:nodes, :workers_per_node, :worker_registry]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: {:global, __MODULE__})
  end
  
  def init(opts) do
    # Start workers on all Python nodes
    python_nodes = discover_python_nodes()
    workers_per_node = opts[:workers_per_node] || 8
    
    all_workers = for node <- python_nodes do
      start_workers_on_node(node, workers_per_node)
    end |> List.flatten()
    
    {:ok, %__MODULE__{
      nodes: python_nodes,
      workers_per_node: workers_per_node,
      worker_registry: build_worker_registry(all_workers)
    }}
  end
  
  defp start_workers_on_node(node, count) do
    :rpc.call(node, __MODULE__, :start_local_workers, [count])
  end
  
  def start_local_workers(count) do
    1..count
    |> Task.async_stream(fn i ->
      worker_id = "#{node()}_worker_#{i}"
      DSPex.Python.DistributedSupervisor.start_child(
        {DSPex.Python.Worker, id: worker_id}
      )
      worker_id
    end, max_concurrency: count)
    |> Enum.map(fn {:ok, id} -> id end)
  end
end
```

### Step 3: Location-Aware Request Routing

```elixir
defmodule DSPex.Python.Router do
  @doc """
  Route requests with node affinity for better performance
  """
  def execute(command, args, opts \\ []) do
    preferred_node = opts[:node] || select_best_node()
    
    case find_worker_on_node(preferred_node) do
      {:ok, worker_id} ->
        execute_on_worker(worker_id, command, args)
      {:error, :no_workers} ->
        # Fallback to any available worker
        execute_on_any_worker(command, args)
    end
  end
  
  defp select_best_node do
    # Strategy 1: Round-robin
    nodes = Node.list()
    Enum.random(nodes)
    
    # Strategy 2: Least loaded (requires metrics)
    # find_least_loaded_node()
    
    # Strategy 3: Geographically closest
    # find_closest_node()
  end
  
  defp find_worker_on_node(node) do
    case Horde.Registry.select(DSPex.Python.DistributedRegistry, [
      {{:"$1", {:"$2", :"$3"}, :"$4"}, 
       [{:==, :"$2", node}], 
       [:"$1"]}
    ]) do
      [] -> {:error, :no_workers}
      workers -> {:ok, Enum.random(workers)}
    end
  end
end
```

### Step 4: Distributed Session Store

```elixir
defmodule DSPex.DistributedSessionStore do
  @moduledoc """
  Replicated session store using CRDT for eventual consistency
  """
  
  def start_link(opts) do
    DeltaCrdt.start_link(
      __MODULE__,
      DeltaCrdt.AWLWWMap,
      sync_interval: 100,
      max_sync_size: :infinite,
      neighbours: neighbours()
    )
  end
  
  def store_session(session_id, session_data) do
    DeltaCrdt.put(__MODULE__, session_id, session_data)
  end
  
  def get_session(session_id) do
    case DeltaCrdt.get(__MODULE__, session_id) do
      nil -> {:error, :not_found}
      data -> {:ok, data}
    end
  end
  
  defp neighbours do
    Node.list()
    |> Enum.map(&{__MODULE__, &1})
  end
end
```

## Deployment Configurations

### Docker Compose Example

```yaml
version: '3.8'

services:
  coordinator:
    image: dspex:latest
    environment:
      - NODE_TYPE=coordinator
      - RELEASE_NODE=coordinator@dspex
      - RELEASE_COOKIE=secret_cookie
    command: ["mix", "run", "--no-halt"]
    
  router:
    image: dspex:latest
    deploy:
      replicas: 3
    environment:
      - NODE_TYPE=router
      - COORDINATOR_NODE=coordinator@dspex
      - RELEASE_COOKIE=secret_cookie
    depends_on:
      - coordinator
      
  python_worker:
    image: dspex:latest
    deploy:
      replicas: 5
    environment:
      - NODE_TYPE=python
      - COORDINATOR_NODE=coordinator@dspex
      - RELEASE_COOKIE=secret_cookie
      - WORKERS_PER_NODE=8
    depends_on:
      - coordinator
```

### Kubernetes Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dspex-python-workers
spec:
  replicas: 10
  selector:
    matchLabels:
      app: dspex-python
  template:
    metadata:
      labels:
        app: dspex-python
        node-type: python
    spec:
      containers:
      - name: dspex
        image: dspex:latest
        env:
        - name: NODE_TYPE
          value: "python"
        - name: WORKERS_PER_NODE
          value: "8"
        - name: RELEASE_COOKIE
          valueFrom:
            secretKeyRef:
              name: dspex-secrets
              key: cookie
        resources:
          requests:
            memory: "4Gi"
            cpu: "2"
          limits:
            memory: "8Gi"
            cpu: "4"
---
apiVersion: v1
kind: Service
metadata:
  name: dspex-discovery
spec:
  clusterIP: None
  selector:
    app: dspex
  ports:
  - name: epmd
    port: 4369
  - name: erlang
    port: 9000
```

## Monitoring Distributed Pool

### Cluster Health

```elixir
defmodule DSPex.ClusterMonitor do
  use GenServer
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  
  def init(_) do
    :timer.send_interval(5_000, :check_health)
    {:ok, %{}}
  end
  
  def handle_info(:check_health, state) do
    health = %{
      nodes: check_nodes(),
      workers: check_workers(),
      registry: check_registry(),
      memory: check_memory()
    }
    
    :telemetry.execute(
      [:dspex, :cluster, :health],
      health,
      %{timestamp: System.system_time(:second)}
    )
    
    {:noreply, health}
  end
  
  defp check_nodes do
    all_nodes = [node() | Node.list()]
    
    Enum.map(all_nodes, fn node ->
      {node, node_health(node)}
    end)
  end
  
  defp check_workers do
    workers = Horde.Registry.select(
      DSPex.Python.DistributedRegistry,
      [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}]
    )
    
    %{
      total: length(workers),
      by_node: Enum.group_by(workers, &node(elem(&1, 1)))
    }
  end
end
```

### Distributed Metrics

```elixir
# Aggregate metrics from all nodes
defmodule DSPex.DistributedMetrics do
  def gather_pool_metrics do
    Node.list()
    |> Task.async_stream(fn node ->
      :rpc.call(node, DSPex.LocalMetrics, :get_metrics, [])
    end)
    |> Enum.reduce(%{}, &merge_metrics/2)
  end
  
  defp merge_metrics({:ok, node_metrics}, acc) do
    Map.merge(acc, node_metrics, fn _k, v1, v2 ->
      cond do
        is_number(v1) -> v1 + v2
        is_list(v1) -> v1 ++ v2
        true -> v2
      end
    end)
  end
end
```

## Best Practices

### 1. Node Specialization

```elixir
# config/runtime.exs
config :dspex, :node_type,
  case System.get_env("NODE_TYPE") do
    "router" -> :router
    "python" -> :python_worker
    "coordinator" -> :coordinator
    _ -> :all_in_one
  end

# Only start relevant processes based on node type
```

### 2. Network Partitions

```elixir
defmodule DSPex.PartitionHandler do
  use GenServer
  
  def handle_info({:nodedown, node}, state) do
    Logger.warn("Node #{node} went down")
    
    # Mark workers on that node as unavailable
    mark_node_workers_unavailable(node)
    
    # Potentially start replacement workers
    maybe_start_replacement_workers(node)
    
    {:noreply, state}
  end
end
```

### 3. Load Balancing

```elixir
defmodule DSPex.LoadBalancer do
  @strategies [:round_robin, :least_loaded, :random, :sticky]
  
  def select_worker(strategy \\ :least_loaded) do
    case strategy do
      :round_robin -> round_robin_select()
      :least_loaded -> least_loaded_select()
      :random -> random_select()
      :sticky -> sticky_select(caller_node())
    end
  end
  
  defp least_loaded_select do
    # Query worker load from distributed metrics
    metrics = DSPex.DistributedMetrics.get_worker_loads()
    
    {worker_id, _load} = Enum.min_by(metrics, fn {_id, load} -> load end)
    worker_id
  end
end
```

### 4. Rolling Deployments

```elixir
defmodule DSPex.RollingDeploy do
  def deploy_new_version(new_image) do
    nodes = get_python_nodes()
    
    Enum.each(nodes, fn node ->
      # Drain node
      drain_node(node)
      
      # Wait for requests to complete
      wait_for_drain(node)
      
      # Update and restart
      update_node(node, new_image)
      
      # Health check
      wait_for_healthy(node)
      
      # Re-enable
      enable_node(node)
    end)
  end
end
```

## Performance Considerations

### Network Overhead

- Local worker calls: ~0.1ms
- Remote worker calls: ~1-5ms (same datacenter)
- Cross-region calls: ~50-200ms

### Optimization Strategies

1. **Node Affinity**: Keep requests on same node when possible
2. **Batch Operations**: Reduce network round trips
3. **Connection Pooling**: Reuse Erlang distribution connections
4. **Data Locality**: Cache frequently used data on each node

### Benchmarks

```elixir
defmodule DistributedBenchmark do
  def compare_local_vs_remote do
    Benchee.run(%{
      "local worker" => fn ->
        execute_on_local_worker(:ping, %{})
      end,
      "remote worker (same DC)" => fn ->
        execute_on_remote_worker(:ping, %{}, :same_dc)
      end,
      "remote worker (cross region)" => fn ->
        execute_on_remote_worker(:ping, %{}, :cross_region)
      end
    })
  end
end

# Results:
# local worker: 0.1ms avg
# remote worker (same DC): 1.2ms avg  
# remote worker (cross region): 65ms avg
```

## Troubleshooting

### Common Issues

1. **Workers not registering globally**
   - Check Horde cluster membership
   - Verify network connectivity
   - Check EPMD ports (4369)

2. **High latency**
   - Check network topology
   - Consider node affinity
   - Monitor Erlang distribution buffers

3. **Uneven load distribution**
   - Review distribution strategy
   - Check worker health
   - Monitor per-node metrics

### Debug Tools

```elixir
# Check cluster status
:net_adm.world()

# Verify Horde membership  
Horde.Cluster.members(DSPex.Python.DistributedRegistry)

# List all workers across cluster
DSPex.DistributedPool.list_all_workers()

# Test cross-node communication
:rpc.call(:"python1@host", DSPex.Python.Worker, :ping, [])
```