# Stage 2 Prompt 3: Core Module System Architecture

## OBJECTIVE

Implement a comprehensive GenServer-based module system that replaces DSPy's Python class-based modules with native Elixir processes. This system must provide parameter tracking, state management, module composition, lifecycle management, and supervision tree integration while maintaining 100% DSPy module API compatibility and delivering superior fault tolerance and performance through OTP design patterns.

## COMPLETE IMPLEMENTATION CONTEXT

### MODULE SYSTEM ARCHITECTURE OVERVIEW

From Stage 2 Technical Specification:

```
┌─────────────────────────────────────────────────────────────┐
│                Core Module System Architecture             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Module Behavior │  │ State           │  │ Parameter    ││
│  │ - GenServer     │  │ Management      │  │ Tracking     ││
│  │ - Lifecycle     │  │ - Persistence   │  │ - Learning   ││
│  │ - Composition   │  │ - Recovery      │  │ - Gradients  ││
│  │ - Supervision   │  │ - Snapshots     │  │ - History    ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Module Registry │  │ Composition     │  │ Fault        ││
│  │ - Discovery     │  │ - Dependencies  │  │ Tolerance    ││
│  │ - Management    │  │ - Orchestration │  │ - Recovery   ││
│  │ - Hot Swapping  │  │ - Parallelism   │  │ - Isolation  ││
│  │ - Versioning    │  │ - Coordination  │  │ - Monitoring ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### DSPy MODULE SYSTEM ANALYSIS

From comprehensive DSPy source code analysis (primitives/module.py):

**DSPy Module Core Patterns:**

```python
# DSPy Module base class with parameter tracking
class Module:
    def __init__(self):
        self._compiled = False
        self._parameters = {}
        self._predictors = {}
        self._modules = {}
        
    def named_parameters(self):
        """Return all parameters with their names."""
        for name, value in self._parameters.items():
            yield name, value
        
        for name, module in self._modules.items():
            for sub_name, sub_value in module.named_parameters():
                yield f"{name}.{sub_name}", sub_value
    
    def parameters(self):
        """Return all parameters."""
        for name, value in self.named_parameters():
            yield value
    
    def forward(self, *args, **kwargs):
        """Forward pass - must be implemented by subclasses."""
        raise NotImplementedError
    
    def __call__(self, *args, **kwargs):
        """Make module callable."""
        return self.forward(*args, **kwargs)
    
    def train(self):
        """Set module to training mode."""
        self._training = True
        for module in self._modules.values():
            module.train()
    
    def eval(self):
        """Set module to evaluation mode."""
        self._training = False
        for module in self._modules.values():
            module.eval()

# Example DSPy module implementation
class ChainOfThought(Module):
    def __init__(self, signature):
        super().__init__()
        self.signature = signature
        self.predictor = Predict(signature)
        
    def forward(self, **kwargs):
        # Chain of thought reasoning
        reasoning = self.predictor(generate_cot_prompt(**kwargs))
        return reasoning
        
# Parameter tracking in DSPy
class Parameter:
    def __init__(self, value, requires_grad=False):
        self.value = value
        self.requires_grad = requires_grad
        self.grad = None
        
    def update(self, new_value):
        self.value = new_value
```

**Key DSPy Module Features:**
1. **Parameter Management** - Hierarchical parameter tracking and updates
2. **Module Composition** - Nested modules with automatic parameter collection
3. **Training/Evaluation Modes** - State management for learning vs inference
4. **Forward Pass Pattern** - Consistent execution interface
5. **Compilation Support** - Optimization and compilation integration

### ADVANCED GENSERVER MODULE PATTERNS

From Elixir/OTP best practices for stateful ML operations:

**GenServer Patterns for ML Modules:**

```elixir
# Advanced GenServer state management
defmodule ModuleState do
  defstruct [
    :module_id,
    :signature,
    :parameters,
    :predictors,
    :sub_modules,
    :training_mode,
    :execution_history,
    :performance_metrics,
    :optimization_state,
    :compilation_status,
    :last_checkpoint,
    :error_recovery_data
  ]
end

# Supervision tree patterns for module management
defmodule ModuleSupervisor do
  use Supervisor
  
  def start_link(module_config) do
    Supervisor.start_link(__MODULE__, module_config, name: __MODULE__)
  end
  
  def init(module_config) do
    children = [
      # Module registry for discovery and management
      {ModuleRegistry, []},
      
      # Parameter store for shared parameters
      {ParameterStore, []},
      
      # Module instances with restart strategies
      {DynamicSupervisor, strategy: :one_for_one, name: ModuleInstanceSupervisor}
    ]
    
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
```

### COMPREHENSIVE NATIVE MODULE SYSTEM

**Core Module Behavior with GenServer Integration:**

```elixir
defmodule AshDSPy.Module.Native do
  @moduledoc """
  Native Elixir module system using GenServer for state management and supervision.
  Provides 100% DSPy module compatibility with enhanced fault tolerance.
  """
  
  defmacro __using__(opts) do
    quote do
      use GenServer
      import AshDSPy.Module.Native
      import AshDSPy.Module.DSL
      
      # Module registration attributes
      Module.register_attribute(__MODULE__, :module_parameters, accumulate: true)
      Module.register_attribute(__MODULE__, :module_predictors, accumulate: true)
      Module.register_attribute(__MODULE__, :module_sub_modules, accumulate: true)
      Module.register_attribute(__MODULE__, :module_config, accumulate: false)
      Module.register_attribute(__MODULE__, :module_metadata, accumulate: false)
      
      @before_compile AshDSPy.Module.Native
    end
  end
  
  @doc """
  Define a parameter for the module.
  """
  defmacro parameter(name, type, opts \\ []) do
    quote do
      @module_parameters {unquote(name), unquote(type), unquote(opts)}
    end
  end
  
  @doc """
  Define a predictor component.
  """
  defmacro predictor(name, signature_module, opts \\ []) do
    quote do
      @module_predictors {unquote(name), unquote(signature_module), unquote(opts)}
    end
  end
  
  @doc """
  Define a sub-module component.
  """
  defmacro sub_module(name, module_type, opts \\ []) do
    quote do
      @module_sub_modules {unquote(name), unquote(module_type), unquote(opts)}
    end
  end
  
  @doc """
  Define the forward pass for the module.
  """
  defmacro forward(args, do: body) do
    quote do
      def handle_call({:forward, inputs}, from, state) do
        # Extract arguments for forward pass
        unquote(args) = extract_forward_args(inputs)
        
        # Execute forward pass with state tracking
        task = Task.async(fn ->
          execute_forward_with_monitoring(fn ->
            unquote(body)
          end, state)
        end)
        
        # Monitor execution
        monitor_ref = Process.monitor(task.pid)
        
        execution_context = %{
          task: task,
          monitor_ref: monitor_ref,
          from: from,
          start_time: System.monotonic_time(:microsecond),
          inputs: inputs
        }
        
        new_pending = Map.put(state.pending_executions || %{}, monitor_ref, execution_context)
        
        {:noreply, %{state | pending_executions: new_pending}}
      end
    end
  end
  
  defmacro __before_compile__(env) do
    parameters = Module.get_attribute(env.module, :module_parameters)
    predictors = Module.get_attribute(env.module, :module_predictors)
    sub_modules = Module.get_attribute(env.module, :module_sub_modules)
    config = Module.get_attribute(env.module, :module_config) || %{}
    
    quote do
      @module_metadata %{
        module: __MODULE__,
        parameters: unquote(Macro.escape(parameters)),
        predictors: unquote(Macro.escape(predictors)),
        sub_modules: unquote(Macro.escape(sub_modules)),
        config: unquote(Macro.escape(config)),
        compiled_at: System.system_time(:second)
      }
      
      # Generate parameter access functions
      unquote(generate_parameter_functions(parameters))
      
      # Generate predictor access functions
      unquote(generate_predictor_functions(predictors))
      
      # Generate sub-module access functions
      unquote(generate_sub_module_functions(sub_modules))
      
      # Core GenServer callbacks
      def init(opts) do
        module_id = Keyword.get(opts, :module_id, generate_module_id())
        
        # Initialize state
        state = %AshDSPy.Module.State{
          module_id: module_id,
          module: __MODULE__,
          parameters: initialize_parameters(unquote(Macro.escape(parameters)), opts),
          predictors: initialize_predictors(unquote(Macro.escape(predictors)), opts),
          sub_modules: initialize_sub_modules(unquote(Macro.escape(sub_modules)), opts),
          training_mode: Keyword.get(opts, :training_mode, false),
          execution_history: :queue.new(),
          performance_metrics: %{},
          optimization_state: %{},
          compilation_status: :not_compiled,
          last_checkpoint: nil,
          error_recovery_data: %{}
        }
        
        # Register module
        AshDSPy.Module.Registry.register_module(module_id, __MODULE__, self())
        
        # Start monitoring sub-modules
        monitor_sub_modules(state.sub_modules)
        
        {:ok, state}
      end
      
      def handle_call({:get_parameter, name}, _from, state) do
        case Map.get(state.parameters, name) do
          nil ->
            {:reply, {:error, :parameter_not_found}, state}
          
          parameter ->
            {:reply, {:ok, parameter.value}, state}
        end
      end
      
      def handle_call({:set_parameter, name, value}, _from, state) do
        case Map.get(state.parameters, name) do
          nil ->
            {:reply, {:error, :parameter_not_found}, state}
          
          parameter ->
            updated_parameter = %{parameter | value: value, updated_at: System.system_time(:second)}
            new_parameters = Map.put(state.parameters, name, updated_parameter)
            
            # Track parameter change
            parameter_change = %{
              parameter: name,
              old_value: parameter.value,
              new_value: value,
              timestamp: System.system_time(:second)
            }
            
            new_history = add_to_execution_history(state.execution_history, {:parameter_update, parameter_change})
            
            new_state = %{state |
              parameters: new_parameters,
              execution_history: new_history
            }
            
            {:reply, :ok, new_state}
        end
      end
      
      def handle_call({:predict, predictor_name, inputs}, from, state) do
        case Map.get(state.predictors, predictor_name) do
          nil ->
            {:reply, {:error, :predictor_not_found}, state}
          
          predictor ->
            # Execute prediction asynchronously
            execute_predictor_async(predictor, inputs, from, state)
        end
      end
      
      def handle_call({:train_mode}, _from, state) do
        new_state = set_training_mode(state, true)
        {:reply, :ok, new_state}
      end
      
      def handle_call({:eval_mode}, _from, state) do
        new_state = set_training_mode(state, false)
        {:reply, :ok, new_state}
      end
      
      def handle_call({:compile, optimization_opts}, _from, state) do
        case compile_module(state, optimization_opts) do
          {:ok, compiled_state} ->
            {:reply, :ok, compiled_state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      end
      
      def handle_call({:checkpoint}, _from, state) do
        checkpoint = create_checkpoint(state)
        new_state = %{state | last_checkpoint: checkpoint}
        {:reply, {:ok, checkpoint}, new_state}
      end
      
      def handle_call({:restore_checkpoint, checkpoint}, _from, state) do
        case restore_from_checkpoint(state, checkpoint) do
          {:ok, restored_state} ->
            {:reply, :ok, restored_state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      end
      
      # Handle async execution results
      def handle_info({:DOWN, monitor_ref, :process, _pid, result}, state) do
        case Map.pop(state.pending_executions || %{}, monitor_ref) do
          {execution_context, remaining_pending} when execution_context != nil ->
            # Calculate execution metrics
            duration = System.monotonic_time(:microsecond) - execution_context.start_time
            
            # Update execution history
            execution_record = %{
              type: :forward_pass,
              inputs: execution_context.inputs,
              result: result,
              duration: duration,
              timestamp: System.system_time(:second)
            }
            
            new_history = add_to_execution_history(state.execution_history, execution_record)
            
            # Update performance metrics
            new_metrics = update_performance_metrics(state.performance_metrics, execution_record)
            
            # Reply to caller
            GenServer.reply(execution_context.from, result)
            
            new_state = %{state |
              pending_executions: remaining_pending,
              execution_history: new_history,
              performance_metrics: new_metrics
            }
            
            {:noreply, new_state}
          
          {nil, _} ->
            {:noreply, state}
        end
      end
      
      # Handle sub-module monitoring
      def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
        case find_sub_module_by_pid(state.sub_modules, pid) do
          {:ok, sub_module_name} ->
            Logger.warning("Sub-module #{sub_module_name} crashed: #{inspect(reason)}")
            
            # Attempt to restart sub-module
            case restart_sub_module(sub_module_name, state) do
              {:ok, new_state} ->
                {:noreply, new_state}
              
              {:error, restart_reason} ->
                Logger.error("Failed to restart sub-module #{sub_module_name}: #{restart_reason}")
                {:noreply, state}
            end
          
          :not_found ->
            {:noreply, state}
        end
      end
      
      # Default forward implementation if not overridden
      unless Module.defines?(__MODULE__, {:handle_call, 3}) do
        def handle_call({:forward, _inputs}, _from, state) do
          {:reply, {:error, :forward_not_implemented}, state}
        end
      end
      
      # Module metadata access
      def __module_metadata__, do: @module_metadata
      
      # DSPy compatibility functions
      def named_parameters(pid) do
        GenServer.call(pid, :named_parameters)
      end
      
      def parameters(pid) do
        GenServer.call(pid, :parameters)
      end
      
      def train(pid) do
        GenServer.call(pid, {:train_mode})
      end
      
      def eval(pid) do
        GenServer.call(pid, {:eval_mode})
      end
    end
  end
  
  # Code generation functions
  
  defp generate_parameter_functions(parameters) do
    Enum.map(parameters, fn {name, type, opts} ->
      quote do
        def unquote(:"get_#{name}")(pid) do
          GenServer.call(pid, {:get_parameter, unquote(name)})
        end
        
        def unquote(:"set_#{name}")(pid, value) do
          GenServer.call(pid, {:set_parameter, unquote(name), value})
        end
        
        def unquote(:"#{name}_type")() do
          unquote(type)
        end
        
        def unquote(:"#{name}_opts")() do
          unquote(opts)
        end
      end
    end)
  end
  
  defp generate_predictor_functions(predictors) do
    Enum.map(predictors, fn {name, signature_module, opts} ->
      quote do
        def unquote(:"predict_#{name}")(pid, inputs) do
          GenServer.call(pid, {:predict, unquote(name), inputs})
        end
        
        def unquote(:"#{name}_signature")() do
          unquote(signature_module)
        end
        
        def unquote(:"#{name}_opts")() do
          unquote(opts)
        end
      end
    end)
  end
  
  defp generate_sub_module_functions(sub_modules) do
    Enum.map(sub_modules, fn {name, module_type, opts} ->
      quote do
        def unquote(:"get_#{name}")(pid) do
          GenServer.call(pid, {:get_sub_module, unquote(name)})
        end
        
        def unquote(:"#{name}_type")() do
          unquote(module_type)
        end
        
        def unquote(:"#{name}_opts")() do
          unquote(opts)
        end
      end
    end)
  end
end
```

### MODULE STATE MANAGEMENT

**Advanced State Management with Persistence:**

```elixir
defmodule AshDSPy.Module.State do
  @moduledoc """
  Module state structure with comprehensive tracking and persistence.
  """
  
  defstruct [
    # Core identification
    :module_id,
    :module,
    :pid,
    
    # Component management
    :parameters,
    :predictors,
    :sub_modules,
    
    # Execution state
    :training_mode,
    :compilation_status,
    :execution_history,
    :pending_executions,
    
    # Performance tracking
    :performance_metrics,
    :optimization_state,
    
    # Fault tolerance
    :last_checkpoint,
    :error_recovery_data,
    :restart_count,
    
    # Metadata
    :created_at,
    :last_updated,
    :version
  ]
  
  def new(module_id, module, opts \\ []) do
    %__MODULE__{
      module_id: module_id,
      module: module,
      pid: self(),
      parameters: %{},
      predictors: %{},
      sub_modules: %{},
      training_mode: Keyword.get(opts, :training_mode, false),
      compilation_status: :not_compiled,
      execution_history: :queue.new(),
      pending_executions: %{},
      performance_metrics: initialize_performance_metrics(),
      optimization_state: %{},
      last_checkpoint: nil,
      error_recovery_data: %{},
      restart_count: 0,
      created_at: System.system_time(:second),
      last_updated: System.system_time(:second),
      version: "1.0"
    }
  end
  
  def update_parameter(state, name, value) do
    case Map.get(state.parameters, name) do
      nil ->
        {:error, :parameter_not_found}
      
      parameter ->
        updated_parameter = %{parameter |
          value: value,
          updated_at: System.system_time(:second)
        }
        
        new_parameters = Map.put(state.parameters, name, updated_parameter)
        
        updated_state = %{state |
          parameters: new_parameters,
          last_updated: System.system_time(:second)
        }
        
        {:ok, updated_state}
    end
  end
  
  def add_execution_record(state, execution_record) do
    # Add to history with size limit
    new_history = :queue.in(execution_record, state.execution_history)
    
    # Keep only last 1000 executions
    trimmed_history = if :queue.len(new_history) > 1000 do
      {_dropped, trimmed} = :queue.out(new_history)
      trimmed
    else
      new_history
    end
    
    %{state |
      execution_history: trimmed_history,
      last_updated: System.system_time(:second)
    }
  end
  
  def update_performance_metrics(state, execution_record) do
    current_metrics = state.performance_metrics
    
    # Update execution count
    new_execution_count = Map.get(current_metrics, :execution_count, 0) + 1
    
    # Update average execution time
    current_avg = Map.get(current_metrics, :avg_execution_time, 0)
    new_avg = (current_avg * (new_execution_count - 1) + execution_record.duration) / new_execution_count
    
    # Update success rate
    success_count = Map.get(current_metrics, :success_count, 0)
    new_success_count = if match?({:ok, _}, execution_record.result) do
      success_count + 1
    else
      success_count
    end
    
    new_success_rate = new_success_count / new_execution_count
    
    new_metrics = Map.merge(current_metrics, %{
      execution_count: new_execution_count,
      avg_execution_time: new_avg,
      success_count: new_success_count,
      success_rate: new_success_rate,
      last_execution: execution_record.timestamp
    })
    
    %{state |
      performance_metrics: new_metrics,
      last_updated: System.system_time(:second)
    }
  end
  
  defp initialize_performance_metrics do
    %{
      execution_count: 0,
      avg_execution_time: 0,
      success_count: 0,
      success_rate: 0.0,
      last_execution: nil,
      created_at: System.system_time(:second)
    }
  end
end
```

### PARAMETER TRACKING AND MANAGEMENT

**Advanced Parameter Management System:**

```elixir
defmodule AshDSPy.Module.Parameter do
  @moduledoc """
  Parameter management with learning state tracking and optimization.
  """
  
  defstruct [
    :name,
    :type,
    :value,
    :requires_grad,
    :grad,
    :learning_rate,
    :momentum,
    :update_history,
    :constraints,
    :metadata,
    :created_at,
    :updated_at
  ]
  
  def new(name, type, initial_value, opts \\ []) do
    %__MODULE__{
      name: name,
      type: type,
      value: initial_value,
      requires_grad: Keyword.get(opts, :requires_grad, false),
      grad: nil,
      learning_rate: Keyword.get(opts, :learning_rate, 0.01),
      momentum: Keyword.get(opts, :momentum, 0.0),
      update_history: :queue.new(),
      constraints: Keyword.get(opts, :constraints, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      created_at: System.system_time(:second),
      updated_at: System.system_time(:second)
    }
  end
  
  def update_value(parameter, new_value) do
    # Validate constraints
    case validate_constraints(new_value, parameter.constraints) do
      :ok ->
        # Record update in history
        update_record = %{
          old_value: parameter.value,
          new_value: new_value,
          timestamp: System.system_time(:second)
        }
        
        new_history = :queue.in(update_record, parameter.update_history)
        
        # Keep only last 100 updates
        trimmed_history = if :queue.len(new_history) > 100 do
          {_dropped, trimmed} = :queue.out(new_history)
          trimmed
        else
          new_history
        end
        
        updated_parameter = %{parameter |
          value: new_value,
          update_history: trimmed_history,
          updated_at: System.system_time(:second)
        }
        
        {:ok, updated_parameter}
      
      {:error, reason} ->
        {:error, {:constraint_violation, reason}}
    end
  end
  
  def apply_gradient(parameter, gradient) do
    if parameter.requires_grad do
      # Apply gradient with momentum
      current_grad = parameter.grad || 0
      new_grad = parameter.momentum * current_grad + (1 - parameter.momentum) * gradient
      
      # Update value
      new_value = parameter.value - parameter.learning_rate * new_grad
      
      case update_value(parameter, new_value) do
        {:ok, updated_parameter} ->
          {:ok, %{updated_parameter | grad: new_grad}}
        
        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :gradient_not_required}
    end
  end
  
  defp validate_constraints(value, constraints) do
    Enum.reduce_while(constraints, :ok, fn constraint, _acc ->
      case validate_constraint(value, constraint) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
  
  defp validate_constraint(value, constraint) do
    case constraint do
      {:min, min_val} when value >= min_val -> :ok
      {:min, min_val} -> {:error, {:below_minimum, min_val}}
      
      {:max, max_val} when value <= max_val -> :ok
      {:max, max_val} -> {:error, {:above_maximum, max_val}}
      
      {:type, expected_type} ->
        if matches_type?(value, expected_type) do
          :ok
        else
          {:error, {:type_mismatch, expected_type}}
        end
      
      {:custom, validator_func} when is_function(validator_func) ->
        validator_func.(value)
      
      _ ->
        :ok
    end
  end
  
  defp matches_type?(value, type) do
    case type do
      :number -> is_number(value)
      :string -> is_binary(value)
      :boolean -> is_boolean(value)
      :list -> is_list(value)
      :map -> is_map(value)
      _ -> true
    end
  end
end

defmodule AshDSPy.Module.ParameterStore do
  @moduledoc """
  Centralized parameter storage with persistence and sharing capabilities.
  """
  
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Create ETS table for parameter storage
    parameter_table = :ets.new(:parameter_store, [
      :named_table,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    # Create table for shared parameters
    shared_table = :ets.new(:shared_parameters, [
      :named_table,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    state = %{
      parameter_table: parameter_table,
      shared_table: shared_table,
      subscriptions: %{}
    }
    
    {:ok, state}
  end
  
  @doc """
  Store parameter with optional sharing.
  """
  def store_parameter(module_id, parameter_name, parameter, shared \\ false) do
    GenServer.call(__MODULE__, {:store_parameter, module_id, parameter_name, parameter, shared})
  end
  
  @doc """
  Get parameter by module and name.
  """
  def get_parameter(module_id, parameter_name) do
    case :ets.lookup(:parameter_store, {module_id, parameter_name}) do
      [{_key, parameter}] -> {:ok, parameter}
      [] -> {:error, :parameter_not_found}
    end
  end
  
  @doc """
  Subscribe to parameter updates.
  """
  def subscribe_to_parameter(module_id, parameter_name) do
    GenServer.call(__MODULE__, {:subscribe, module_id, parameter_name, self()})
  end
  
  def handle_call({:store_parameter, module_id, parameter_name, parameter, shared}, _from, state) do
    key = {module_id, parameter_name}
    
    # Store in main table
    :ets.insert(:parameter_store, {key, parameter})
    
    # Store in shared table if shared
    if shared do
      :ets.insert(:shared_parameters, {parameter_name, parameter, module_id})
    end
    
    # Notify subscribers
    notify_subscribers(key, parameter, state.subscriptions)
    
    {:reply, :ok, state}
  end
  
  def handle_call({:subscribe, module_id, parameter_name, subscriber_pid}, _from, state) do
    key = {module_id, parameter_name}
    current_subscribers = Map.get(state.subscriptions, key, [])
    new_subscribers = [subscriber_pid | current_subscribers]
    
    new_subscriptions = Map.put(state.subscriptions, key, new_subscribers)
    
    {:reply, :ok, %{state | subscriptions: new_subscriptions}}
  end
  
  defp notify_subscribers(key, parameter, subscriptions) do
    case Map.get(subscriptions, key) do
      nil -> :ok
      subscribers ->
        Enum.each(subscribers, fn subscriber_pid ->
          send(subscriber_pid, {:parameter_updated, key, parameter})
        end)
    end
  end
end
```

### MODULE REGISTRY AND MANAGEMENT

**Dynamic Module Discovery and Management:**

```elixir
defmodule AshDSPy.Module.Registry do
  @moduledoc """
  Module registry for discovery, management, and lifecycle coordination.
  """
  
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Create registry table
    registry_table = :ets.new(:module_registry, [
      :named_table,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    # Create dependency tracking table
    dependency_table = :ets.new(:module_dependencies, [
      :named_table,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    state = %{
      registry_table: registry_table,
      dependency_table: dependency_table,
      module_supervisors: %{},
      hot_swap_queue: :queue.new()
    }
    
    {:ok, state}
  end
  
  @doc """
  Register a module instance.
  """
  def register_module(module_id, module_type, pid) do
    GenServer.call(__MODULE__, {:register_module, module_id, module_type, pid})
  end
  
  @doc """
  Get module instance by ID.
  """
  def get_module(module_id) do
    case :ets.lookup(:module_registry, module_id) do
      [{^module_id, module_info}] -> {:ok, module_info}
      [] -> {:error, :module_not_found}
    end
  end
  
  @doc """
  List all registered modules.
  """
  def list_modules() do
    :ets.tab2list(:module_registry)
  end
  
  @doc """
  Start a module instance.
  """
  def start_module(module_type, opts \\ []) do
    GenServer.call(__MODULE__, {:start_module, module_type, opts})
  end
  
  @doc """
  Stop a module instance.
  """
  def stop_module(module_id) do
    GenServer.call(__MODULE__, {:stop_module, module_id})
  end
  
  @doc """
  Hot swap module with new version.
  """
  def hot_swap_module(module_id, new_module_type, migration_opts \\ []) do
    GenServer.call(__MODULE__, {:hot_swap_module, module_id, new_module_type, migration_opts})
  end
  
  def handle_call({:register_module, module_id, module_type, pid}, _from, state) do
    # Monitor the module process
    monitor_ref = Process.monitor(pid)
    
    module_info = %{
      module_id: module_id,
      module_type: module_type,
      pid: pid,
      monitor_ref: monitor_ref,
      status: :running,
      registered_at: System.system_time(:second),
      metadata: %{}
    }
    
    :ets.insert(:module_registry, {module_id, module_info})
    
    {:reply, :ok, state}
  end
  
  def handle_call({:start_module, module_type, opts}, _from, state) do
    module_id = generate_module_id()
    
    case start_module_process(module_type, module_id, opts) do
      {:ok, pid} ->
        # Registration will happen when the module starts
        {:reply, {:ok, module_id, pid}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:stop_module, module_id}, _from, state) do
    case :ets.lookup(:module_registry, module_id) do
      [{^module_id, module_info}] ->
        # Stop the module process gracefully
        case stop_module_process(module_info.pid) do
          :ok ->
            :ets.delete(:module_registry, module_id)
            {:reply, :ok, state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      
      [] ->
        {:reply, {:error, :module_not_found}, state}
    end
  end
  
  def handle_call({:hot_swap_module, module_id, new_module_type, migration_opts}, _from, state) do
    case perform_hot_swap(module_id, new_module_type, migration_opts) do
      {:ok, new_pid} ->
        {:reply, {:ok, new_pid}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  # Handle module process crashes
  def handle_info({:DOWN, monitor_ref, :process, pid, reason}, state) do
    # Find the crashed module
    case find_module_by_monitor_ref(monitor_ref) do
      {:ok, module_id, module_info} ->
        Logger.warning("Module #{module_id} crashed: #{inspect(reason)}")
        
        # Update status
        updated_info = %{module_info | status: :crashed, crash_reason: reason}
        :ets.insert(:module_registry, {module_id, updated_info})
        
        # Attempt restart if configured
        maybe_restart_module(module_id, module_info, state)
      
      :not_found ->
        {:noreply, state}
    end
  end
  
  defp start_module_process(module_type, module_id, opts) do
    module_opts = Keyword.put(opts, :module_id, module_id)
    
    case DynamicSupervisor.start_child(
      AshDSPy.Module.DynamicSupervisor,
      {module_type, module_opts}
    ) do
      {:ok, pid} ->
        {:ok, pid}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp stop_module_process(pid) do
    try do
      GenServer.stop(pid, :normal, 5000)
      :ok
    catch
      :exit, _ -> {:error, :stop_timeout}
    end
  end
  
  defp perform_hot_swap(module_id, new_module_type, migration_opts) do
    case :ets.lookup(:module_registry, module_id) do
      [{^module_id, module_info}] ->
        # Get current state
        case GenServer.call(module_info.pid, :get_state) do
          {:ok, current_state} ->
            # Start new module
            new_module_opts = Keyword.merge(migration_opts, [
              module_id: module_id,
              migrate_from: current_state
            ])
            
            case start_module_process(new_module_type, module_id, new_module_opts) do
              {:ok, new_pid} ->
                # Stop old module
                stop_module_process(module_info.pid)
                
                # Update registry
                updated_info = %{module_info |
                  module_type: new_module_type,
                  pid: new_pid,
                  monitor_ref: Process.monitor(new_pid),
                  status: :running,
                  hot_swapped_at: System.system_time(:second)
                }
                
                :ets.insert(:module_registry, {module_id, updated_info})
                
                {:ok, new_pid}
              
              {:error, reason} ->
                {:error, reason}
            end
          
          {:error, reason} ->
            {:error, {:state_migration_failed, reason}}
        end
      
      [] ->
        {:error, :module_not_found}
    end
  end
  
  defp find_module_by_monitor_ref(monitor_ref) do
    case :ets.match(:module_registry, {'$1', %{monitor_ref: monitor_ref}}) do
      [[module_id]] ->
        [{^module_id, module_info}] = :ets.lookup(:module_registry, module_id)
        {:ok, module_id, module_info}
      
      [] ->
        :not_found
    end
  end
  
  defp maybe_restart_module(module_id, module_info, state) do
    restart_policy = Map.get(module_info.metadata, :restart_policy, :temporary)
    
    case restart_policy do
      :permanent ->
        # Always restart
        attempt_module_restart(module_id, module_info)
        
      :transient ->
        # Restart only if crash was abnormal
        if module_info.crash_reason != :normal do
          attempt_module_restart(module_id, module_info)
        end
        
      :temporary ->
        # Never restart
        :ok
    end
    
    {:noreply, state}
  end
  
  defp attempt_module_restart(module_id, module_info) do
    case start_module_process(module_info.module_type, module_id, []) do
      {:ok, new_pid} ->
        Logger.info("Successfully restarted module #{module_id}")
        
        updated_info = %{module_info |
          pid: new_pid,
          monitor_ref: Process.monitor(new_pid),
          status: :running,
          restarted_at: System.system_time(:second)
        }
        
        :ets.insert(:module_registry, {module_id, updated_info})
        
      {:error, reason} ->
        Logger.error("Failed to restart module #{module_id}: #{inspect(reason)}")
    end
  end
  
  defp generate_module_id do
    "module_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
```

## IMPLEMENTATION REQUIREMENTS

### SUCCESS CRITERIA

**Core Module System Must Achieve:**

1. **100% DSPy Compatibility** - All DSPy module patterns supported natively
2. **Fault Tolerance** - Automatic recovery from module crashes with state preservation
3. **Performance Optimization** - Sub-millisecond parameter access with caching
4. **Module Composition** - Complex module hierarchies with dependency management
5. **Hot Swapping** - Zero-downtime module updates and migrations

### PERFORMANCE TARGETS

**Module System Performance:**
- **<1ms** parameter get/set operations
- **<10ms** module startup time
- **<5s** module compilation time
- **>99.9% uptime** with automatic recovery
- **Support for 1000+ modules** simultaneously

### FAULT TOLERANCE REQUIREMENTS

**Module Fault Tolerance:**
- Automatic module restart on crash
- State persistence and recovery
- Dependency cascade handling
- Error isolation between modules
- Graceful degradation strategies

## EXPECTED DELIVERABLES

### PRIMARY DELIVERABLES

1. **Native Module Behavior** - Complete `AshDSPy.Module.Native` with DSL and GenServer integration
2. **Parameter Management** - Advanced parameter tracking with learning state and optimization
3. **Module Registry** - Dynamic discovery, lifecycle management, and hot swapping
4. **State Management** - Comprehensive state persistence and recovery systems
5. **Supervision Integration** - Fault-tolerant supervision trees for module management

### VERIFICATION AND VALIDATION

**Module System Verified:**
- All DSPy module patterns work correctly
- Parameter tracking and updates function properly
- Module composition and dependencies work seamlessly
- Fault tolerance and recovery mechanisms operate correctly
- Performance targets are met under load

This comprehensive module system provides the foundation for complex ML workflows with superior fault tolerance and performance through native Elixir/OTP patterns.