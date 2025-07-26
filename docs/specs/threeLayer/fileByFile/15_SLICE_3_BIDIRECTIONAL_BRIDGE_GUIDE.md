# Slice 3: Bidirectional Tool Bridge Implementation Guide

## Overview

This guide covers implementing Slice 3: The Bidirectional Tool Bridge - the killer feature that enables Python to call back into Elixir. This is what sets DSPex apart from simple Python wrappers.

## Slice 3 Goals

- Enable Python components to call Elixir functions
- Create tool registry for available functions
- Implement secure tool execution
- Add comprehensive telemetry
- Demonstrate with ChainOfThought validation

## Prerequisites

- [ ] Slices 1 & 2 completed and working
- [ ] Understanding of bidirectional concept from `01_REFACTORED_ARCHITECTURE_OVERVIEW.md`
- [ ] Python bridge can maintain session context
- [ ] Basic gRPC service infrastructure exists

## Architecture Overview

```
Elixir Side:                          Python Side:
DSPex.Tools.Registry                  session_context.py
    ↓                                      ↓
Tool.Executor  <---gRPC--->  call_elixir_tool(name, args)
    ↓                                      ↓
User Functions                        DSPy Components
(validators, transformers)            (use tools in logic)
```

## The Killer Feature Explained

Before diving into implementation, understand why this matters:

```python
# Traditional: Python calls Elixir, gets result, done
result = bridge.call("predict", {"question": "What is AI?"})

# Bidirectional: Python can call back to Elixir during execution!
def enhanced_predict(session_context, question):
    # Generate initial answer
    answer = generate_answer(question)
    
    # Use Elixir business logic to validate
    if not session_context.call_elixir_tool("validate_answer", {
        "question": question,
        "answer": answer
    }):
        # Use Elixir to fix the answer
        answer = session_context.call_elixir_tool("improve_answer", {
            "question": question, 
            "draft": answer
        })
    
    return answer
```

## Conversation Flow

### Conversation 1: Create Tool Registry

**Objective**: Build the registry for Elixir tools

**Source Documents**:
- `01_REFACTORED_ARCHITECTURE_OVERVIEW.md` - Bidirectional bridge section
- `04_VERTICAL_SLICE_MIGRATION.md` - Slice 3 scope

**Prompt**:
```text
CONTEXT:
I'm implementing Slice 3: Bidirectional Tool Bridge from our migration plan.
This is the killer feature described in 01_REFACTORED_ARCHITECTURE_OVERVIEW.md:

--- PASTE lines 169-209 from 01_REFACTORED_ARCHITECTURE_OVERVIEW.md ---

We need a registry where Elixir functions can be registered for Python to call.

TASK:
Create SnakepitGrpcBridge.Tools.Registry module that:

1. Maintains a registry of available tools
2. Supports registering functions with names and metadata
3. Validates function signatures (must accept map, return any term)
4. Provides lookup by name
5. Supports namespacing (e.g., "validation.email", "transform.normalize")
6. Includes introspection (list available tools)

Core functions:
- start_link/1 - GenServer managing registry
- register/3 - Register function with name and metadata
- unregister/1 - Remove a tool
- lookup/1 - Get function by name
- list/0 - List all registered tools
- execute/2 - Execute tool by name with args (for next step)

CONSTRAINTS:
- Functions must have arity of 1 (accept a map)
- Validate function exists and is exported
- Support hot code reloading (function refs, not captures)
- Thread-safe registration
- Clear error messages for missing tools

EXAMPLE:
```elixir
# Register a tool
:ok = Registry.register("validate_email", {MyApp.Validators, :email?}, %{
  description: "Validates email format",
  params: %{email: :string},
  returns: :boolean
})

# Look up and use
{:ok, {module, function, metadata}} = Registry.lookup("validate_email")
result = apply(module, function, [%{"email" => "test@example.com"}])
```
```

**Expected Output**: Complete tool registry implementation

### Conversation 2: Create Tool Executor

**Objective**: Safe execution layer for tools

**Source Documents**:
- Security best practices
- `08_TELEMETRY_AND_OBSERVABILITY.md` - Tool telemetry

**Prompt**:
```text
CONTEXT:
We need a safe execution layer for tools that handles errors, timeouts, and telemetry.
This sits between the registry and actual function execution.

From our telemetry spec (08_TELEMETRY_AND_OBSERVABILITY.md):
--- PASTE lines 75-94 from 08_TELEMETRY_AND_OBSERVABILITY.md ---

TASK:
Create SnakepitGrpcBridge.Tools.Executor module that:

1. Safely executes registered tools
2. Handles errors gracefully  
3. Enforces timeouts (default 5 seconds)
4. Emits telemetry events
5. Validates inputs/outputs
6. Provides execution context

Main function:
- execute/3 - execute(tool_name, args, context)

Where context includes:
- session_id
- caller (python/elixir)
- timeout
- metadata

CONSTRAINTS:
- Catch all exceptions and return {:error, reason}
- Emit telemetry for start/stop/exception
- Validate args is a map
- Support async execution (return task)
- Log execution details for debugging
- Measure execution time accurately

EXAMPLE:
```elixir
# Execute a tool
{:ok, result} = Executor.execute("validate_email", 
  %{"email" => "test@example.com"},
  %{session_id: "sess-123", caller: :python}
)

# With timeout
{:ok, result} = Executor.execute("slow_operation",
  %{data: data},
  %{timeout: 10_000}
)

# Handling errors
{:error, :timeout} = Executor.execute("infinite_loop", %{}, %{timeout: 100})
{:error, {:exception, error}} = Executor.execute("buggy_tool", %{}, %{})
```
```

**Expected Output**: Safe tool execution module

### Conversation 3: Add Bidirectional Behavior

**Objective**: Create the behavior for bidirectional modules

**Source Documents**:
- `02_DECOMPOSED_DEFDSYP_DESIGN.md` - Bidirectional behavior
- `07_SIMPLIFIED_MACRO_IMPLEMENTATION.md` - Behavior implementation

**Prompt**:
```text
CONTEXT:
Now we implement the Bidirectional behavior that modules use to expose tools.
From 02_DECOMPOSED_DEFDSYP_DESIGN.md:

--- PASTE lines 65-94 from 02_DECOMPOSED_DEFDSYP_DESIGN.md ---

And implementation pattern from 07_SIMPLIFIED_MACRO_IMPLEMENTATION.md:

--- PASTE lines 154-183 from 07_SIMPLIFIED_MACRO_IMPLEMENTATION.md ---

TASK:
Implement the complete DSPex.Bridge.Bidirectional behavior:

1. Update/create the behavior module with:
   - elixir_tools/0 callback
   - on_python_callback/3 optional callback
   - __using__ macro that properly sets up modules

2. The __using__ macro should:
   - Set @behaviour
   - Register module attribute for behavior tracking
   - Provide default on_python_callback
   - Make it overridable

3. Add helper functions:
   - register_tools/1 to bulk register from a module
   - tools_from_module/1 to extract tool definitions

CONSTRAINTS:
- Follow the exact pattern from our docs
- Don't use super() - use module attributes
- Keep it simple and composable
- Work with our registry from conversation 1
- Include clear documentation

EXAMPLE:
```elixir
defmodule MyPredictor do
  use DSPex.Bridge.SimpleWrapper
  use DSPex.Bridge.Bidirectional
  
  @impl DSPex.Bridge.Bidirectional
  def elixir_tools do
    [
      {"validate_prediction", &MyApp.Validators.validate/1},
      {"enhance_prompt", &MyApp.Enhancers.enhance/1}
    ]
  end
  
  @impl DSPex.Bridge.Bidirectional
  def on_python_callback(tool, args, context) do
    Logger.info("Python called #{tool}")
    :ok
  end
end
```
```

**Expected Output**: Complete Bidirectional behavior

### Conversation 4: Create gRPC Tool Service

**Objective**: Add gRPC endpoints for tool execution

**Source Documents**:
- Existing gRPC patterns in project
- `05_PYTHON_BRIDGE_REFACTORING.md` - Service layer

**Prompt**:
```text
CONTEXT:
We need gRPC service for Python to call Elixir tools.
This enables the bidirectional communication described in our architecture.

TASK:
Create gRPC service definitions and implementation:

1. Proto definitions:
```proto
service ToolService {
  rpc CallTool(CallToolRequest) returns (CallToolResponse);
  rpc ListTools(ListToolsRequest) returns (ListToolsResponse);
}

message CallToolRequest {
  string session_id = 1;
  string tool_name = 2;
  bytes args = 3;  // Serialized map
}

message CallToolResponse {
  bool success = 1;
  bytes result = 2;  // Serialized result
  string error = 3;
}

message ListToolsRequest {
  string session_id = 1;
}

message ListToolsResponse {
  repeated ToolInfo tools = 1;
}

message ToolInfo {
  string name = 1;
  string description = 2;
  map<string, string> params = 3;
}
```

2. Implement Elixir service that:
   - Delegates to Tools.Executor
   - Handles serialization/deserialization
   - Provides proper error responses
   - Includes session context

CONSTRAINTS:
- Use consistent serialization (ETF or JSON)
- Return proper gRPC status codes
- Include request ID for tracing
- Rate limit tool calls per session
- Log all tool invocations

EXAMPLE:
```elixir
def call_tool(request, _stream) do
  with {:ok, args} <- deserialize(request.args),
       {:ok, result} <- Tools.Executor.execute(
         request.tool_name,
         args,
         %{session_id: request.session_id, caller: :python}
       ),
       {:ok, serialized} <- serialize(result) do
    CallToolResponse.new(success: true, result: serialized)
  else
    {:error, reason} ->
      CallToolResponse.new(success: false, error: format_error(reason))
  end
end
```
```

**Expected Output**: gRPC service for tools

### Conversation 5: Python Client Implementation

**Objective**: Python-side tool calling interface

**Source Documents**:
- `05_PYTHON_BRIDGE_REFACTORING.md` - Python session context

**Prompt**:
```text
CONTEXT:
Now we implement the Python side that calls Elixir tools.
This goes in the session context as shown in 05_PYTHON_BRIDGE_REFACTORING.md:

--- PASTE lines 155-178 from 05_PYTHON_BRIDGE_REFACTORING.md ---

TASK:
Update Python session context with tool calling:

1. Add to Session class:
   - call_elixir_tool(self, tool_name: str, args: dict) -> Any
   - list_available_tools(self) -> List[ToolInfo]
   - register_result_handler(self, handler) for custom deserialization

2. Features to include:
   - Automatic serialization of Python types
   - Clear error messages
   - Timeout handling
   - Result caching (optional)
   - Async support (return Future)

3. Make it Pythonic:
   - Support kwargs: call_tool("validate", email="test@example.com")
   - Raise exceptions for errors
   - Type hints throughout
   - Context manager support

CONSTRAINTS:
- Handle common Python types seamlessly
- Provide sync and async versions
- Include retry logic for transient failures
- Log tool calls for debugging
- Support numpy/pandas types if present

EXAMPLE:
```python
class Session:
    def call_elixir_tool(self, tool_name: str, args: dict = None, **kwargs) -> Any:
        \"\"\"Call an Elixir tool registered with the bridge.
        
        Args:
            tool_name: Name of the registered tool
            args: Arguments as dictionary
            **kwargs: Alternative to args dict
            
        Returns:
            Result from Elixir function
            
        Raises:
            ToolNotFoundError: If tool doesn't exist
            ToolExecutionError: If tool execution fails
        \"\"\"
        if args is None:
            args = kwargs
            
        request = CallToolRequest(
            session_id=self.id,
            tool_name=tool_name,
            args=self._serialize(args)
        )
        
        response = self._grpc_client.CallTool(request)
        
        if not response.success:
            if "not found" in response.error:
                raise ToolNotFoundError(f"Tool '{tool_name}' not found")
            raise ToolExecutionError(response.error)
            
        return self._deserialize(response.result)
```
```

**Expected Output**: Python tool calling implementation

### Conversation 6: Integration with DSPex Modules

**Objective**: Wire up bidirectional support in DSPex

**Source Documents**:
- Our new macro system design
- Existing DSPex modules

**Prompt**:
```text
CONTEXT:
We need to integrate bidirectional support into DSPex wrapper modules.
When a module uses DSPex.Bridge.Bidirectional, its tools should be automatically registered.

TASK:
Update the wrapper generation system to handle bidirectional modules:

1. In ContractBased or SimpleWrapper's create function:
   - Check if module has @dspex_behaviors including :bidirectional
   - If yes, register tools from elixir_tools/0
   - Store tool registrations with the instance reference

2. Create DSPex.Tools module for high-level API:
   - register/2 - Register a single tool  
   - register_module/1 - Register all tools from a bidirectional module
   - unregister/1 - Remove a tool
   - call/2 - Call a tool (for testing from Elixir side)

3. Update instance lifecycle:
   - Register tools on instance creation
   - Unregister tools on instance cleanup
   - Handle module reloading

CONSTRAINTS:
- Don't break modules without bidirectional
- Make registration automatic and transparent
- Support dynamic tool updates
- Clean up on process exit
- Include debug logging

EXAMPLE:
```elixir
# This should automatically work:
defmodule MyApp.SmartPredictor do
  use DSPex.Bridge.ContractBased
  use DSPex.Bridge.Bidirectional
  
  use_contract DSPex.Contracts.Predict
  
  @impl DSPex.Bridge.Bidirectional
  def elixir_tools do
    [
      {"validate_answer", &MyApp.validate_answer/1},
      {"get_context", &MyApp.get_context/1}
    ]
  end
end

# When someone creates an instance:
{:ok, ref} = MyApp.SmartPredictor.create(signature: "question -> answer")
# Tools are automatically available to Python!
```
```

**Expected Output**: Automatic tool registration

### Conversation 7: ChainOfThought Example Implementation

**Objective**: Demonstrate bidirectional with real use case

**Source Documents**:
- ChainOfThought patterns
- Validation requirements

**Prompt**:
```text
CONTEXT:
Let's create a complete example showing bidirectional tools with ChainOfThought.
This demonstrates the killer feature in action.

TASK:
Create a bidirectional ChainOfThought wrapper that:

1. Uses contract-based approach
2. Exposes validation tools to Python
3. Shows real business logic integration

Create these modules:

1. DSPex.Examples.BiChainOfThought:
   - Uses ContractBased + Bidirectional
   - Exposes reasoning validation
   - Exposes context fetching

2. DSPex.Examples.Validators:
   - validate_reasoning/1 - Ensures reasoning has enough steps
   - validate_conclusion/1 - Checks conclusion follows from reasoning
   - score_reasoning/1 - Returns quality score

3. DSPex.Examples.ContextProvider:
   - fetch_examples/1 - Get relevant examples
   - fetch_rules/1 - Get business rules

Include a complete example showing:
- Elixir setup
- Python usage
- How validation affects output

CONSTRAINTS:
- Make it realistic and useful
- Show clear business value
- Include error handling
- Document the flow clearly

EXAMPLE:
The Python side might look like:
```python
def enhanced_chain_of_thought(session_context, question):
    # Get business rules from Elixir
    rules = session_context.call_elixir_tool("fetch_rules", {
        "domain": "medical"
    })
    
    # Generate reasoning
    reasoning = generate_reasoning(question, rules)
    
    # Validate with Elixir business logic
    if not session_context.call_elixir_tool("validate_reasoning", {
        "steps": reasoning,
        "rules": rules
    }):
        # Get help from Elixir to fix it
        reasoning = session_context.call_elixir_tool("improve_reasoning", {
            "original": reasoning,
            "question": question
        })
    
    return create_answer(reasoning)
```
```

**Expected Output**: Complete working example

### Conversation 8: Comprehensive Integration Tests

**Objective**: Test the complete bidirectional flow

**Source Documents**:
- `06_COGNITIVE_READINESS_TESTS.md` - Bidirectional tests
- `04_VERTICAL_SLICE_MIGRATION.md` - Success criteria

**Prompt**:
```text
CONTEXT:
We need comprehensive tests proving bidirectional tools work end-to-end.
From 06_COGNITIVE_READINESS_TESTS.md:

--- PASTE lines 178-236 from 06_COGNITIVE_READINESS_TESTS.md ---

And our success criteria from 04_VERTICAL_SLICE_MIGRATION.md:

--- PASTE lines 113-132 from 04_VERTICAL_SLICE_MIGRATION.md ---

TASK:
Create test/dspex/bidirectional_integration_test.exs with:

1. Basic tool calling tests:
   - Python calls simple Elixir function
   - Parameters passed correctly
   - Return values work
   - Errors handled gracefully

2. Complex workflow tests:
   - Multi-step validation flow
   - Tools calling other tools
   - Session state interaction
   - Concurrent tool calls

3. Performance tests:
   - Tool execution time tracking
   - Overhead measurement
   - Throughput testing
   - Memory usage validation

4. Error scenario tests:
   - Tool not found
   - Tool timeout
   - Tool exception
   - Serialization failure

5. Real use case test:
   - Complete ChainOfThought with validation
   - Shows business value
   - Measures improvement

CONSTRAINTS:
- Test both happy and unhappy paths
- Include telemetry verification
- Test security boundaries
- Verify cleanup happens
- Make tests deterministic

EXAMPLE:
```elixir
@tag :integration
test "ChainOfThought uses Elixir validation to improve quality" do
  # Register validation tool
  Tools.Registry.register("validate_medical", 
    {Medical.Validators, :validate_diagnosis}, 
    %{description: "Validates medical reasoning"}
  )
  
  # Create ChainOfThought that uses validation
  {:ok, cot} = Medical.ChainOfThought.create(
    signature: "symptoms -> diagnosis, treatment"
  )
  
  # Run with medical question
  {:ok, result} = Medical.ChainOfThought.call(cot, %{
    symptoms: "persistent cough, fever, fatigue"
  })
  
  # Verify validation was called
  assert_receive {:telemetry, [:dspex, :tools, :call, :stop], _, %{
    tool_name: "validate_medical"
  }}
  
  # Check result quality improved
  assert Medical.Validators.score_diagnosis(result) > 0.8
end
```
```

**Expected Output**: Complete test suite

## Verification Checklist

After all conversations:

- [ ] Tool registry works and persists tools
- [ ] Tools can be called from Python naturally
- [ ] Errors are handled gracefully
- [ ] Telemetry provides full visibility
- [ ] ChainOfThought example demonstrates value
- [ ] Performance overhead is acceptable
- [ ] Security boundaries are enforced
- [ ] Integration tests pass

## Manual Testing Scenarios

### Scenario 1: Basic Tool Call
```python
# Python
session = bridge.get_session("test-1")
result = session.call_elixir_tool("uppercase", {"text": "hello"})
assert result == "HELLO"
```

### Scenario 2: Validation Flow
```python
# Python
def smart_predict(session, question):
    answer = generate_answer(question)
    
    valid = session.call_elixir_tool("validate_answer", {
        "question": question,
        "answer": answer
    })
    
    if not valid:
        context = session.call_elixir_tool("get_context", {
            "question": question
        })
        answer = regenerate_with_context(question, context)
    
    return answer
```

### Scenario 3: Complex Business Logic
```elixir
# Elixir tools
def validate_medical_diagnosis(%{"symptoms" => symptoms, "diagnosis" => diagnosis}) do
  rules = MedicalRules.get_diagnostic_criteria(diagnosis)
  symptoms_match = Enum.all?(rules.required_symptoms, &(&1 in symptoms))
  
  if symptoms_match do
    {:ok, true}
  else
    {:error, "Missing symptoms: #{inspect(rules.required_symptoms -- symptoms)}"}
  end
end
```

## Performance Optimization

1. **Tool Result Caching**: Cache frequently called tools
2. **Batch Operations**: Support calling multiple tools in one request
3. **Connection Pooling**: Reuse gRPC connections
4. **Lazy Loading**: Only serialize/deserialize when needed
5. **Circuit Breaking**: Disable broken tools temporarily

## Security Considerations

1. **Tool Whitelist**: Only registered tools can be called
2. **Input Validation**: Validate all inputs before execution
3. **Timeout Enforcement**: Prevent infinite loops
4. **Rate Limiting**: Limit calls per session
5. **Audit Logging**: Log all tool invocations

## Next Steps

After Slice 3:
1. Monitor tool usage patterns
2. Add more business logic tools
3. Create tool marketplace/registry
4. Implement tool versioning
5. Add tool composition features

## Summary

Slice 3 implements the killer feature:
- ✅ Python can call Elixir functions
- ✅ Business logic stays in Elixir
- ✅ Clean, natural API
- ✅ Full observability
- ✅ Production-ready patterns

This enables true collaboration between Python's AI capabilities and Elixir's business logic, creating possibilities that neither can achieve alone.