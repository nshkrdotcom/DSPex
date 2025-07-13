# Stage 2 Prompt 4: Program Execution Engine

## OBJECTIVE

Implement a comprehensive program execution engine that orchestrates complex ML workflows through dependency-aware module coordination, parallel execution optimization, comprehensive error handling, and performance monitoring. This engine must provide advanced execution strategies, resource management, and fault tolerance while maintaining compatibility with DSPy program patterns and delivering superior performance through native Elixir concurrency.

## COMPLETE IMPLEMENTATION CONTEXT

### PROGRAM EXECUTION ARCHITECTURE OVERVIEW

From Stage 2 Technical Specification:

```
┌─────────────────────────────────────────────────────────────┐
│                Program Execution Engine                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Execution       │  │ Dependency      │  │ Resource     ││
│  │ Orchestration   │  │ Resolution      │  │ Management   ││
│  │ - Task Graph    │  │ - DAG Analysis  │  │ - Allocation ││
│  │ - Parallelism   │  │ - Scheduling    │  │ - Cleanup    ││
│  │ - Coordination  │  │ - Optimization  │  │ - Monitoring ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Error Handling  │  │ Performance     │  │ State        ││
│  │ - Recovery      │  │ Monitoring      │  │ Management   ││
│  │ - Isolation     │  │ - Metrics       │  │ - Persistence││
│  │ - Compensation  │  │ - Optimization  │  │ - Recovery   ││
│  │ - Rollback      │  │ - Bottlenecks   │  │ - Snapshots  ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### DSPy PROGRAM EXECUTION ANALYSIS

From comprehensive DSPy source code analysis (primitives/program.py):

**DSPy Program Core Patterns:**

```python
# DSPy Program base class with execution coordination
class Program(Module):
    def __init__(self):
        super().__init__()
        self._modules = {}
        self._execution_graph = {}
        self._compiled = False
        
    def add_module(self, name, module):
        """Add a module to the program."""
        self._modules[name] = module
        
    def forward(self, **kwargs):
        """Execute the program forward pass."""
        # Execute modules in dependency order
        results = {}
        for module_name in self._get_execution_order():
            module = self._modules[module_name]
            module_inputs = self._prepare_inputs(module_name, kwargs, results)
            module_output = module(**module_inputs)
            results[module_name] = module_output
            
        return self._aggregate_results(results)
    
    def _get_execution_order(self):
        """Get topologically sorted execution order."""
        return topological_sort(self._execution_graph)
    
    def _prepare_inputs(self, module_name, initial_inputs, results):
        """Prepare inputs for a specific module."""
        module_inputs = {}
        dependencies = self._execution_graph.get(module_name, [])
        
        for dep in dependencies:
            if dep in results:
                module_inputs.update(results[dep])
            elif dep in initial_inputs:
                module_inputs[dep] = initial_inputs[dep]
                
        return module_inputs
    
    def compile(self, optimizer=None):
        """Compile the program for optimization."""
        self._compiled = True
        self._optimization_state = {}
        
        # Optimize execution graph
        self._execution_graph = optimize_execution_graph(self._execution_graph)
        
        # Compile individual modules
        for module in self._modules.values():
            if hasattr(module, 'compile'):
                module.compile(optimizer)

# Example DSPy program implementation
class RAGProgram(Program):
    def __init__(self, retriever, generator):
        super().__init__()
        self.add_module("retriever", retriever)
        self.add_module("generator", generator)
        
        # Define dependencies
        self._execution_graph = {
            "retriever": [],  # No dependencies
            "generator": ["retriever"]  # Depends on retriever
        }
    
    def forward(self, question):
        # Retrieve relevant documents
        docs = self.retriever(question=question)
        
        # Generate answer using retrieved docs
        answer = self.generator(question=question, context=docs.context)
        
        return answer
```

**Key DSPy Program Features:**
1. **Module Orchestration** - Coordinated execution of multiple modules
2. **Dependency Management** - DAG-based dependency resolution and execution ordering
3. **Result Aggregation** - Combining outputs from multiple modules
4. **Compilation Support** - Program-level optimization and compilation
5. **State Management** - Maintaining execution state and intermediate results

### ADVANCED EXECUTION PATTERNS

From Elixir/OTP concurrency and coordination patterns:

**Task Coordination Patterns:**

```elixir
# Advanced task coordination with supervision
defmodule TaskCoordinator do
  use GenServer
  
  def coordinate_tasks(tasks, strategy \\ :parallel) do
    case strategy do
      :parallel -> execute_parallel(tasks)
      :sequential -> execute_sequential(tasks)
      :pipeline -> execute_pipeline(tasks)
      :dag -> execute_dag(tasks)
    end
  end
  
  defp execute_parallel(tasks) do
    tasks
    |> Enum.map(&Task.async/1)
    |> Task.await_many(30_000)
  end
  
  defp execute_dag(tasks) do
    # Topological sort and dependency-aware execution
    execution_order = topological_sort(build_dependency_graph(tasks))
    execute_in_order(execution_order, tasks)
  end
end

# Supervision patterns for fault tolerance
defmodule ExecutionSupervisor do
  use Supervisor
  
  def start_link(execution_config) do
    Supervisor.start_link(__MODULE__, execution_config)
  end
  
  def init(execution_config) do
    children = [
      # Execution coordinator
      {ExecutionCoordinator, execution_config},
      
      # Resource manager
      {ResourceManager, []},
      
      # Task supervisor for individual executions
      {Task.Supervisor, name: ExecutionTaskSupervisor}
    ]
    
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
```

### COMPREHENSIVE PROGRAM EXECUTION ENGINE

**Core Execution Engine with Advanced Orchestration:**

```elixir
defmodule DSPex.Program.ExecutionEngine do
  @moduledoc """
  Comprehensive program execution engine with advanced orchestration capabilities.
  """
  
  use GenServer
  
  alias DSPex.Module.Registry
  alias DSPex.Program.{DependencyGraph, ResourceManager, ExecutionContext}
  alias DSPex.Telemetry.Tracker
  
  defstruct [
    :program_id,
    :execution_graph,
    :modules,
    :execution_strategy,
    :resource_limits,
    :performance_targets,
    :error_handling_config,
    :current_executions,
    :execution_history,
    :optimization_state
  ]
  
  def start_link([program_id, config]) do
    GenServer.start_link(__MODULE__, [program_id, config], 
      name: via_name(program_id))
  end
  
  def init([program_id, config]) do
    state = %__MODULE__{
      program_id: program_id,
      execution_graph: build_execution_graph(config.modules, config.dependencies),
      modules: config.modules,
      execution_strategy: config[:strategy] || :optimized,
      resource_limits: config[:resource_limits] || default_resource_limits(),
      performance_targets: config[:performance_targets] || default_performance_targets(),
      error_handling_config: config[:error_handling] || default_error_handling(),
      current_executions: %{},
      execution_history: :queue.new(),
      optimization_state: %{}
    }
    
    # Validate execution graph
    case validate_execution_graph(state.execution_graph) do
      :ok ->
        {:ok, state}
      
      {:error, reason} ->
        {:stop, {:invalid_execution_graph, reason}}
    end
  end
  
  @doc """
  Execute program with comprehensive monitoring and optimization.
  """
  def execute_program(program_id, inputs, opts \\ []) do
    GenServer.call(via_name(program_id), {:execute, inputs, opts}, 60_000)
  end
  
  @doc """
  Get program execution status and metrics.
  """
  def get_execution_status(program_id) do
    GenServer.call(via_name(program_id), :get_status)
  end
  
  @doc """
  Optimize program execution based on historical performance.
  """
  def optimize_program(program_id, optimization_opts \\ []) do
    GenServer.call(via_name(program_id), {:optimize, optimization_opts})
  end
  
  def handle_call({:execute, inputs, opts}, from, state) do
    execution_id = generate_execution_id()
    
    # Start telemetry span
    :telemetry.span([:dspex, :program, :execution],
      %{
        program_id: state.program_id,
        execution_id: execution_id,
        strategy: state.execution_strategy
      }, fn ->
      
      # Execute with comprehensive monitoring
      task = Task.async(fn ->
        execute_program_with_orchestration(inputs, opts, state)
      end)
      
      monitor_ref = Process.monitor(task.pid)
      
      execution_context = %ExecutionContext{
        execution_id: execution_id,
        task: task,
        monitor_ref: monitor_ref,
        from: from,
        start_time: System.monotonic_time(:microsecond),
        inputs: inputs,
        opts: opts,
        status: :running
      }
      
      new_executions = Map.put(state.current_executions, monitor_ref, execution_context)
      
      {:noreply, %{state | current_executions: new_executions}}
    end)
  end
  
  def handle_call(:get_status, _from, state) do
    status = %{
      program_id: state.program_id,
      current_executions: map_size(state.current_executions),
      execution_history_size: :queue.len(state.execution_history),
      execution_strategy: state.execution_strategy,
      optimization_state: state.optimization_state,
      performance_metrics: calculate_performance_metrics(state)
    }
    
    {:reply, status, state}
  end
  
  def handle_call({:optimize, optimization_opts}, _from, state) do
    case optimize_execution_engine(state, optimization_opts) do
      {:ok, optimized_state} ->
        {:reply, :ok, optimized_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  # Handle execution completion
  def handle_info({:DOWN, monitor_ref, :process, _pid, result}, state) do
    case Map.pop(state.current_executions, monitor_ref) do
      {execution_context, remaining_executions} when execution_context != nil ->
        # Calculate execution metrics
        duration = System.monotonic_time(:microsecond) - execution_context.start_time
        
        # Create execution record
        execution_record = %{
          execution_id: execution_context.execution_id,
          inputs: execution_context.inputs,
          result: result,
          duration: duration,
          timestamp: System.system_time(:second),
          strategy_used: state.execution_strategy
        }
        
        # Update execution history
        new_history = add_to_execution_history(state.execution_history, execution_record)
        
        # Emit telemetry
        :telemetry.execute([:dspex, :program, :completed],
          %{duration: duration},
          %{
            program_id: state.program_id,
            execution_id: execution_context.execution_id,
            result: categorize_result(result)
          }
        )
        
        # Reply to caller
        GenServer.reply(execution_context.from, result)
        
        # Update state
        new_state = %{state |
          current_executions: remaining_executions,
          execution_history: new_history
        }
        
        # Trigger optimization if conditions are met
        maybe_trigger_optimization(new_state)
      
      {nil, _} ->
        {:noreply, state}
    end
  end
  
  # Private execution functions
  
  defp execute_program_with_orchestration(inputs, opts, state) do
    try do
      # Validate inputs against program requirements
      case validate_program_inputs(inputs, state) do
        {:ok, validated_inputs} ->
          # Choose execution strategy
          strategy = determine_execution_strategy(state, opts)
          
          # Execute based on strategy
          case strategy do
            :sequential ->
              execute_sequential_strategy(validated_inputs, state)
            
            :parallel ->
              execute_parallel_strategy(validated_inputs, state)
            
            :optimized ->
              execute_optimized_strategy(validated_inputs, state)
            
            :resource_aware ->
              execute_resource_aware_strategy(validated_inputs, state)
          end
        
        {:error, validation_errors} ->
          {:error, {:input_validation_failed, validation_errors}}
      end
    rescue
      error ->
        {:error, {:execution_error, error}}
    end
  end
  
  defp execute_optimized_strategy(inputs, state) do
    # Analyze execution graph for optimal strategy
    execution_plan = create_execution_plan(state.execution_graph, inputs)
    
    # Execute with dynamic optimization
    case execute_execution_plan(execution_plan, state) do
      {:ok, results} ->
        {:ok, aggregate_program_results(results, state)}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp create_execution_plan(execution_graph, inputs) do
    # Perform topological sort to determine execution order
    execution_order = DependencyGraph.topological_sort(execution_graph)
    
    # Group modules that can execute in parallel
    execution_levels = group_by_execution_level(execution_order, execution_graph)
    
    # Create optimized execution plan
    %{
      execution_levels: execution_levels,
      total_modules: length(execution_order),
      estimated_duration: estimate_execution_duration(execution_order),
      parallelism_opportunities: count_parallelism_opportunities(execution_levels)
    }
  end
  
  defp execute_execution_plan(execution_plan, state) do
    # Execute each level in sequence, modules within level in parallel
    Enum.reduce_while(execution_plan.execution_levels, %{}, fn {level, modules}, acc_results ->
      level_inputs = prepare_level_inputs(modules, acc_results, state)
      
      # Execute all modules in this level concurrently with monitoring
      level_results = execute_level_with_monitoring(level, modules, level_inputs, state)
      
      case level_results do
        {:ok, results} ->
          {:cont, Map.merge(acc_results, results)}
        
        {:error, failed_modules} ->
          {:halt, {:error, {:level_execution_failed, level, failed_modules}}}
      end
    end)
  end
  
  defp execute_level_with_monitoring(level, modules, level_inputs, state) do
    # Start tasks for each module with resource monitoring
    tasks = Enum.map(modules, fn module_spec ->
      Task.async(fn ->
        execute_module_with_resource_monitoring(module_spec, level_inputs[module_spec.name], state)
      end)
    end)
    
    # Monitor execution with timeout and resource limits
    timeout = calculate_level_timeout(level, modules, state.performance_targets)
    
    case Task.await_many(tasks, timeout) do
      results when is_list(results) ->
        # Analyze results for success/failure
        {successful, failed} = partition_results(results, modules)
        
        if length(failed) == 0 do
          {:ok, successful}
        else
          # Handle partial failures based on error handling config
          handle_partial_failures(successful, failed, state.error_handling_config)
        end
      
      {:timeout, partial_results} ->
        {:error, {:level_timeout, level, partial_results}}
    end
  end
  
  defp execute_module_with_resource_monitoring(module_spec, inputs, state) do
    # Check resource availability
    case ResourceManager.request_resources(module_spec.resource_requirements) do
      {:ok, resource_allocation} ->
        try do
          # Execute module with telemetry
          :telemetry.span([:dspex, :module, :execution],
            %{
              module: module_spec.name,
              program: state.program_id
            }, fn ->
            
            result = execute_single_module(module_spec, inputs, state)
            {result, %{module: module_spec.name}}
          end)
        after
          # Always release resources
          ResourceManager.release_resources(resource_allocation)
        end
      
      {:error, :insufficient_resources} ->
        {:error, {:insufficient_resources, module_spec.name}}
    end
  end
  
  defp execute_single_module(module_spec, inputs, state) do
    case Registry.get_module(module_spec.module_id) do
      {:ok, module_info} ->
        # Execute module with timeout and monitoring
        case GenServer.call(module_info.pid, {:forward, inputs}, module_spec.timeout || 30_000) do
          {:ok, result} ->
            {:ok, {module_spec.name, result}}
          
          {:error, reason} ->
            {:error, {module_spec.name, reason}}
        end
      
      {:error, :module_not_found} ->
        {:error, {:module_not_found, module_spec.name}}
    end
  end
  
  defp handle_partial_failures(successful, failed, error_config) do
    failure_tolerance = Map.get(error_config, :failure_tolerance, :strict)
    
    case failure_tolerance do
      :strict ->
        # Any failure fails the entire execution
        {:error, {:partial_failures, failed}}
      
      :tolerant ->
        # Continue with successful results
        {:ok, successful}
      
      {:threshold, max_failures} when length(failed) <= max_failures ->
        # Within acceptable failure threshold
        {:ok, successful}
      
      {:threshold, max_failures} ->
        # Exceeded failure threshold
        {:error, {:failure_threshold_exceeded, max_failures, length(failed)}}
    end
  end
  
  # Optimization and performance functions
  
  defp optimize_execution_engine(state, optimization_opts) do
    # Analyze execution history for optimization opportunities
    optimization_analysis = analyze_execution_history(state.execution_history)
    
    # Apply optimizations based on analysis
    optimizations = [
      optimize_execution_order(optimization_analysis),
      optimize_resource_allocation(optimization_analysis),
      optimize_parallelism(optimization_analysis),
      optimize_timeouts(optimization_analysis)
    ]
    
    # Apply optimizations to state
    optimized_state = apply_optimizations(state, optimizations)
    
    {:ok, optimized_state}
  end
  
  defp analyze_execution_history(execution_history) do
    history_list = :queue.to_list(execution_history)
    
    %{
      total_executions: length(history_list),
      average_duration: calculate_average_duration(history_list),
      success_rate: calculate_success_rate(history_list),
      bottleneck_modules: identify_bottleneck_modules(history_list),
      resource_utilization: analyze_resource_utilization(history_list),
      parallelism_efficiency: analyze_parallelism_efficiency(history_list)
    }
  end
  
  defp identify_bottleneck_modules(execution_history) do
    # Analyze module execution times to identify bottlenecks
    module_times = Enum.reduce(execution_history, %{}, fn execution, acc ->
      case execution.result do
        {:ok, module_results} when is_map(module_results) ->
          Enum.reduce(module_results, acc, fn {module_name, _result}, inner_acc ->
            times = Map.get(inner_acc, module_name, [])
            Map.put(inner_acc, module_name, [execution.duration | times])
          end)
        
        _ ->
          acc
      end
    end)
    
    # Calculate average times and identify bottlenecks
    Enum.map(module_times, fn {module_name, times} ->
      avg_time = Enum.sum(times) / length(times)
      {module_name, avg_time}
    end)
    |> Enum.sort_by(fn {_module, avg_time} -> avg_time end, :desc)
    |> Enum.take(3)  # Top 3 bottlenecks
  end
  
  # Resource management and coordination
  
  defp prepare_level_inputs(modules, previous_results, state) do
    Enum.reduce(modules, %{}, fn module_spec, acc ->
      module_inputs = resolve_module_dependencies(module_spec, previous_results, state)
      Map.put(acc, module_spec.name, module_inputs)
    end)
  end
  
  defp resolve_module_dependencies(module_spec, previous_results, state) do
    dependencies = Map.get(state.execution_graph, module_spec.name, [])
    
    Enum.reduce(dependencies, %{}, fn dependency, acc ->
      case Map.get(previous_results, dependency) do
        nil ->
          Logger.warning("Dependency #{dependency} not found for module #{module_spec.name}")
          acc
        
        result ->
          Map.merge(acc, result)
      end
    end)
  end
  
  # Utility functions
  
  defp via_name(program_id) do
    {:via, Registry, {DSPex.Program.Registry, program_id}}
  end
  
  defp generate_execution_id do
    "exec_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
  
  defp build_execution_graph(modules, dependencies) do
    # Build directed acyclic graph of module dependencies
    Enum.reduce(dependencies, %{}, fn {module, deps}, acc ->
      Map.put(acc, module, deps)
    end)
  end
  
  defp validate_execution_graph(execution_graph) do
    # Check for cycles in the dependency graph
    case DependencyGraph.has_cycles?(execution_graph) do
      true ->
        {:error, :cyclic_dependencies}
      
      false ->
        :ok
    end
  end
  
  defp group_by_execution_level(execution_order, execution_graph) do
    # Group modules by their dependency level for parallel execution
    levels = DependencyGraph.calculate_dependency_levels(execution_order, execution_graph)
    
    Enum.group_by(levels, fn {_module, level} -> level end, fn {module, _level} -> module end)
    |> Enum.sort_by(fn {level, _modules} -> level end)
  end
  
  defp calculate_level_timeout(level, modules, performance_targets) do
    base_timeout = Map.get(performance_targets, :base_module_timeout, 30_000)
    level_multiplier = Map.get(performance_targets, :level_timeout_multiplier, 1.5)
    
    round(base_timeout * level_multiplier * length(modules))
  end
  
  defp default_resource_limits do
    %{
      max_concurrent_modules: 10,
      max_memory_per_module: 500 * 1024 * 1024,  # 500MB
      max_cpu_per_module: 1.0,  # 1 CPU core
      max_execution_time: 300_000  # 5 minutes
    }
  end
  
  defp default_performance_targets do
    %{
      target_execution_time: 30_000,  # 30 seconds
      base_module_timeout: 30_000,    # 30 seconds
      level_timeout_multiplier: 1.5,
      target_success_rate: 0.95
    }
  end
  
  defp default_error_handling do
    %{
      failure_tolerance: :strict,
      retry_strategy: :exponential_backoff,
      max_retries: 3,
      circuit_breaker: true
    }
  end
  
  defp add_to_execution_history(history, execution_record) do
    new_history = :queue.in(execution_record, history)
    
    # Keep only last 1000 executions
    if :queue.len(new_history) > 1000 do
      {_dropped, trimmed} = :queue.out(new_history)
      trimmed
    else
      new_history
    end
  end
  
  defp calculate_performance_metrics(state) do
    history_list = :queue.to_list(state.execution_history)
    
    %{
      total_executions: length(history_list),
      average_duration: calculate_average_duration(history_list),
      success_rate: calculate_success_rate(history_list),
      current_load: map_size(state.current_executions)
    }
  end
  
  defp calculate_average_duration(history_list) do
    if length(history_list) > 0 do
      total_duration = Enum.sum(Enum.map(history_list, & &1.duration))
      total_duration / length(history_list)
    else
      0
    end
  end
  
  defp calculate_success_rate(history_list) do
    if length(history_list) > 0 do
      successful = Enum.count(history_list, fn record ->
        match?({:ok, _}, record.result)
      end)
      successful / length(history_list)
    else
      0.0
    end
  end
  
  defp categorize_result(result) do
    case result do
      {:ok, _} -> :success
      {:error, _} -> :error
      _ -> :unknown
    end
  end
  
  defp maybe_trigger_optimization(state) do
    # Check if optimization should be triggered based on execution history
    history_size = :queue.len(state.execution_history)
    
    if rem(history_size, 100) == 0 and history_size > 0 do
      # Trigger optimization every 100 executions
      Task.start(fn ->
        GenServer.cast(via_name(state.program_id), :trigger_optimization)
      end)
    end
    
    {:noreply, state}
  end
end
```

### DEPENDENCY GRAPH MANAGEMENT

**Advanced Dependency Analysis and Optimization:**

```elixir
defmodule DSPex.Program.DependencyGraph do
  @moduledoc """
  Advanced dependency graph analysis and optimization for program execution.
  """
  
  @doc """
  Perform topological sort on dependency graph.
  """
  def topological_sort(graph) do
    # Kahn's algorithm for topological sorting
    in_degree = calculate_in_degrees(graph)
    queue = :queue.from_list(nodes_with_zero_in_degree(in_degree))
    
    topological_sort_recursive(queue, in_degree, graph, [])
  end
  
  defp topological_sort_recursive(queue, in_degree, graph, result) do
    case :queue.out(queue) do
      {{:value, node}, remaining_queue} ->
        # Add node to result
        new_result = [node | result]
        
        # Reduce in-degree of dependent nodes
        {new_queue, new_in_degree} = process_dependencies(node, remaining_queue, in_degree, graph)
        
        topological_sort_recursive(new_queue, new_in_degree, graph, new_result)
      
      {:empty, _} ->
        Enum.reverse(result)
    end
  end
  
  defp process_dependencies(node, queue, in_degree, graph) do
    dependents = get_dependents(node, graph)
    
    Enum.reduce(dependents, {queue, in_degree}, fn dependent, {acc_queue, acc_in_degree} ->
      new_degree = Map.get(acc_in_degree, dependent, 0) - 1
      new_in_degree = Map.put(acc_in_degree, dependent, new_degree)
      
      if new_degree == 0 do
        new_queue = :queue.in(dependent, acc_queue)
        {new_queue, new_in_degree}
      else
        {acc_queue, new_in_degree}
      end
    end)
  end
  
  @doc """
  Check if the graph has cycles.
  """
  def has_cycles?(graph) do
    # Use DFS to detect cycles
    nodes = get_all_nodes(graph)
    visited = MapSet.new()
    rec_stack = MapSet.new()
    
    Enum.any?(nodes, fn node ->
      if not MapSet.member?(visited, node) do
        has_cycle_dfs(node, graph, visited, rec_stack)
      else
        false
      end
    end)
  end
  
  defp has_cycle_dfs(node, graph, visited, rec_stack) do
    new_visited = MapSet.put(visited, node)
    new_rec_stack = MapSet.put(rec_stack, node)
    
    dependencies = Map.get(graph, node, [])
    
    Enum.any?(dependencies, fn dep ->
      cond do
        not MapSet.member?(new_visited, dep) ->
          has_cycle_dfs(dep, graph, new_visited, new_rec_stack)
        
        MapSet.member?(new_rec_stack, dep) ->
          true
        
        true ->
          false
      end
    end)
  end
  
  @doc """
  Calculate dependency levels for parallel execution optimization.
  """
  def calculate_dependency_levels(execution_order, graph) do
    # Calculate the maximum dependency depth for each node
    levels = Enum.reduce(execution_order, %{}, fn node, acc ->
      level = calculate_node_level(node, graph, acc)
      Map.put(acc, node, level)
    end)
    
    Enum.map(execution_order, fn node ->
      {node, Map.get(levels, node, 0)}
    end)
  end
  
  defp calculate_node_level(node, graph, existing_levels) do
    dependencies = Map.get(graph, node, [])
    
    if dependencies == [] do
      0
    else
      max_dep_level = dependencies
      |> Enum.map(fn dep -> Map.get(existing_levels, dep, 0) end)
      |> Enum.max()
      
      max_dep_level + 1
    end
  end
  
  @doc """
  Optimize execution graph for better performance.
  """
  def optimize_graph(graph, execution_history) do
    # Analyze execution patterns
    bottlenecks = identify_execution_bottlenecks(execution_history)
    critical_path = find_critical_path(graph, bottlenecks)
    
    # Apply optimizations
    optimized_graph = graph
    |> reorder_for_critical_path(critical_path)
    |> balance_parallelism(bottlenecks)
    |> optimize_resource_usage(execution_history)
    
    optimized_graph
  end
  
  defp identify_execution_bottlenecks(execution_history) do
    # Analyze execution times to identify bottlenecks
    history_list = :queue.to_list(execution_history)
    
    module_performances = Enum.reduce(history_list, %{}, fn execution, acc ->
      case execution.result do
        {:ok, module_results} when is_map(module_results) ->
          Enum.reduce(module_results, acc, fn {module, _result}, inner_acc ->
            times = Map.get(inner_acc, module, [])
            Map.put(inner_acc, module, [execution.duration | times])
          end)
        
        _ ->
          acc
      end
    end)
    
    # Calculate average execution times
    Enum.map(module_performances, fn {module, times} ->
      avg_time = Enum.sum(times) / length(times)
      {module, avg_time}
    end)
    |> Enum.into(%{})
  end
  
  defp find_critical_path(graph, bottlenecks) do
    # Find the longest path through the graph considering execution times
    all_paths = find_all_paths(graph)
    
    Enum.max_by(all_paths, fn path ->
      calculate_path_weight(path, bottlenecks)
    end)
  end
  
  defp calculate_path_weight(path, bottlenecks) do
    Enum.sum(Enum.map(path, fn node ->
      Map.get(bottlenecks, node, 1)
    end))
  end
  
  # Utility functions
  
  defp calculate_in_degrees(graph) do
    all_nodes = get_all_nodes(graph)
    
    Enum.reduce(all_nodes, %{}, fn node, acc ->
      Map.put(acc, node, 0)
    end)
    |> then(fn initial_degrees ->
      Enum.reduce(graph, initial_degrees, fn {_node, dependencies}, acc ->
        Enum.reduce(dependencies, acc, fn dep, inner_acc ->
          Map.update(inner_acc, dep, 1, &(&1 + 1))
        end)
      end)
    end)
  end
  
  defp nodes_with_zero_in_degree(in_degree) do
    Enum.filter(in_degree, fn {_node, degree} -> degree == 0 end)
    |> Enum.map(fn {node, _degree} -> node end)
  end
  
  defp get_all_nodes(graph) do
    dependencies = Map.values(graph) |> List.flatten()
    nodes = Map.keys(graph)
    
    (nodes ++ dependencies)
    |> Enum.uniq()
  end
  
  defp get_dependents(node, graph) do
    Enum.filter(graph, fn {_dependent, dependencies} ->
      Enum.member?(dependencies, node)
    end)
    |> Enum.map(fn {dependent, _dependencies} -> dependent end)
  end
  
  defp find_all_paths(graph) do
    # Find all possible execution paths through the graph
    entry_points = find_entry_points(graph)
    
    Enum.flat_map(entry_points, fn entry ->
      find_paths_from_node(entry, graph, [])
    end)
  end
  
  defp find_entry_points(graph) do
    all_nodes = get_all_nodes(graph)
    dependency_nodes = Map.values(graph) |> List.flatten() |> MapSet.new()
    
    Enum.filter(all_nodes, fn node ->
      not MapSet.member?(dependency_nodes, node)
    end)
  end
  
  defp find_paths_from_node(node, graph, current_path) do
    new_path = [node | current_path]
    dependents = get_dependents(node, graph)
    
    if dependents == [] do
      [Enum.reverse(new_path)]
    else
      Enum.flat_map(dependents, fn dependent ->
        find_paths_from_node(dependent, graph, new_path)
      end)
    end
  end
end
```

### RESOURCE MANAGEMENT SYSTEM

**Advanced Resource Allocation and Monitoring:**

```elixir
defmodule DSPex.Program.ResourceManager do
  @moduledoc """
  Advanced resource management for program execution optimization.
  """
  
  use GenServer
  
  defstruct [
    :total_resources,
    :allocated_resources,
    :resource_reservations,
    :allocation_history,
    :performance_metrics
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    total_resources = %{
      cpu_cores: Keyword.get(opts, :cpu_cores, System.schedulers_online()),
      memory_mb: Keyword.get(opts, :memory_mb, get_system_memory_mb()),
      concurrent_operations: Keyword.get(opts, :concurrent_operations, 100),
      network_bandwidth: Keyword.get(opts, :network_bandwidth, 1000)  # Mbps
    }
    
    state = %__MODULE__{
      total_resources: total_resources,
      allocated_resources: %{cpu_cores: 0, memory_mb: 0, concurrent_operations: 0, network_bandwidth: 0},
      resource_reservations: %{},
      allocation_history: :queue.new(),
      performance_metrics: %{}
    }
    
    # Schedule periodic resource monitoring
    :timer.send_interval(5000, :monitor_resources)
    
    {:ok, state}
  end
  
  @doc """
  Request resource allocation for a module execution.
  """
  def request_resources(resource_requirements) do
    GenServer.call(__MODULE__, {:request_resources, resource_requirements})
  end
  
  @doc """
  Release previously allocated resources.
  """
  def release_resources(allocation_id) do
    GenServer.call(__MODULE__, {:release_resources, allocation_id})
  end
  
  @doc """
  Get current resource utilization.
  """
  def get_resource_utilization do
    GenServer.call(__MODULE__, :get_utilization)
  end
  
  def handle_call({:request_resources, requirements}, _from, state) do
    case check_resource_availability(requirements, state) do
      {:ok, allocation_id} ->
        new_state = allocate_resources(allocation_id, requirements, state)
        {:reply, {:ok, allocation_id}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:release_resources, allocation_id}, _from, state) do
    case release_allocation(allocation_id, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call(:get_utilization, _from, state) do
    utilization = calculate_resource_utilization(state)
    {:reply, utilization, state}
  end
  
  def handle_info(:monitor_resources, state) do
    # Monitor actual resource usage vs allocations
    actual_usage = get_actual_resource_usage()
    new_metrics = update_performance_metrics(state.performance_metrics, actual_usage)
    
    new_state = %{state | performance_metrics: new_metrics}
    
    # Check for resource pressure and optimization opportunities
    maybe_optimize_allocations(new_state)
  end
  
  defp check_resource_availability(requirements, state) do
    required_cpu = Map.get(requirements, :cpu_cores, 0)
    required_memory = Map.get(requirements, :memory_mb, 0)
    required_ops = Map.get(requirements, :concurrent_operations, 1)
    required_bandwidth = Map.get(requirements, :network_bandwidth, 0)
    
    available_cpu = state.total_resources.cpu_cores - state.allocated_resources.cpu_cores
    available_memory = state.total_resources.memory_mb - state.allocated_resources.memory_mb
    available_ops = state.total_resources.concurrent_operations - state.allocated_resources.concurrent_operations
    available_bandwidth = state.total_resources.network_bandwidth - state.allocated_resources.network_bandwidth
    
    cond do
      required_cpu > available_cpu ->
        {:error, {:insufficient_cpu, required_cpu, available_cpu}}
      
      required_memory > available_memory ->
        {:error, {:insufficient_memory, required_memory, available_memory}}
      
      required_ops > available_ops ->
        {:error, {:insufficient_concurrent_operations, required_ops, available_ops}}
      
      required_bandwidth > available_bandwidth ->
        {:error, {:insufficient_bandwidth, required_bandwidth, available_bandwidth}}
      
      true ->
        allocation_id = generate_allocation_id()
        {:ok, allocation_id}
    end
  end
  
  defp allocate_resources(allocation_id, requirements, state) do
    # Update allocated resources
    new_allocated = %{
      cpu_cores: state.allocated_resources.cpu_cores + Map.get(requirements, :cpu_cores, 0),
      memory_mb: state.allocated_resources.memory_mb + Map.get(requirements, :memory_mb, 0),
      concurrent_operations: state.allocated_resources.concurrent_operations + Map.get(requirements, :concurrent_operations, 1),
      network_bandwidth: state.allocated_resources.network_bandwidth + Map.get(requirements, :network_bandwidth, 0)
    }
    
    # Record allocation
    allocation_record = %{
      allocation_id: allocation_id,
      requirements: requirements,
      allocated_at: System.system_time(:second)
    }
    
    new_reservations = Map.put(state.resource_reservations, allocation_id, allocation_record)
    new_history = :queue.in({:allocation, allocation_record}, state.allocation_history)
    
    %{state |
      allocated_resources: new_allocated,
      resource_reservations: new_reservations,
      allocation_history: new_history
    }
  end
  
  defp release_allocation(allocation_id, state) do
    case Map.pop(state.resource_reservations, allocation_id) do
      {allocation_record, remaining_reservations} when allocation_record != nil ->
        # Update allocated resources
        requirements = allocation_record.requirements
        
        new_allocated = %{
          cpu_cores: state.allocated_resources.cpu_cores - Map.get(requirements, :cpu_cores, 0),
          memory_mb: state.allocated_resources.memory_mb - Map.get(requirements, :memory_mb, 0),
          concurrent_operations: state.allocated_resources.concurrent_operations - Map.get(requirements, :concurrent_operations, 1),
          network_bandwidth: state.allocated_resources.network_bandwidth - Map.get(requirements, :network_bandwidth, 0)
        }
        
        # Record release
        release_record = %{
          allocation_id: allocation_id,
          released_at: System.system_time(:second),
          duration: System.system_time(:second) - allocation_record.allocated_at
        }
        
        new_history = :queue.in({:release, release_record}, state.allocation_history)
        
        new_state = %{state |
          allocated_resources: new_allocated,
          resource_reservations: remaining_reservations,
          allocation_history: new_history
        }
        
        {:ok, new_state}
      
      {nil, _} ->
        {:error, :allocation_not_found}
    end
  end
  
  defp calculate_resource_utilization(state) do
    %{
      cpu_utilization: state.allocated_resources.cpu_cores / state.total_resources.cpu_cores,
      memory_utilization: state.allocated_resources.memory_mb / state.total_resources.memory_mb,
      operation_utilization: state.allocated_resources.concurrent_operations / state.total_resources.concurrent_operations,
      bandwidth_utilization: state.allocated_resources.network_bandwidth / state.total_resources.network_bandwidth,
      active_allocations: map_size(state.resource_reservations)
    }
  end
  
  defp get_actual_resource_usage do
    # Get actual system resource usage
    %{
      cpu_usage: get_cpu_usage(),
      memory_usage: get_memory_usage(),
      process_count: length(Process.list()),
      system_load: :cpu_sup.avg1() / 256  # Load average
    }
  end
  
  defp get_cpu_usage do
    # Simple CPU usage estimation
    :cpu_sup.util() |> Enum.sum() / length(:cpu_sup.util())
  end
  
  defp get_memory_usage do
    # Get memory usage in MB
    total_memory = :erlang.memory(:total)
    total_memory / (1024 * 1024)
  end
  
  defp get_system_memory_mb do
    # Get total system memory in MB
    case :memsup.get_system_memory_data() do
      data when is_list(data) ->
        case List.keyfind(data, :total_memory, 0) do
          {:total_memory, total} -> div(total, 1024 * 1024)
          nil -> 4096  # Default to 4GB
        end
      
      _ ->
        4096  # Default to 4GB
    end
  end
  
  defp generate_allocation_id do
    "alloc_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
  
  defp update_performance_metrics(metrics, actual_usage) do
    timestamp = System.system_time(:second)
    
    Map.merge(metrics, %{
      last_update: timestamp,
      cpu_efficiency: calculate_cpu_efficiency(actual_usage),
      memory_efficiency: calculate_memory_efficiency(actual_usage),
      resource_waste: calculate_resource_waste(actual_usage)
    })
  end
  
  defp calculate_cpu_efficiency(actual_usage) do
    # Simple efficiency calculation
    max(0.0, min(1.0, actual_usage.cpu_usage / 100))
  end
  
  defp calculate_memory_efficiency(actual_usage) do
    # Memory efficiency based on actual vs expected usage
    expected_usage = 0.8  # 80% expected utilization
    actual = actual_usage.memory_usage / get_system_memory_mb()
    
    if actual > 0 do
      min(1.0, expected_usage / actual)
    else
      0.0
    end
  end
  
  defp calculate_resource_waste(_actual_usage) do
    # Calculate percentage of allocated but unused resources
    0.05  # Placeholder - 5% waste
  end
  
  defp maybe_optimize_allocations(state) do
    # Check if optimization is needed
    utilization = calculate_resource_utilization(state)
    
    if should_optimize?(utilization) do
      Task.start(fn ->
        optimize_resource_allocation(state)
      end)
    end
    
    {:noreply, state}
  end
  
  defp should_optimize?(utilization) do
    # Trigger optimization if utilization is very high or very low
    cpu_util = utilization.cpu_utilization
    memory_util = utilization.memory_utilization
    
    (cpu_util > 0.9 or memory_util > 0.9) or (cpu_util < 0.2 and memory_util < 0.2)
  end
  
  defp optimize_resource_allocation(state) do
    # Placeholder for resource allocation optimization
    Logger.info("Optimizing resource allocation based on utilization patterns")
  end
end
```

## IMPLEMENTATION REQUIREMENTS

### SUCCESS CRITERIA

**Program Execution Engine Must Achieve:**

1. **Advanced Orchestration** - Dependency-aware execution with optimal parallelism
2. **Fault Tolerance** - Comprehensive error handling with recovery strategies
3. **Performance Optimization** - Resource-aware execution with bottleneck detection
4. **DSPy Compatibility** - 100% compatible with DSPy program patterns
5. **Production Readiness** - Monitoring, optimization, and operational features

### PERFORMANCE TARGETS

**Execution Engine Performance:**
- **<5s** program startup and initialization time
- **>90% resource utilization** efficiency under optimal conditions
- **<10ms** dependency resolution time for complex graphs
- **Support for 100+ module programs** with complex dependencies
- **Automatic optimization** based on execution history

### FAULT TOLERANCE REQUIREMENTS

**Program Execution Fault Tolerance:**
- Graceful handling of module failures with configurable tolerance levels
- Automatic retry with exponential backoff for transient failures
- Resource cleanup and recovery on execution failures
- Execution state preservation for debugging and analysis
- Circuit breaker patterns for repeated failures

## EXPECTED DELIVERABLES

### PRIMARY DELIVERABLES

1. **Execution Engine** - Complete `DSPex.Program.ExecutionEngine` with orchestration
2. **Dependency Graph Manager** - Advanced dependency analysis and optimization
3. **Resource Manager** - Intelligent resource allocation and monitoring
4. **Execution Context** - Comprehensive execution state and monitoring
5. **Performance Optimization** - Automatic optimization based on execution patterns

### VERIFICATION AND VALIDATION

**Execution Engine Verified:**
- Complex dependency graphs execute correctly with optimal parallelism
- Resource management prevents conflicts and optimizes utilization
- Error handling and recovery work correctly under failure conditions
- Performance optimization improves execution efficiency over time
- DSPy program compatibility is maintained with enhanced features

This comprehensive program execution engine provides the foundation for complex ML program orchestration with superior performance, fault tolerance, and optimization capabilities.