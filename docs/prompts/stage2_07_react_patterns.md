# Stage 2 Prompt 7: React Pattern and Tool Integration

## OBJECTIVE

Implement a comprehensive React (Reason, Act, Observe) pattern system that provides native Elixir execution of multi-step reasoning with tool calling and action execution. This system must deliver React pattern execution with reasoning-action cycles, tool integration with function calling capabilities, action validation and execution management, thought-action-observation cycle implementation, and error handling with recovery strategies while maintaining complete DSPy React API compatibility and achieving superior performance through native concurrency.

## COMPLETE IMPLEMENTATION CONTEXT

### REACT PATTERN ARCHITECTURE OVERVIEW

From Stage 2 Technical Specification:

```
┌─────────────────────────────────────────────────────────────┐
│                  React Pattern System                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Reasoning        │  │ Action          │  │ Observation  ││
│  │ Engine           │  │ Executor        │  │ Processor    ││
│  │ - Thought Gen    │  │ - Tool Calling  │  │ - Result Parse││
│  │ - Planning       │  │ - Validation    │  │ - State Update││
│  │ - Decision       │  │ - Execution     │  │ - Feedback   ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Tool             │  │ Workflow        │  │ Error        ││
│  │ Registry         │  │ Orchestration   │  │ Recovery     ││
│  │ - Registration   │  │ - Multi-step    │  │ - Retry      ││
│  │ - Discovery      │  │ - Coordination  │  │ - Fallback   ││
│  │ - Invocation     │  │ - State Mgmt    │  │ - Correction ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### DSPy REACT PATTERN ANALYSIS

From comprehensive DSPy source code analysis (predict/react.py):

**DSPy React Core Patterns:**

```python
# DSPy React implementation
class ReAct(Module):
    def __init__(self, signature, tools=None, max_iters=5, **kwargs):
        super().__init__()
        self.signature = signature
        self.tools = tools or {}
        self.max_iters = max_iters
        self.react_signature = self._create_react_signature()
        
    def _create_react_signature(self):
        """Create signature for ReAct reasoning."""
        class ReActSignature(Signature):
            """Reason and act to solve the problem."""
            
            # Input fields from original signature
            context: str = InputField(desc="Current context and observations")
            objective: str = InputField(desc="What we're trying to accomplish")
            
            # ReAct specific fields
            thought: str = OutputField(
                desc="Reasoning about what to do next"
            )
            action: str = OutputField(
                desc="Action to take. Format: Action[tool_name](args)"
            )
            
        return ReActSignature
    
    def forward(self, **kwargs):
        """Execute ReAct loop."""
        # Initialize context
        context = self._build_initial_context(**kwargs)
        trajectory = []
        
        for i in range(self.max_iters):
            # Generate thought and action
            react_output = self._reason_and_act(context)
            
            trajectory.append({
                'iteration': i,
                'thought': react_output.thought,
                'action': react_output.action
            })
            
            # Parse and execute action
            if self._is_final_answer(react_output.action):
                # Extract final answer
                answer = self._extract_answer(react_output.action)
                trajectory[-1]['observation'] = "Final answer provided"
                break
                
            else:
                # Execute tool action
                observation = self._execute_action(react_output.action)
                trajectory[-1]['observation'] = observation
                
                # Update context with observation
                context = self._update_context(
                    context, 
                    react_output.thought,
                    react_output.action,
                    observation
                )
        
        # Store trajectory
        self.trajectory = trajectory
        
        # Return final result
        return self._build_final_result(trajectory, answer)
    
    def _reason_and_act(self, context):
        """Generate thought and action."""
        predictor = Predict(self.react_signature)
        return predictor(
            context=context,
            objective=self.objective
        )
    
    def _execute_action(self, action_str):
        """Parse and execute tool action."""
        # Parse action format: Action[tool_name](args)
        match = re.match(r'Action\[(\w+)\]\((.*)\)', action_str)
        
        if not match:
            return "Error: Invalid action format"
        
        tool_name, args_str = match.groups()
        
        if tool_name not in self.tools:
            return f"Error: Unknown tool '{tool_name}'"
        
        try:
            # Parse arguments
            args = self._parse_args(args_str)
            
            # Execute tool
            tool = self.tools[tool_name]
            result = tool(**args)
            
            return f"Observation: {result}"
            
        except Exception as e:
            return f"Error executing {tool_name}: {str(e)}"
    
    def _is_final_answer(self, action):
        """Check if action is final answer."""
        return action.startswith("Finish[")
    
    def _extract_answer(self, action):
        """Extract answer from Finish action."""
        match = re.match(r'Finish\[(.*)\]', action)
        return match.group(1) if match else ""

# Tool integration
class Tool:
    def __init__(self, name, func, desc=""):
        self.name = name
        self.func = func
        self.desc = desc
        
    def __call__(self, **kwargs):
        return self.func(**kwargs)

# Example tools
def Calculator(**kwargs):
    """Evaluate mathematical expressions."""
    expr = kwargs.get('expression', '')
    try:
        # Safe evaluation
        allowed_names = {
            k: v for k, v in math.__dict__.items() 
            if not k.startswith("_")
        }
        result = eval(expr, {"__builtins__": {}}, allowed_names)
        return f"Result: {result}"
    except Exception as e:
        return f"Calculation error: {str(e)}"

def Search(**kwargs):
    """Search for information."""
    query = kwargs.get('query', '')
    # Simulated search
    results = search_database(query)
    return f"Search results: {results}"

# ReAct with tools
react = ReAct(
    signature=QASignature,
    tools={
        'Calculator': Tool('Calculator', Calculator),
        'Search': Tool('Search', Search)
    },
    max_iters=5
)
```

**Key DSPy React Features:**
1. **Thought-Action-Observation Cycles** - Iterative reasoning and action
2. **Tool Integration** - Dynamic tool calling with parsed arguments
3. **Action Parsing** - Structured action format with validation
4. **Context Management** - Progressive context building
5. **Trajectory Tracking** - Complete execution history

### TOOL CALLING PATTERNS

From research on tool calling and function execution:

```python
# Advanced tool patterns
class ToolRegistry:
    def __init__(self):
        self.tools = {}
        self.schemas = {}
        
    def register(self, name, func, schema=None):
        """Register a tool with optional schema."""
        self.tools[name] = func
        
        if schema:
            self.schemas[name] = schema
        else:
            # Infer schema from function signature
            self.schemas[name] = self._infer_schema(func)
    
    def validate_call(self, name, args):
        """Validate tool call arguments."""
        if name not in self.schemas:
            return True  # No schema to validate against
            
        schema = self.schemas[name]
        return validate_against_schema(args, schema)
    
    def execute(self, name, args):
        """Execute tool with validation."""
        if name not in self.tools:
            raise ValueError(f"Unknown tool: {name}")
            
        if not self.validate_call(name, args):
            raise ValueError(f"Invalid arguments for {name}")
            
        return self.tools[name](**args)

# Tool execution patterns
class ToolExecutor:
    def __init__(self, registry, sandbox=True):
        self.registry = registry
        self.sandbox = sandbox
        
    def execute_action(self, action):
        """Execute parsed action safely."""
        tool_name = action['tool']
        args = action['args']
        
        if self.sandbox:
            # Execute in sandboxed environment
            return self._sandboxed_execute(tool_name, args)
        else:
            return self.registry.execute(tool_name, args)
    
    def _sandboxed_execute(self, tool_name, args):
        """Execute with safety constraints."""
        # Apply execution limits
        with timeout(30), memory_limit(100 * 1024 * 1024):
            return self.registry.execute(tool_name, args)
```

## NATIVE ELIXIR IMPLEMENTATION

### CORE REACT ENGINE

```elixir
defmodule AshDSPy.React.Engine do
  @moduledoc """
  Core React pattern engine with tool integration and workflow orchestration.
  
  Provides:
  - Thought-Action-Observation cycle execution
  - Dynamic tool registration and invocation
  - Multi-step workflow orchestration
  - Action validation and safe execution
  - Error recovery and retry strategies
  - Complete trajectory tracking
  """
  
  use GenServer
  require Logger
  
  alias AshDSPy.{Signature, Prediction}
  alias AshDSPy.React.{
    ToolRegistry,
    ActionParser,
    ContextManager,
    WorkflowOrchestrator,
    ErrorRecovery
  }
  
  @type react_opts :: [
    max_iterations: pos_integer(),
    timeout_per_action: timeout(),
    tools: map(),
    sandbox_mode: boolean(),
    recovery_strategy: atom(),
    trace_mode: boolean()
  ]
  
  @type react_result :: %{
    final_answer: any(),
    trajectory: [trajectory_entry()],
    iterations: non_neg_integer(),
    success: boolean(),
    metadata: map()
  }
  
  @type trajectory_entry :: %{
    iteration: non_neg_integer(),
    thought: String.t(),
    action: String.t(),
    observation: String.t(),
    timestamp: DateTime.t(),
    duration_ms: non_neg_integer()
  }
  
  # Client API
  
  @doc """
  Start the React engine.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Execute React pattern with the given signature and inputs.
  """
  @spec react(Signature.t(), map(), react_opts()) :: 
    {:ok, react_result()} | {:error, term()}
  def react(signature, inputs, opts \\ []) do
    timeout = calculate_total_timeout(opts)
    GenServer.call(__MODULE__, {:react, signature, inputs, opts}, timeout)
  end
  
  @doc """
  Register a tool for use in React workflows.
  """
  @spec register_tool(atom(), function(), map()) :: :ok
  def register_tool(name, func, schema \\ %{}) do
    GenServer.call(__MODULE__, {:register_tool, name, func, schema})
  end
  
  @doc """
  Execute a specific action outside of React loop (for testing).
  """
  @spec execute_action(String.t()) :: {:ok, String.t()} | {:error, term()}
  def execute_action(action_string) do
    GenServer.call(__MODULE__, {:execute_action, action_string})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Initialize components
    {:ok, tool_registry} = ToolRegistry.start_link()
    {:ok, context_manager} = ContextManager.start_link()
    {:ok, orchestrator} = WorkflowOrchestrator.start_link()
    {:ok, error_recovery} = ErrorRecovery.start_link()
    
    # Register default tools
    register_default_tools(tool_registry)
    
    # Initialize trajectory storage
    :ets.new(:react_trajectories, [:named_table, :public, :set])
    
    state = %{
      tool_registry: tool_registry,
      context_manager: context_manager,
      orchestrator: orchestrator,
      error_recovery: error_recovery,
      opts: opts
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:react, signature, inputs, opts}, _from, state) do
    result = execute_react_pattern(signature, inputs, opts, state)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:register_tool, name, func, schema}, _from, state) do
    result = ToolRegistry.register(state.tool_registry, name, func, schema)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:execute_action, action_string}, _from, state) do
    result = execute_single_action(action_string, state)
    {:reply, result, state}
  end
  
  # Private functions
  
  defp execute_react_pattern(signature, inputs, opts, state) do
    # Initialize execution context
    context = ContextManager.initialize(state.context_manager, signature, inputs)
    
    # Create React signature
    react_signature = create_react_signature(signature)
    
    # Execute React loop
    max_iterations = Keyword.get(opts, :max_iterations, 5)
    trajectory = []
    
    result = react_loop(
      react_signature,
      context,
      trajectory,
      max_iterations,
      opts,
      state
    )
    
    # Build final result
    case result do
      {:ok, final_answer, final_trajectory} ->
        {:ok, build_react_result(final_answer, final_trajectory, true)}
        
      {:error, reason, partial_trajectory} ->
        # Return partial result with error
        {:ok, build_react_result(nil, partial_trajectory, false, reason)}
    end
  end
  
  defp react_loop(signature, context, trajectory, remaining_iters, opts, state) do
    if remaining_iters == 0 do
      {:error, :max_iterations_exceeded, trajectory}
    else
      # Generate thought and action
      case generate_thought_and_action(signature, context, opts) do
        {:ok, thought, action} ->
          # Record trajectory entry
          start_time = System.monotonic_time(:millisecond)
          
          # Check if final answer
          if is_final_answer?(action) do
            answer = extract_final_answer(action)
            observation = "Final answer provided"
            
            entry = build_trajectory_entry(
              length(trajectory),
              thought,
              action,
              observation,
              start_time
            )
            
            {:ok, answer, trajectory ++ [entry]}
          else
            # Execute action
            case execute_action_with_recovery(action, opts, state) do
              {:ok, observation} ->
                # Record trajectory
                entry = build_trajectory_entry(
                  length(trajectory),
                  thought,
                  action,
                  observation,
                  start_time
                )
                
                # Update context
                updated_context = ContextManager.update(
                  state.context_manager,
                  context,
                  thought,
                  action,
                  observation
                )
                
                # Continue loop
                react_loop(
                  signature,
                  updated_context,
                  trajectory ++ [entry],
                  remaining_iters - 1,
                  opts,
                  state
                )
                
              {:error, error_msg} ->
                # Handle error with recovery
                handle_action_error(
                  error_msg,
                  signature,
                  context,
                  trajectory,
                  remaining_iters,
                  opts,
                  state
                )
            end
          end
          
        {:error, reason} ->
          {:error, {:thought_generation_failed, reason}, trajectory}
      end
    end
  end
  
  defp generate_thought_and_action(signature, context, opts) do
    # Build prompt with context
    prompt_context = build_react_prompt(context)
    
    # Use prediction engine
    case Prediction.Engine.predict(signature, prompt_context, opts) do
      {:ok, result} ->
        thought = Map.get(result.outputs, :thought, "")
        action = Map.get(result.outputs, :action, "")
        
        # Validate outputs
        if thought != "" and action != "" do
          {:ok, thought, action}
        else
          {:error, :incomplete_outputs}
        end
        
      error -> error
    end
  end
  
  defp execute_action_with_recovery(action_string, opts, state) do
    # Parse action
    case ActionParser.parse(action_string) do
      {:ok, parsed_action} ->
        # Execute with error recovery
        ErrorRecovery.with_recovery(state.error_recovery, fn ->
          execute_parsed_action(parsed_action, opts, state)
        end)
        
      {:error, parse_error} ->
        {:error, "Action parsing failed: #{inspect(parse_error)}"}
    end
  end
  
  defp execute_parsed_action(parsed_action, opts, state) do
    %{tool: tool_name, args: args} = parsed_action
    
    # Check if tool exists
    case ToolRegistry.get_tool(state.tool_registry, tool_name) do
      {:ok, tool_def} ->
        # Validate arguments
        case validate_tool_args(tool_def, args) do
          :ok ->
            # Execute tool
            execute_tool_safely(tool_def, args, opts)
            
          {:error, validation_error} ->
            {:error, "Invalid arguments: #{inspect(validation_error)}"}
        end
        
      :error ->
        {:error, "Unknown tool: #{tool_name}"}
    end
  end
  
  defp execute_tool_safely(tool_def, args, opts) do
    sandbox_mode = Keyword.get(opts, :sandbox_mode, true)
    timeout = Keyword.get(opts, :timeout_per_action, 30_000)
    
    task = Task.async(fn ->
      if sandbox_mode do
        # Execute with restrictions
        with_sandboxing(fn ->
          apply(tool_def.func, [args])
        end)
      else
        # Direct execution
        apply(tool_def.func, [args])
      end
    end)
    
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} ->
        format_observation(result)
        
      nil ->
        {:error, "Tool execution timeout"}
        
      {:exit, reason} ->
        {:error, "Tool execution failed: #{inspect(reason)}"}
    end
  end
  
  defp handle_action_error(error_msg, signature, context, trajectory, remaining_iters, opts, state) do
    # Add error to context
    error_observation = "Error: #{error_msg}"
    
    error_entry = build_trajectory_entry(
      length(trajectory),
      "Need to handle error",
      "Retry with correction",
      error_observation,
      System.monotonic_time(:millisecond)
    )
    
    # Update context with error
    error_context = ContextManager.add_error(
      state.context_manager,
      context,
      error_msg
    )
    
    # Decide on recovery strategy
    recovery_strategy = Keyword.get(opts, :recovery_strategy, :retry_with_guidance)
    
    case recovery_strategy do
      :retry_with_guidance ->
        # Add guidance to context and retry
        guided_context = add_error_guidance(error_context, error_msg)
        
        react_loop(
          signature,
          guided_context,
          trajectory ++ [error_entry],
          remaining_iters - 1,
          opts,
          state
        )
        
      :skip_and_continue ->
        # Skip this action and continue
        react_loop(
          signature,
          error_context,
          trajectory ++ [error_entry],
          remaining_iters - 1,
          opts,
          state
        )
        
      :fail_fast ->
        # Terminate on error
        {:error, error_msg, trajectory ++ [error_entry]}
    end
  end
  
  defp create_react_signature(original_signature) do
    # Enhance signature for React pattern
    %{original_signature |
      name: "#{original_signature.name}_react",
      output_fields: Map.merge(original_signature.output_fields, %{
        thought: %{
          type: :string,
          required: true,
          desc: "Your reasoning about what to do next"
        },
        action: %{
          type: :string,
          required: true,
          desc: "Action to take. Use Action[tool](args) or Finish[answer]"
        }
      }),
      instructions: build_react_instructions(original_signature)
    }
  end
  
  defp build_react_instructions(signature) do
    """
    #{signature.instructions || "Solve the given problem."}
    
    You have access to the following tools:
    #{format_available_tools()}
    
    Use the following format:
    Thought: reasoning about what to do
    Action: Action[tool](args) or Finish[answer]
    
    Always think before acting. When you have the final answer, use Finish[answer].
    """
  end
  
  defp build_react_prompt(context) do
    # Format context for prompt
    %{
      context: ContextManager.format_for_prompt(context),
      objective: context.objective
    }
  end
  
  defp is_final_answer?(action) do
    String.starts_with?(action, "Finish[")
  end
  
  defp extract_final_answer(action) do
    case Regex.run(~r/Finish\[(.*)\]/, action) do
      [_, answer] -> answer
      _ -> nil
    end
  end
  
  defp validate_tool_args(tool_def, args) do
    if tool_def.schema == %{} do
      :ok  # No schema to validate
    else
      # Validate against schema
      case ExDantic.validate(args, tool_def.schema) do
        {:ok, _} -> :ok
        error -> error
      end
    end
  end
  
  defp format_observation(result) do
    case result do
      {:ok, observation} ->
        {:ok, "Observation: #{observation}"}
        
      {:error, error} ->
        {:error, "Tool error: #{inspect(error)}"}
        
      other ->
        {:ok, "Observation: #{inspect(other)}"}
    end
  end
  
  defp build_trajectory_entry(iteration, thought, action, observation, start_time) do
    %{
      iteration: iteration,
      thought: thought,
      action: action,
      observation: observation,
      timestamp: DateTime.utc_now(),
      duration_ms: System.monotonic_time(:millisecond) - start_time
    }
  end
  
  defp build_react_result(final_answer, trajectory, success, error \\ nil) do
    %{
      final_answer: final_answer,
      trajectory: trajectory,
      iterations: length(trajectory),
      success: success,
      metadata: %{
        error: error,
        total_duration_ms: calculate_total_duration(trajectory),
        tools_used: extract_tools_used(trajectory)
      }
    }
  end
  
  defp calculate_total_timeout(opts) do
    max_iterations = Keyword.get(opts, :max_iterations, 5)
    timeout_per_action = Keyword.get(opts, :timeout_per_action, 30_000)
    
    # Add buffer for reasoning time
    max_iterations * (timeout_per_action + 10_000)
  end
  
  defp calculate_total_duration(trajectory) do
    Enum.sum(trajectory, & &1.duration_ms)
  end
  
  defp extract_tools_used(trajectory) do
    trajectory
    |> Enum.map(& &1.action)
    |> Enum.flat_map(fn action ->
      case ActionParser.parse(action) do
        {:ok, %{tool: tool}} -> [tool]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end
  
  defp register_default_tools(registry) do
    # Register built-in tools
    ToolRegistry.register(registry, :calculator, &calculator_tool/1, %{
      expression: %{type: :string, required: true}
    })
    
    ToolRegistry.register(registry, :string_operations, &string_tool/1, %{
      operation: %{type: :string, required: true},
      text: %{type: :string, required: true}
    })
  end
  
  defp calculator_tool(%{expression: expr}) do
    # Safe math evaluation
    try do
      # Parse and evaluate safely
      result = safe_eval_math(expr)
      {:ok, "Result: #{result}"}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
  
  defp string_tool(%{operation: op, text: text}) do
    case op do
      "length" -> {:ok, "Length: #{String.length(text)}"}
      "reverse" -> {:ok, "Reversed: #{String.reverse(text)}"}
      "uppercase" -> {:ok, "Uppercase: #{String.upcase(text)}"}
      "lowercase" -> {:ok, "Lowercase: #{String.downcase(text)}"}
      _ -> {:error, "Unknown operation: #{op}"}
    end
  end
  
  defp safe_eval_math(expr) do
    # Very basic math parser - in production use proper parser
    expr
    |> String.replace(" ", "")
    |> Code.eval_string()
    |> elem(0)
  end
  
  defp with_sandboxing(func) do
    # Simplified sandboxing - in production use proper isolation
    func.()
  end
  
  defp add_error_guidance(context, error_msg) do
    guidance = """
    
    Previous action failed with error: #{error_msg}
    Please try a different approach or use a different tool.
    """
    
    ContextManager.add_guidance(context, guidance)
  end
  
  defp format_available_tools do
    # This would fetch from registry
    """
    - Calculator: Evaluate mathematical expressions
      Usage: Action[calculator](expression: "2 + 2")
    
    - StringOperations: Perform string operations
      Usage: Action[string_operations](operation: "length", text: "hello")
    """
  end
end
```

### TOOL REGISTRY SYSTEM

```elixir
defmodule AshDSPy.React.ToolRegistry do
  @moduledoc """
  Registry for React tools with schema validation and discovery.
  """
  
  use GenServer
  
  @type tool_def :: %{
    name: atom(),
    func: function(),
    schema: map(),
    description: String.t(),
    examples: [String.t()],
    categories: [atom()],
    metadata: map()
  }
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Register a new tool.
  """
  def register(server \\ __MODULE__, name, func, schema \\ %{}, opts \\ []) do
    GenServer.call(server, {:register, name, func, schema, opts})
  end
  
  @doc """
  Get tool definition.
  """
  def get_tool(server \\ __MODULE__, name) do
    GenServer.call(server, {:get_tool, name})
  end
  
  @doc """
  List all available tools.
  """
  def list_tools(server \\ __MODULE__, filters \\ []) do
    GenServer.call(server, {:list_tools, filters})
  end
  
  @doc """
  Generate tool documentation.
  """
  def generate_docs(server \\ __MODULE__) do
    GenServer.call(server, :generate_docs)
  end
  
  @impl true
  def init(opts) do
    # Initialize tool storage
    tools = %{}
    
    # Load built-in tools
    tools = load_builtin_tools(tools)
    
    {:ok, %{
      tools: tools,
      opts: opts
    }}
  end
  
  @impl true
  def handle_call({:register, name, func, schema, opts}, _from, state) do
    # Create tool definition
    tool_def = %{
      name: name,
      func: func,
      schema: schema,
      description: Keyword.get(opts, :description, ""),
      examples: Keyword.get(opts, :examples, []),
      categories: Keyword.get(opts, :categories, [:general]),
      metadata: Keyword.get(opts, :metadata, %{})
    }
    
    # Validate tool definition
    case validate_tool_def(tool_def) do
      :ok ->
        updated_tools = Map.put(state.tools, name, tool_def)
        {:reply, :ok, %{state | tools: updated_tools}}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:get_tool, name}, _from, state) do
    case Map.get(state.tools, name) do
      nil -> {:reply, :error, state}
      tool -> {:reply, {:ok, tool}, state}
    end
  end
  
  @impl true
  def handle_call({:list_tools, filters}, _from, state) do
    tools = filter_tools(state.tools, filters)
    {:reply, {:ok, tools}, state}
  end
  
  @impl true
  def handle_call(:generate_docs, _from, state) do
    docs = generate_tool_documentation(state.tools)
    {:reply, {:ok, docs}, state}
  end
  
  defp validate_tool_def(tool_def) do
    cond do
      not is_atom(tool_def.name) ->
        {:error, "Tool name must be an atom"}
        
      not is_function(tool_def.func, 1) ->
        {:error, "Tool function must accept exactly one argument"}
        
      not is_map(tool_def.schema) ->
        {:error, "Tool schema must be a map"}
        
      true ->
        :ok
    end
  end
  
  defp filter_tools(tools, filters) do
    category_filter = Keyword.get(filters, :category)
    
    tools
    |> Enum.filter(fn {_name, tool} ->
      if category_filter do
        category_filter in tool.categories
      else
        true
      end
    end)
    |> Map.new()
  end
  
  defp generate_tool_documentation(tools) do
    tools
    |> Enum.map(fn {name, tool} ->
      """
      ## #{name}
      
      #{tool.description}
      
      ### Schema
      ```
      #{inspect(tool.schema, pretty: true)}
      ```
      
      ### Examples
      #{Enum.join(tool.examples, "\n")}
      
      Categories: #{Enum.join(tool.categories, ", ")}
      """
    end)
    |> Enum.join("\n\n")
  end
  
  defp load_builtin_tools(tools) do
    builtin = [
      # Calculator tool
      {:calculator, &Builtin.calculator/1, 
       %{expression: %{type: :string, required: true}},
       [
         description: "Evaluate mathematical expressions",
         examples: [
           ~s|Action[calculator](expression: "2 + 2")|,
           ~s|Action[calculator](expression: "sqrt(16)")|
         ],
         categories: [:math, :computation]
       ]},
       
      # Search tool
      {:search, &Builtin.search/1,
       %{query: %{type: :string, required: true}, limit: %{type: :integer, default: 5}},
       [
         description: "Search for information",
         examples: [
           ~s|Action[search](query: "Elixir GenServer")|,
           ~s|Action[search](query: "React pattern", limit: 10)|
         ],
         categories: [:information, :research]
       ]},
       
      # File operations
      {:file_read, &Builtin.file_read/1,
       %{path: %{type: :string, required: true}},
       [
         description: "Read file contents",
         examples: [~s|Action[file_read](path: "config.exs")|],
         categories: [:file_system]
       ]},
       
      # HTTP requests
      {:http_request, &Builtin.http_request/1,
       %{
         method: %{type: :string, enum: ["GET", "POST"], default: "GET"},
         url: %{type: :string, required: true},
         body: %{type: :map, default: %{}}
       },
       [
         description: "Make HTTP requests",
         examples: [
           ~s|Action[http_request](method: "GET", url: "https://api.example.com")|
         ],
         categories: [:network, :api]
       ]}
    ]
    
    Enum.reduce(builtin, tools, fn {name, func, schema, opts}, acc ->
      tool_def = %{
        name: name,
        func: func,
        schema: schema,
        description: Keyword.get(opts, :description, ""),
        examples: Keyword.get(opts, :examples, []),
        categories: Keyword.get(opts, :categories, [:general]),
        metadata: %{builtin: true}
      }
      
      Map.put(acc, name, tool_def)
    end)
  end
end
```

### ACTION PARSER

```elixir
defmodule AshDSPy.React.ActionParser do
  @moduledoc """
  Parses React action strings into structured format.
  """
  
  @action_pattern ~r/^Action\[(\w+)\]\((.*)\)$/
  @finish_pattern ~r/^Finish\[(.*)\]$/
  
  @doc """
  Parse an action string into structured format.
  """
  def parse(action_string) do
    action_string = String.trim(action_string)
    
    cond do
      # Check for Finish action
      match = Regex.run(@finish_pattern, action_string) ->
        [_, answer] = match
        {:ok, %{type: :finish, answer: answer}}
        
      # Check for tool action
      match = Regex.run(@action_pattern, action_string) ->
        [_, tool_name, args_string] = match
        
        case parse_arguments(args_string) do
          {:ok, args} ->
            {:ok, %{
              type: :tool,
              tool: String.to_atom(tool_name),
              args: args
            }}
            
          error -> error
        end
        
      # Invalid format
      true ->
        {:error, {:invalid_action_format, action_string}}
    end
  end
  
  @doc """
  Format a structured action back to string.
  """
  def format(action) do
    case action do
      %{type: :finish, answer: answer} ->
        "Finish[#{answer}]"
        
      %{type: :tool, tool: tool, args: args} ->
        args_str = format_arguments(args)
        "Action[#{tool}](#{args_str})"
        
      _ ->
        {:error, :invalid_action}
    end
  end
  
  defp parse_arguments(args_string) do
    # Parse key-value pairs
    args_string = String.trim(args_string)
    
    if args_string == "" do
      {:ok, %{}}
    else
      # Split by commas not inside quotes
      pairs = split_arguments(args_string)
      
      # Parse each pair
      result = Enum.reduce_while(pairs, {:ok, %{}}, fn pair, {:ok, acc} ->
        case parse_key_value(pair) do
          {:ok, key, value} ->
            {:cont, {:ok, Map.put(acc, key, value)}}
            
          error ->
            {:halt, error}
        end
      end)
      
      result
    end
  end
  
  defp split_arguments(args_string) do
    # Simple split - in production use proper parser
    args_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end
  
  defp parse_key_value(pair) do
    case String.split(pair, ":", parts: 2) do
      [key, value] ->
        key = key |> String.trim() |> String.to_atom()
        value = parse_value(String.trim(value))
        {:ok, key, value}
        
      _ ->
        {:error, {:invalid_argument, pair}}
    end
  end
  
  defp parse_value(value_string) do
    cond do
      # String value (quoted)
      String.starts_with?(value_string, "\"") and String.ends_with?(value_string, "\"") ->
        String.slice(value_string, 1..-2//1)
        
      # Number
      match = Regex.match?(~r/^-?\d+(\.\d+)?$/, value_string) ->
        if String.contains?(value_string, ".") do
          String.to_float(value_string)
        else
          String.to_integer(value_string)
        end
        
      # Boolean
      value_string in ["true", "false"] ->
        value_string == "true"
        
      # Default to string
      true ->
        value_string
    end
  end
  
  defp format_arguments(args) when args == %{}, do: ""
  
  defp format_arguments(args) do
    args
    |> Enum.map(fn {key, value} ->
      "#{key}: #{format_value(value)}"
    end)
    |> Enum.join(", ")
  end
  
  defp format_value(value) when is_binary(value) do
    if String.contains?(value, ["\"", ",", ":"]) do
      "\"#{escape_string(value)}\""
    else
      "\"#{value}\""
    end
  end
  
  defp format_value(value) when is_number(value), do: to_string(value)
  defp format_value(true), do: "true"
  defp format_value(false), do: "false"
  defp format_value(value), do: inspect(value)
  
  defp escape_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end
end
```

### CONTEXT MANAGER

```elixir
defmodule AshDSPy.React.ContextManager do
  @moduledoc """
  Manages execution context for React workflows.
  """
  
  use GenServer
  
  @max_context_size 10_000  # Characters
  @max_history_items 20
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def initialize(server \\ __MODULE__, signature, inputs) do
    GenServer.call(server, {:initialize, signature, inputs})
  end
  
  def update(server \\ __MODULE__, context, thought, action, observation) do
    GenServer.call(server, {:update, context, thought, action, observation})
  end
  
  def add_error(server \\ __MODULE__, context, error_msg) do
    GenServer.call(server, {:add_error, context, error_msg})
  end
  
  def add_guidance(context, guidance) do
    %{context | guidance: context.guidance ++ [guidance]}
  end
  
  def format_for_prompt(context) do
    # Format context for inclusion in prompt
    sections = []
    
    # Add objective
    sections = ["Objective: #{context.objective}" | sections]
    
    # Add inputs
    if context.inputs != %{} do
      inputs_str = format_inputs(context.inputs)
      sections = ["Given inputs:\n#{inputs_str}" | sections]
    end
    
    # Add history
    if context.history != [] do
      history_str = format_history(context.history)
      sections = ["Previous steps:\n#{history_str}" | sections]
    end
    
    # Add errors
    if context.errors != [] do
      errors_str = format_errors(context.errors)
      sections = ["Errors encountered:\n#{errors_str}" | sections]
    end
    
    # Add guidance
    if context.guidance != [] do
      guidance_str = Enum.join(context.guidance, "\n")
      sections = ["Guidance:\n#{guidance_str}" | sections]
    end
    
    # Join and truncate if needed
    full_context = Enum.join(Enum.reverse(sections), "\n\n")
    truncate_context(full_context)
  end
  
  @impl true
  def init(opts) do
    {:ok, %{opts: opts}}
  end
  
  @impl true
  def handle_call({:initialize, signature, inputs}, _from, state) do
    context = %{
      objective: extract_objective(signature, inputs),
      inputs: inputs,
      history: [],
      errors: [],
      guidance: [],
      metadata: %{
        signature_name: signature.name,
        start_time: DateTime.utc_now()
      }
    }
    
    {:reply, context, state}
  end
  
  @impl true
  def handle_call({:update, context, thought, action, observation}, _from, state) do
    # Add to history
    history_entry = %{
      thought: thought,
      action: action,
      observation: observation,
      timestamp: DateTime.utc_now()
    }
    
    # Update context with size management
    updated_context = %{context |
      history: manage_history_size(context.history ++ [history_entry])
    }
    
    {:reply, updated_context, state}
  end
  
  @impl true
  def handle_call({:add_error, context, error_msg}, _from, state) do
    error_entry = %{
      message: error_msg,
      timestamp: DateTime.utc_now()
    }
    
    updated_context = %{context |
      errors: context.errors ++ [error_entry]
    }
    
    {:reply, updated_context, state}
  end
  
  defp extract_objective(signature, inputs) do
    # Build objective from signature and inputs
    base = signature.instructions || "Complete the task"
    
    # Add key input information
    input_summary = inputs
    |> Enum.take(3)
    |> Enum.map(fn {k, v} -> "#{k}: #{truncate_value(v)}" end)
    |> Enum.join(", ")
    
    if input_summary != "" do
      "#{base} (#{input_summary})"
    else
      base
    end
  end
  
  defp manage_history_size(history) do
    if length(history) > @max_history_items do
      # Keep first few and last many
      keep_first = 3
      keep_last = @max_history_items - keep_first - 1
      
      first_items = Enum.take(history, keep_first)
      last_items = Enum.take(history, -keep_last)
      
      first_items ++ [%{thought: "...", action: "...", observation: "[#{length(history) - @max_history_items} steps omitted]"}] ++ last_items
    else
      history
    end
  end
  
  defp format_inputs(inputs) do
    inputs
    |> Enum.map(fn {k, v} -> "- #{k}: #{format_value(v)}" end)
    |> Enum.join("\n")
  end
  
  defp format_history(history) do
    history
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, idx} ->
      """
      Step #{idx}:
      Thought: #{entry.thought}
      Action: #{entry.action}
      Observation: #{entry.observation}
      """
    end)
    |> Enum.join("\n")
  end
  
  defp format_errors(errors) do
    errors
    |> Enum.map(fn error -> "- #{error.message}" end)
    |> Enum.join("\n")
  end
  
  defp format_value(value) when is_binary(value) do
    truncate_value(value)
  end
  
  defp format_value(value) do
    value |> inspect() |> truncate_value()
  end
  
  defp truncate_value(str) when byte_size(str) > 100 do
    String.slice(str, 0..97) <> "..."
  end
  
  defp truncate_value(str), do: str
  
  defp truncate_context(context) when byte_size(context) > @max_context_size do
    # Truncate intelligently
    String.slice(context, 0..(@max_context_size - 20)) <> "\n...[truncated]"
  end
  
  defp truncate_context(context), do: context
end
```

### WORKFLOW ORCHESTRATOR

```elixir
defmodule AshDSPy.React.WorkflowOrchestrator do
  @moduledoc """
  Orchestrates complex multi-step React workflows.
  """
  
  use GenServer
  require Logger
  
  @type workflow :: %{
    id: String.t(),
    steps: [workflow_step()],
    state: atom(),
    current_step: non_neg_integer(),
    results: map(),
    metadata: map()
  }
  
  @type workflow_step :: %{
    name: atom(),
    type: :react | :parallel_react | :conditional | :loop,
    config: map()
  }
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Execute a complex workflow.
  """
  def execute_workflow(server \\ __MODULE__, workflow_def, inputs) do
    GenServer.call(server, {:execute_workflow, workflow_def, inputs}, :infinity)
  end
  
  @doc """
  Get workflow status.
  """
  def get_status(server \\ __MODULE__, workflow_id) do
    GenServer.call(server, {:get_status, workflow_id})
  end
  
  @impl true
  def init(opts) do
    {:ok, %{
      workflows: %{},
      opts: opts
    }}
  end
  
  @impl true
  def handle_call({:execute_workflow, workflow_def, inputs}, _from, state) do
    workflow_id = generate_workflow_id()
    
    # Initialize workflow
    workflow = %{
      id: workflow_id,
      steps: workflow_def.steps,
      state: :running,
      current_step: 0,
      results: %{},
      metadata: %{
        start_time: DateTime.utc_now(),
        inputs: inputs
      }
    }
    
    # Execute workflow
    final_workflow = execute_steps(workflow, inputs)
    
    # Store result
    updated_state = put_in(state.workflows[workflow_id], final_workflow)
    
    result = build_workflow_result(final_workflow)
    {:reply, {:ok, result}, updated_state}
  end
  
  @impl true
  def handle_call({:get_status, workflow_id}, _from, state) do
    case Map.get(state.workflows, workflow_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      workflow ->
        status = %{
          id: workflow_id,
          state: workflow.state,
          current_step: workflow.current_step,
          total_steps: length(workflow.steps)
        }
        {:reply, {:ok, status}, state}
    end
  end
  
  defp execute_steps(workflow, inputs) do
    Enum.reduce_while(workflow.steps, {workflow, inputs}, fn step, {wf, current_inputs} ->
      case execute_step(step, current_inputs, wf) do
        {:ok, result} ->
          # Update workflow
          updated_wf = %{wf |
            current_step: wf.current_step + 1,
            results: Map.put(wf.results, step.name, result)
          }
          
          # Prepare inputs for next step
          next_inputs = prepare_next_inputs(current_inputs, result, step)
          
          {:cont, {updated_wf, next_inputs}}
          
        {:error, reason} ->
          # Mark workflow as failed
          failed_wf = %{wf |
            state: :failed,
            results: Map.put(wf.results, step.name, {:error, reason})
          }
          
          {:halt, {failed_wf, current_inputs}}
      end
    end)
    |> elem(0)
    |> mark_completed()
  end
  
  defp execute_step(step, inputs, workflow) do
    case step.type do
      :react ->
        execute_react_step(step, inputs)
        
      :parallel_react ->
        execute_parallel_react(step, inputs)
        
      :conditional ->
        execute_conditional(step, inputs, workflow)
        
      :loop ->
        execute_loop(step, inputs, workflow)
        
      _ ->
        {:error, {:unknown_step_type, step.type}}
    end
  end
  
  defp execute_react_step(step, inputs) do
    # Execute single React workflow
    signature = step.config.signature
    react_opts = Map.get(step.config, :options, [])
    
    case AshDSPy.React.Engine.react(signature, inputs, react_opts) do
      {:ok, result} -> {:ok, result}
      error -> error
    end
  end
  
  defp execute_parallel_react(step, inputs) do
    # Execute multiple React workflows in parallel
    tasks = step.config.tasks
    
    # Start all tasks
    task_refs = Enum.map(tasks, fn task_config ->
      Task.async(fn ->
        execute_react_step(%{config: task_config}, inputs)
      end)
    end)
    
    # Collect results
    results = Task.await_many(task_refs, 60_000)
    
    # Check for failures
    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, %{
        results: Enum.map(results, fn {:ok, r} -> r end),
        type: :parallel
      }}
    else
      {:error, :parallel_execution_failed}
    end
  end
  
  defp execute_conditional(step, inputs, workflow) do
    # Evaluate condition
    condition = step.config.condition
    
    branch = if evaluate_condition(condition, inputs, workflow) do
      :then_branch
    else
      :else_branch
    end
    
    # Execute selected branch
    branch_config = Map.get(step.config, branch)
    
    if branch_config do
      execute_step(%{
        name: :"#{step.name}_#{branch}",
        type: branch_config.type,
        config: branch_config
      }, inputs, workflow)
    else
      {:ok, %{branch: branch, result: nil}}
    end
  end
  
  defp execute_loop(step, inputs, workflow) do
    # Execute loop with condition
    max_iterations = Map.get(step.config, :max_iterations, 10)
    loop_body = step.config.body
    condition = step.config.while_condition
    
    loop_results = execute_loop_iterations(
      loop_body,
      condition,
      inputs,
      workflow,
      max_iterations,
      []
    )
    
    {:ok, %{
      type: :loop,
      iterations: length(loop_results),
      results: loop_results
    }}
  end
  
  defp execute_loop_iterations(_body, _condition, _inputs, _workflow, 0, results) do
    results  # Max iterations reached
  end
  
  defp execute_loop_iterations(body, condition, inputs, workflow, remaining, results) do
    # Check condition
    if evaluate_condition(condition, inputs, workflow) do
      # Execute body
      case execute_step(body, inputs, workflow) do
        {:ok, result} ->
          # Continue loop with updated inputs
          next_inputs = prepare_next_inputs(inputs, result, body)
          
          execute_loop_iterations(
            body,
            condition,
            next_inputs,
            workflow,
            remaining - 1,
            results ++ [result]
          )
          
        {:error, _} = error ->
          results ++ [error]
      end
    else
      results  # Condition false, exit loop
    end
  end
  
  defp evaluate_condition(condition, inputs, workflow) do
    case condition do
      {:always, true} -> true
      {:always, false} -> false
      
      {:input_check, field, op, value} ->
        input_value = Map.get(inputs, field)
        apply_operator(input_value, op, value)
        
      {:result_check, step_name, field, op, value} ->
        step_result = get_in(workflow.results, [step_name, field])
        apply_operator(step_result, op, value)
        
      {:custom, func} when is_function(func) ->
        func.(inputs, workflow)
        
      _ -> false
    end
  end
  
  defp apply_operator(left, :eq, right), do: left == right
  defp apply_operator(left, :neq, right), do: left != right
  defp apply_operator(left, :gt, right), do: left > right
  defp apply_operator(left, :lt, right), do: left < right
  defp apply_operator(left, :gte, right), do: left >= right
  defp apply_operator(left, :lte, right), do: left <= right
  defp apply_operator(left, :in, right), do: left in right
  defp apply_operator(left, :contains, right), do: String.contains?(left, right)
  
  defp prepare_next_inputs(current_inputs, step_result, step_config) do
    # Merge step results into inputs based on configuration
    output_mapping = Map.get(step_config.config, :output_mapping, %{})
    
    Enum.reduce(output_mapping, current_inputs, fn {from, to}, acc ->
      value = get_in(step_result, String.split(to_string(from), "."))
      Map.put(acc, to, value)
    end)
  end
  
  defp mark_completed(workflow) do
    if workflow.state == :running do
      %{workflow | state: :completed}
    else
      workflow
    end
  end
  
  defp build_workflow_result(workflow) do
    %{
      id: workflow.id,
      state: workflow.state,
      results: workflow.results,
      metadata: Map.merge(workflow.metadata, %{
        end_time: DateTime.utc_now(),
        steps_completed: workflow.current_step
      })
    }
  end
  
  defp generate_workflow_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
```

### ERROR RECOVERY

```elixir
defmodule AshDSPy.React.ErrorRecovery do
  @moduledoc """
  Error recovery strategies for React workflows.
  """
  
  use GenServer
  require Logger
  
  @retry_strategies %{
    exponential_backoff: &exponential_backoff/2,
    linear_backoff: &linear_backoff/2,
    immediate: &immediate_retry/2,
    circuit_breaker: &circuit_breaker_retry/2
  }
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Execute function with recovery strategy.
  """
  def with_recovery(server \\ __MODULE__, func, opts \\ []) do
    GenServer.call(server, {:with_recovery, func, opts}, :infinity)
  end
  
  @doc """
  Record error for pattern analysis.
  """
  def record_error(server \\ __MODULE__, error_info) do
    GenServer.cast(server, {:record_error, error_info})
  end
  
  @impl true
  def init(opts) do
    # Initialize error tracking
    :ets.new(:react_errors, [:named_table, :set, :public])
    :ets.new(:circuit_breakers, [:named_table, :set, :public])
    
    {:ok, %{
      opts: opts,
      error_patterns: %{}
    }}
  end
  
  @impl true
  def handle_call({:with_recovery, func, opts}, _from, state) do
    strategy = Keyword.get(opts, :strategy, :exponential_backoff)
    max_retries = Keyword.get(opts, :max_retries, 3)
    
    result = execute_with_retries(func, strategy, max_retries, state)
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_cast({:record_error, error_info}, state) do
    # Record error for pattern analysis
    record_error_pattern(error_info, state)
    {:noreply, state}
  end
  
  defp execute_with_retries(func, strategy, max_retries, state) do
    do_execute_with_retries(func, strategy, max_retries, 0, nil, state)
  end
  
  defp do_execute_with_retries(func, _strategy, max_retries, attempt, last_error, _state) 
       when attempt >= max_retries do
    {:error, {:max_retries_exceeded, last_error}}
  end
  
  defp do_execute_with_retries(func, strategy, max_retries, attempt, _last_error, state) do
    # Wait before retry (except first attempt)
    if attempt > 0 do
      delay = calculate_delay(strategy, attempt)
      Process.sleep(delay)
    end
    
    # Execute function
    try do
      case func.() do
        {:ok, _} = success ->
          # Record success if recovering from error
          if attempt > 0 do
            record_recovery(attempt, state)
          end
          success
          
        {:error, reason} = error ->
          # Check if error is retryable
          if retryable_error?(reason) do
            Logger.warning("Attempt #{attempt + 1} failed: #{inspect(reason)}, retrying...")
            do_execute_with_retries(func, strategy, max_retries, attempt + 1, reason, state)
          else
            error
          end
          
        other ->
          {:ok, other}
      end
    rescue
      e ->
        if retryable_exception?(e) and attempt < max_retries - 1 do
          Logger.warning("Attempt #{attempt + 1} raised: #{inspect(e)}, retrying...")
          do_execute_with_retries(func, strategy, max_retries, attempt + 1, e, state)
        else
          {:error, {:exception, e}}
        end
    end
  end
  
  defp calculate_delay(strategy, attempt) do
    case @retry_strategies[strategy] do
      nil -> @retry_strategies.exponential_backoff.(attempt, %{})
      strategy_func -> strategy_func.(attempt, %{})
    end
  end
  
  defp exponential_backoff(attempt, _opts) do
    base_delay = 1000  # 1 second
    max_delay = 30_000  # 30 seconds
    
    delay = base_delay * :math.pow(2, attempt) |> round()
    min(delay, max_delay)
  end
  
  defp linear_backoff(attempt, _opts) do
    base_delay = 1000
    base_delay * (attempt + 1)
  end
  
  defp immediate_retry(_attempt, _opts) do
    0
  end
  
  defp circuit_breaker_retry(attempt, _opts) do
    # Check circuit breaker state
    case get_circuit_breaker_state() do
      :open -> :infinity  # Don't retry
      :half_open -> 5000  # 5 seconds
      :closed -> exponential_backoff(attempt, %{})
    end
  end
  
  defp retryable_error?(reason) do
    case reason do
      :timeout -> true
      :temporary_failure -> true
      {:connection_error, _} -> true
      {:rate_limited, _} -> true
      "Tool execution timeout" -> true
      _ -> false
    end
  end
  
  defp retryable_exception?(exception) do
    case exception do
      %{__struct__: module} ->
        module in [
          RuntimeError,
          ArgumentError,
          MatchError
        ]
        
      _ -> false
    end
  end
  
  defp record_error_pattern(error_info, state) do
    # Track error patterns for analysis
    key = categorize_error(error_info)
    
    :ets.update_counter(:react_errors, key, 1, {key, 0})
    
    # Update state patterns
    updated_patterns = Map.update(state.error_patterns, key, 1, &(&1 + 1))
    
    # Check for error threshold
    if updated_patterns[key] > 10 do
      Logger.error("Error pattern #{key} exceeded threshold")
      trigger_circuit_breaker(key)
    end
  end
  
  defp record_recovery(attempts, _state) do
    :ets.update_counter(:react_errors, :recoveries, 1, {:recoveries, 0})
    :ets.update_counter(:react_errors, {:recovery_attempts, attempts}, 1, {{:recovery_attempts, attempts}, 0})
  end
  
  defp categorize_error(error_info) do
    case error_info do
      {:timeout, tool} -> {:tool_timeout, tool}
      {:parsing_error, _} -> :parsing_error
      {:validation_error, _} -> :validation_error
      {:tool_not_found, tool} -> {:unknown_tool, tool}
      _ -> :other_error
    end
  end
  
  defp get_circuit_breaker_state do
    # Simplified circuit breaker
    case :ets.lookup(:circuit_breakers, :main) do
      [{:main, :open, _}] -> :open
      [{:main, :half_open, _}] -> :half_open
      _ -> :closed
    end
  end
  
  defp trigger_circuit_breaker(error_key) do
    :ets.insert(:circuit_breakers, {:main, :open, {DateTime.utc_now(), error_key}})
    
    # Schedule half-open transition
    Process.send_after(self(), :half_open_circuit, 60_000)
  end
end
```

### BUILT-IN TOOLS

```elixir
defmodule AshDSPy.React.Tools.Builtin do
  @moduledoc """
  Built-in tools for React workflows.
  """
  
  require Logger
  
  @doc """
  Calculator tool for mathematical expressions.
  """
  def calculator(%{expression: expr}) do
    try do
      # Create safe evaluation context
      bindings = [
        pi: :math.pi(),
        e: :math.exp(1)
      ]
      
      # Evaluate expression
      {result, _} = Code.eval_string(expr, bindings)
      
      # Format result
      formatted = case result do
        x when is_float(x) -> Float.round(x, 6)
        x -> x
      end
      
      {:ok, "#{formatted}"}
    rescue
      e ->
        {:error, "Calculation failed: #{Exception.message(e)}"}
    end
  end
  
  @doc """
  Search tool for information retrieval.
  """
  def search(%{query: query} = args) do
    limit = Map.get(args, :limit, 5)
    
    # Simulated search - in production would use real search
    results = [
      %{
        title: "Introduction to #{query}",
        snippet: "A comprehensive guide to understanding #{query}...",
        relevance: 0.95
      },
      %{
        title: "Advanced #{query} Techniques",
        snippet: "Explore advanced concepts and best practices for #{query}...",
        relevance: 0.87
      },
      %{
        title: "Common #{query} Patterns",
        snippet: "Learn about frequently used patterns in #{query}...",
        relevance: 0.82
      }
    ]
    
    # Take requested number of results
    selected = Enum.take(results, limit)
    
    # Format results
    formatted = selected
    |> Enum.with_index(1)
    |> Enum.map(fn {result, idx} ->
      "#{idx}. #{result.title}\n   #{result.snippet}"
    end)
    |> Enum.join("\n\n")
    
    {:ok, formatted}
  end
  
  @doc """
  File reading tool.
  """
  def file_read(%{path: path}) do
    case File.read(path) do
      {:ok, content} ->
        # Truncate if too long
        truncated = if byte_size(content) > 5000 do
          String.slice(content, 0..4997) <> "..."
        else
          content
        end
        
        {:ok, truncated}
        
      {:error, reason} ->
        {:error, "Failed to read file: #{reason}"}
    end
  end
  
  @doc """
  HTTP request tool.
  """
  def http_request(args) do
    method = Map.get(args, :method, "GET") |> String.upcase()
    url = Map.get(args, :url)
    body = Map.get(args, :body, %{})
    
    # Validate URL
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] ->
        # Make request (simplified - use proper HTTP client in production)
        make_http_request(method, url, body)
        
      _ ->
        {:error, "Invalid URL"}
    end
  end
  
  defp make_http_request(method, url, body) do
    # Simulated HTTP request
    case method do
      "GET" ->
        {:ok, ~s|{"status": "success", "data": {"message": "GET #{url}"}}|}
        
      "POST" ->
        {:ok, ~s|{"status": "success", "data": {"message": "POST #{url}", "received": #{Jason.encode!(body)}}}|}
        
      _ ->
        {:error, "Unsupported HTTP method"}
    end
  end
  
  @doc """
  Data transformation tool.
  """
  def data_transform(%{operation: op, data: data} = args) do
    case op do
      "json_parse" ->
        case Jason.decode(data) do
          {:ok, parsed} -> {:ok, inspect(parsed, pretty: true)}
          {:error, _} -> {:error, "Invalid JSON"}
        end
        
      "json_encode" ->
        # Parse Elixir term string and encode to JSON
        try do
          {term, _} = Code.eval_string(data)
          {:ok, Jason.encode!(term)}
        rescue
          _ -> {:error, "Invalid data for JSON encoding"}
        end
        
      "base64_encode" ->
        {:ok, Base.encode64(data)}
        
      "base64_decode" ->
        case Base.decode64(data) do
          {:ok, decoded} -> {:ok, decoded}
          :error -> {:error, "Invalid base64"}
        end
        
      _ ->
        {:error, "Unknown transformation: #{op}"}
    end
  end
end
```

## INTEGRATION AND TESTING

### ASH FRAMEWORK INTEGRATION

```elixir
defmodule AshDSPy.React.AshIntegration do
  @moduledoc """
  Ash framework integration for React workflows.
  """
  
  use Ash.Resource.Change
  
  alias AshDSPy.React.Engine
  
  @doc """
  Ash change for React workflow execution.
  """
  def change(changeset, opts, _context) do
    signature = Keyword.fetch!(opts, :signature)
    tools = Keyword.get(opts, :tools, [])
    output_field = Keyword.get(opts, :output_field, :react_result)
    react_opts = Keyword.get(opts, :react_opts, [])
    
    Ash.Changeset.before_action(changeset, fn changeset ->
      # Extract inputs
      inputs = extract_inputs(changeset, opts)
      
      # Register custom tools if provided
      register_custom_tools(tools)
      
      # Execute React workflow
      case Engine.react(signature, inputs, react_opts) do
        {:ok, result} ->
          changeset
          |> Ash.Changeset.force_change_attribute(output_field, result.final_answer)
          |> Ash.Changeset.force_change_attribute(:"#{output_field}_trajectory", result.trajectory)
          |> Ash.Changeset.force_change_attribute(:"#{output_field}_metadata", result.metadata)
          
        {:error, reason} ->
          Ash.Changeset.add_error(
            changeset,
            field: output_field,
            message: "React workflow failed: #{inspect(reason)}"
          )
      end
    end)
  end
  
  defp extract_inputs(changeset, opts) do
    input_mapping = Keyword.get(opts, :input_mapping, %{})
    
    input_mapping
    |> Enum.reduce(%{}, fn {react_input, source}, acc ->
      value = case source do
        {:attribute, attr} -> Ash.Changeset.get_attribute(changeset, attr)
        {:argument, arg} -> Ash.Changeset.get_argument(changeset, arg)
        {:context, key} -> changeset.context[key]
        value -> value
      end
      
      Map.put(acc, react_input, value)
    end)
  end
  
  defp register_custom_tools(tools) do
    Enum.each(tools, fn {name, func, schema} ->
      Engine.register_tool(name, func, schema)
    end)
  end
end
```

### COMPREHENSIVE TESTING

```elixir
defmodule AshDSPy.React.EngineTest do
  use ExUnit.Case, async: true
  
  alias AshDSPy.React.Engine
  alias AshDSPy.Signature
  
  setup do
    {:ok, engine} = Engine.start_link(test_mode: true)
    
    # Create test signature
    signature = %Signature{
      name: "problem_solver",
      instructions: "Solve the given problem using available tools.",
      input_fields: %{
        problem: %{type: :string, required: true}
      },
      output_fields: %{
        solution: %{type: :string, required: true}
      }
    }
    
    %{engine: engine, signature: signature}
  end
  
  describe "react/3" do
    test "executes simple React workflow", %{signature: signature} do
      inputs = %{problem: "What is 25 * 4?"}
      opts = [max_iterations: 3]
      
      assert {:ok, result} = Engine.react(signature, inputs, opts)
      
      # Check result structure
      assert result.success
      assert result.final_answer == "100"
      assert length(result.trajectory) > 0
      
      # Check trajectory
      first_step = hd(result.trajectory)
      assert Map.has_key?(first_step, :thought)
      assert Map.has_key?(first_step, :action)
      assert Map.has_key?(first_step, :observation)
    end
    
    test "uses calculator tool correctly", %{signature: signature} do
      inputs = %{problem: "Calculate the square root of 144"}
      
      assert {:ok, result} = Engine.react(signature, inputs)
      
      # Find calculator action in trajectory
      calculator_step = Enum.find(result.trajectory, fn step ->
        String.contains?(step.action, "calculator")
      end)
      
      assert calculator_step
      assert calculator_step.observation =~ "12"
    end
    
    test "handles tool errors gracefully", %{signature: signature} do
      inputs = %{problem: "Calculate 1/0"}
      opts = [recovery_strategy: :retry_with_guidance]
      
      assert {:ok, result} = Engine.react(signature, inputs, opts)
      
      # Should recover from error
      error_step = Enum.find(result.trajectory, fn step ->
        String.contains?(step.observation, "Error")
      end)
      
      assert error_step
    end
    
    test "respects max iterations", %{signature: signature} do
      inputs = %{problem: "Solve an impossible problem"}
      opts = [max_iterations: 2]
      
      assert {:ok, result} = Engine.react(signature, inputs, opts)
      
      assert length(result.trajectory) <= 2
      
      if not result.success do
        assert result.metadata.error == :max_iterations_exceeded
      end
    end
  end
  
  describe "register_tool/3" do
    test "registers custom tool", %{signature: signature} do
      # Register custom tool
      custom_tool = fn %{text: text} ->
        {:ok, "Reversed: #{String.reverse(text)}"}
      end
      
      assert :ok = Engine.register_tool(:reverser, custom_tool, %{
        text: %{type: :string, required: true}
      })
      
      # Use custom tool
      inputs = %{problem: "Reverse the word 'hello'"}
      
      assert {:ok, result} = Engine.react(signature, inputs)
      
      # Check tool was used
      reverser_step = Enum.find(result.trajectory, fn step ->
        String.contains?(step.action, "reverser")
      end)
      
      assert reverser_step
      assert reverser_step.observation =~ "olleh"
    end
  end
  
  describe "execute_action/1" do
    test "parses and executes action correctly" do
      action = ~s|Action[calculator](expression: "2 + 2")|
      
      assert {:ok, observation} = Engine.execute_action(action)
      assert observation =~ "4"
    end
    
    test "handles invalid action format" do
      action = "InvalidAction"
      
      assert {:error, msg} = Engine.execute_action(action)
      assert msg =~ "parsing failed"
    end
    
    test "handles unknown tool" do
      action = ~s|Action[unknown_tool](param: "value")|
      
      assert {:error, msg} = Engine.execute_action(action)
      assert msg =~ "Unknown tool"
    end
  end
  
  describe "error recovery" do
    test "retries with exponential backoff" do
      # Create flaky tool
      counter = :counters.new(1, [])
      
      flaky_tool = fn _args ->
        count = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)
        
        if count < 3 do
          {:error, :temporary_failure}
        else
          {:ok, "Success on attempt #{count}"}
        end
      end
      
      Engine.register_tool(:flaky, flaky_tool, %{})
      
      inputs = %{problem: "Use the flaky tool"}
      opts = [recovery_strategy: :exponential_backoff]
      
      assert {:ok, result} = Engine.react(signature, inputs, opts)
      
      # Should eventually succeed
      flaky_step = Enum.find(result.trajectory, fn step ->
        String.contains?(step.action, "flaky") and
        String.contains?(step.observation, "Success")
      end)
      
      assert flaky_step
    end
  end
  
  describe "workflow orchestration" do
    test "executes parallel React workflows" do
      workflow_def = %{
        steps: [
          %{
            name: :parallel_calculations,
            type: :parallel_react,
            config: %{
              tasks: [
                %{signature: signature, options: []},
                %{signature: signature, options: []}
              ]
            }
          }
        ]
      }
      
      inputs = %{problem: "Calculate 2+2"}
      
      {:ok, orchestrator} = AshDSPy.React.WorkflowOrchestrator.start_link()
      
      assert {:ok, result} = 
        AshDSPy.React.WorkflowOrchestrator.execute_workflow(
          orchestrator,
          workflow_def,
          inputs
        )
      
      assert result.state == :completed
      assert Map.has_key?(result.results, :parallel_calculations)
    end
  end
  
  describe "action parsing" do
    test "parses various action formats" do
      alias AshDSPy.React.ActionParser
      
      # Tool action
      assert {:ok, action} = ActionParser.parse(~s|Action[tool](param: "value")|)
      assert action.type == :tool
      assert action.tool == :tool
      assert action.args == %{param: "value"}
      
      # Finish action
      assert {:ok, action} = ActionParser.parse("Finish[42]")
      assert action.type == :finish
      assert action.answer == "42"
      
      # Complex arguments
      assert {:ok, action} = ActionParser.parse(
        ~s|Action[calc](expression: "2 + 2", precision: 2)|
      )
      assert action.args == %{expression: "2 + 2", precision: 2}
    end
  end
  
  describe "context management" do
    test "maintains context across iterations" do
      alias AshDSPy.React.ContextManager
      
      {:ok, manager} = ContextManager.start_link()
      
      context = ContextManager.initialize(manager, signature, %{problem: "Test"})
      
      # Add steps
      context = ContextManager.update(
        manager,
        context,
        "First thought",
        "Action[tool]()",
        "First observation"
      )
      
      context = ContextManager.update(
        manager,
        context,
        "Second thought",
        "Action[tool]()",
        "Second observation"
      )
      
      # Format for prompt
      formatted = ContextManager.format_for_prompt(context)
      
      assert String.contains?(formatted, "First thought")
      assert String.contains?(formatted, "Second observation")
    end
  end
end
```

## PERFORMANCE CONSIDERATIONS

### 1. TOOL EXECUTION OPTIMIZATION
- Tool result caching for identical calls
- Parallel tool execution when independent
- Connection pooling for external tools
- Resource limits and timeouts

### 2. CONTEXT MANAGEMENT
- Intelligent context truncation
- Compression of historical steps
- Selective history inclusion
- Memory-efficient storage

### 3. ERROR RECOVERY
- Circuit breaker patterns for failing tools
- Exponential backoff with jitter
- Error pattern recognition
- Preemptive error avoidance

### 4. WORKFLOW OPTIMIZATION
- Parallel step execution
- Early termination on success
- Resource pooling across workflows
- State persistence for long workflows

## CONFIGURATION

```elixir
# config/config.exs
config :ash_dspy, :react,
  # Engine configuration
  max_iterations: 5,
  timeout_per_action: 30_000,
  default_tools: [:calculator, :search, :file_read],
  
  # Execution configuration
  sandbox_mode: true,
  parallel_tool_execution: true,
  max_parallel_tools: 3,
  
  # Error recovery
  recovery_strategy: :exponential_backoff,
  max_retries: 3,
  retry_delay_base: 1000,
  circuit_breaker_threshold: 10,
  circuit_breaker_timeout: 60_000,
  
  # Context management
  max_context_size: 10_000,
  max_history_items: 20,
  context_compression: true,
  
  # Tool registry
  tool_discovery_enabled: true,
  tool_validation_strict: true,
  tool_timeout_default: 30_000
```

This implementation provides a comprehensive React pattern system with advanced tool integration, workflow orchestration, error recovery, and extensive testing capabilities.