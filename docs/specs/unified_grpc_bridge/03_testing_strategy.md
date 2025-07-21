# Unified gRPC Bridge: Testing Strategy

## Overview

This document provides a comprehensive testing strategy for the unified gRPC bridge that handles both tools and variables. Tests are organized by type and mapped to implementation phases to provide clear definitions of done.

## Testing Philosophy

1. **Test-Driven Development**: Write tests before implementation when possible
2. **Isolation**: Each component should be testable in isolation
3. **Integration Focus**: Prioritize integration tests that verify cross-language behavior
4. **Failure Simulation**: Explicitly test error conditions and edge cases
5. **Performance Awareness**: Include performance benchmarks from the start

## Test Categories and Phase Mapping

### Phase Completion Criteria

| Phase | Description | Completion Criteria |
|-------|-------------|-------------------|
| **Phase 1** | Core Tool Execution | - All SessionStore unit tests pass<br>- Basic gRPC server tests pass<br>- Single tool E2E test succeeds<br>- Performance baseline established |
| **Phase 2** | Variable Integration | - Variable CRUD unit tests pass<br>- Variable type system tests pass<br>- E2E test: Python reads Elixir variable<br>- E2E test: Elixir updates affect Python |
| **Phase 3** | Streaming Support | - Streaming tool tests pass<br>- Variable watch tests pass<br>- E2E test: Real-time updates work<br>- Load test: 100 concurrent streams |
| **Phase 4** | Advanced Features | - Module-type variable tests pass<br>- Batch operation tests pass<br>- Complex E2E scenarios pass<br>- Full system load test passes |

## Detailed Test Specifications

### 1. Unit Tests

#### Phase 1: Core Infrastructure

```elixir
# test/dspex/bridge/session_store_test.exs
defmodule DSPex.Bridge.SessionStoreTest do
  use ExUnit.Case, async: true
  
  describe "session management" do
    test "creates session with unique ID" do
      {:ok, session_id1} = SessionStore.create_session()
      {:ok, session_id2} = SessionStore.create_session()
      
      assert session_id1 != session_id2
      assert is_binary(session_id1)
    end
    
    test "stores and retrieves session metadata" do
      {:ok, session_id} = SessionStore.create_session(%{
        user_id: "test_user",
        purpose: "testing"
      })
      
      {:ok, session} = SessionStore.get_session(session_id)
      assert session.metadata.user_id == "test_user"
      assert session.metadata.purpose == "testing"
    end
  end
  
  describe "tool registration" do
    setup do
      {:ok, session_id} = SessionStore.create_session()
      {:ok, session_id: session_id}
    end
    
    test "registers tool in session", %{session_id: session_id} do
      tool_spec = %{
        name: "test_tool",
        description: "A test tool",
        parameters: [],
        handler: &TestHelpers.echo_handler/2
      }
      
      assert :ok = SessionStore.register_tool(session_id, "test_tool", tool_spec)
      
      {:ok, tools} = SessionStore.get_session_tools(session_id)
      assert Map.has_key?(tools, "test_tool")
    end
    
    test "prevents duplicate tool registration", %{session_id: session_id} do
      tool_spec = %{name: "test_tool", handler: &TestHelpers.echo_handler/2}
      
      :ok = SessionStore.register_tool(session_id, "test_tool", tool_spec)
      assert {:error, :tool_already_exists} = 
        SessionStore.register_tool(session_id, "test_tool", tool_spec)
    end
  end
end
```

```python
# tests/test_session_context.py
import pytest
import asyncio
from unittest.mock import Mock, AsyncMock
import grpc
from dspex_bridge import SessionContext

class TestSessionContext:
    """Test SessionContext initialization and basic operations."""
    
    @pytest.fixture
    def mock_channel(self):
        """Create a mock gRPC channel."""
        channel = Mock(spec=grpc.aio.Channel)
        return channel
    
    @pytest.fixture
    def session_context(self, mock_channel):
        """Create a SessionContext with mocked dependencies."""
        return SessionContext("test_session_123", mock_channel)
    
    def test_initialization(self, session_context):
        """Test proper initialization of SessionContext."""
        assert session_context.session_id == "test_session_123"
        assert session_context._tools == {}
        assert session_context._variable_cache == {}
        assert session_context._cache_ttl == 1.0
    
    @pytest.mark.asyncio
    async def test_tool_access(self, session_context):
        """Test tool proxy creation and access."""
        # Mock tool spec
        tool_spec = {
            "name": "test_tool",
            "description": "Test",
            "parameters": []
        }
        
        # Add tool
        session_context._add_tool(tool_spec)
        
        assert "test_tool" in session_context.tools
        assert session_context.tools["test_tool"].name == "test_tool"
```

#### Phase 2: Variable System

```elixir
# test/dspex/bridge/variable_tests.exs
defmodule DSPex.Bridge.VariableTest do
  use ExUnit.Case
  
  alias DSPex.Bridge.Variables.Types
  
  describe "variable types" do
    test "float type validation" do
      assert {:ok, 1.5} = Types.Float.validate(1.5)
      assert {:ok, 2.0} = Types.Float.validate(2)  # Integer coerced
      assert {:error, _} = Types.Float.validate("not a number")
    end
    
    test "float type constraints" do
      assert :ok = Types.Float.validate_constraint(:min, 0.0, 0.5)
      assert {:error, _} = Types.Float.validate_constraint(:min, 1.0, 0.5)
      
      assert :ok = Types.Float.validate_constraint(:max, 2.0, 1.5)
      assert {:error, _} = Types.Float.validate_constraint(:max, 1.0, 1.5)
    end
    
    test "module type validation" do
      assert {:ok, :Predict} = Types.Module.validate(:Predict)
      assert {:ok, :ChainOfThought} = Types.Module.validate("ChainOfThought")
      assert {:error, _} = Types.Module.validate(123)
    end
  end
  
  describe "variable registration in session" do
    setup do
      {:ok, session_id} = SessionStore.create_session()
      {:ok, session_id: session_id}
    end
    
    test "registers variable with type validation", %{session_id: session_id} do
      {:ok, var_id} = SessionStore.register_variable(
        session_id,
        :temperature,
        :float,
        0.7,
        constraints: %{min: 0.0, max: 2.0}
      )
      
      assert var_id =~ "var_"
      
      {:ok, variable} = SessionStore.get_variable(session_id, var_id)
      assert variable.name == :temperature
      assert variable.value == 0.7
    end
    
    test "enforces type constraints on update", %{session_id: session_id} do
      {:ok, var_id} = SessionStore.register_variable(
        session_id,
        :count,
        :integer,
        5,
        constraints: %{min: 1, max: 10}
      )
      
      # Valid update
      assert :ok = SessionStore.update_variable(session_id, var_id, 8)
      
      # Invalid update
      assert {:error, _} = SessionStore.update_variable(session_id, var_id, 15)
    end
  end
end
```

```python
# tests/test_variable_operations.py
import pytest
from dspex_bridge.session_context import SessionContext

class TestVariableOperations:
    """Test variable-specific operations in SessionContext."""
    
    @pytest.mark.asyncio
    async def test_get_variable_with_cache(self, session_context_with_stub):
        """Test variable retrieval with caching behavior."""
        session = session_context_with_stub
        
        # Mock the gRPC response
        mock_variable = Mock()
        mock_variable.name = "temperature"
        mock_variable.type = "float"
        mock_variable.value.Pack(FloatValue(value=0.7))
        
        session.stub.GetVariable.return_value = Mock(variable=mock_variable)
        
        # First call should hit the server
        value1 = await session.get_variable("temperature")
        assert value1 == 0.7
        assert session.stub.GetVariable.call_count == 1
        
        # Second call should use cache
        value2 = await session.get_variable("temperature")
        assert value2 == 0.7
        assert session.stub.GetVariable.call_count == 1  # No additional call
        
    @pytest.mark.asyncio
    async def test_set_variable_updates_cache(self, session_context_with_stub):
        """Test that setting a variable updates the cache."""
        session = session_context_with_stub
        
        # Mock successful response
        session.stub.SetVariable.return_value = Mock(success=True)
        
        await session.set_variable("max_tokens", 256)
        
        # Should be in cache now
        assert "max_tokens" in session._variable_cache
        assert session._variable_cache["max_tokens"][0] == 256
```

### 2. Integration Tests

#### Phase 1-2: Tool and Variable Integration

```elixir
# test/dspex/bridge/grpc_integration_test.exs
defmodule DSPex.Bridge.GRPCIntegrationTest do
  use DSPex.IntegrationCase
  
  @moduletag :integration
  
  setup do
    # Start gRPC server on test port
    {:ok, _server} = start_test_server(port: 50052)
    
    # Create test session with tools
    {:ok, session_id} = SessionStore.create_session()
    
    # Register test tools
    :ok = SessionStore.register_tool(session_id, "echo", %{
      name: "echo",
      description: "Echoes input",
      parameters: [
        %{name: "message", type: "string", required: true}
      ],
      handler: fn %{"message" => msg}, _ctx -> {:ok, "Echo: #{msg}"} end
    })
    
    :ok = SessionStore.register_tool(session_id, "calculator", %{
      name: "calculator",
      description: "Performs calculations",
      parameters: [
        %{name: "expression", type: "string", required: true}
      ],
      handler: &TestTools.calculator_handler/2
    })
    
    # Register test variables
    {:ok, _} = SessionStore.register_variable(session_id, :temperature, :float, 0.7)
    {:ok, _} = SessionStore.register_variable(session_id, :model, :choice, "gpt-4",
      constraints: %{choices: ["gpt-4", "claude", "gemini"]}
    )
    
    {:ok, session_id: session_id, port: 50052}
  end
  
  test "Python can execute Elixir tool", %{session_id: session_id, port: port} do
    # This would actually spawn a Python process in real test
    result = run_python_test("""
    import asyncio
    from dspex_bridge import SessionContext
    
    async def test():
        channel = grpc.aio.insecure_channel('localhost:#{port}')
        session = SessionContext('#{session_id}', channel)
        
        await session.initialize()
        result = await session.tools['echo'](message='Hello from Python')
        return result
    
    result = asyncio.run(test())
    print(result)
    """)
    
    assert result == "Echo: Hello from Python"
  end
  
  test "Python can read and write variables", %{session_id: session_id, port: port} do
    result = run_python_test("""
    import asyncio
    from dspex_bridge import SessionContext
    
    async def test():
        channel = grpc.aio.insecure_channel('localhost:#{port}')
        session = SessionContext('#{session_id}', channel)
        
        # Read variable set by Elixir
        temp = await session.get_variable('temperature')
        assert temp == 0.7
        
        # Write new variable
        await session.set_variable('python_var', 'Hello from Python')
        
        return True
    
    asyncio.run(test())
    """)
    
    # Verify Python's write is visible in Elixir
    {:ok, var} = SessionStore.get_variable(session_id, "python_var")
    assert var.value == "Hello from Python"
  end
end
```

```python
# tests/test_integration.py
import pytest
import grpc
import asyncio
from dspex_bridge import SessionContext

@pytest.mark.integration
class TestElixirPythonIntegration:
    """Integration tests requiring both Elixir and Python components."""
    
    @pytest.fixture
    async def live_session(self, elixir_server):
        """Create a real session connected to test Elixir server."""
        channel = grpc.aio.insecure_channel(f'localhost:{elixir_server.port}')
        session = SessionContext(elixir_server.session_id, channel)
        await session.initialize()
        yield session
        await channel.close()
    
    @pytest.mark.asyncio
    async def test_tool_with_variable_dependency(self, live_session):
        """Test tool that uses variables for configuration."""
        # Set quality threshold variable
        await live_session.set_variable('quality_threshold', 0.8)
        
        # Create tool that uses the variable
        search_tool = live_session.create_variable_aware_tool(
            'search_web',
            {'min_quality': 'quality_threshold'}
        )
        
        # Execute tool - should use variable value
        results = await search_tool(query="DSPy framework")
        
        # All results should meet quality threshold
        assert all(r['quality'] >= 0.8 for r in results)
    
    @pytest.mark.asyncio
    async def test_variable_updates_affect_tools(self, live_session):
        """Test that variable updates immediately affect tool behavior."""
        # Create temperature-sensitive tool
        summary_tool = live_session.create_variable_aware_tool(
            'summarize',
            {'temperature': 'temperature'}
        )
        
        # Test with low temperature
        await live_session.set_variable('temperature', 0.2)
        summary1 = await summary_tool(text="Long text here...")
        
        # Test with high temperature  
        await live_session.set_variable('temperature', 1.5)
        summary2 = await summary_tool(text="Long text here...")
        
        # High temperature should produce more creative summary
        assert len(summary2) != len(summary1)  # Different outputs
```

### 3. End-to-End Tests

```python
# tests/test_e2e_scenarios.py
import pytest
import asyncio
import grpc
from dspex_bridge import SessionContext, VariableAwareChainOfThought

@pytest.fixture
def elixir_server():
    """
    Fixture that starts a real Elixir gRPC server for testing.
    
    The Elixir application is configured with test tools:
    - echo: Simple echo tool
    - search_web: Mock web search with quality scores
    - calculator: Basic arithmetic evaluation
    - summarize: Mock text summarization
    """
    # In practice, this would use subprocess to start Elixir
    server = ElixirTestServer()
    server.start(port=50053)
    
    # Configure test tools in Elixir
    server.register_tools({
        'echo': {'handler': 'TestTools.echo/2'},
        'search_web': {'handler': 'TestTools.mock_search/2'},
        'calculator': {'handler': 'TestTools.calculate/2'},
        'summarize': {'handler': 'TestTools.mock_summarize/2'}
    })
    
    yield server
    server.stop()

@pytest.mark.e2e
class TestEndToEndScenarios:
    """Complete end-to-end scenarios testing real workflows."""
    
    @pytest.mark.asyncio
    async def test_dspy_module_with_tools_and_variables(self, elixir_server):
        """Test DSPy module using both tools and variables."""
        # Connect to server
        channel = grpc.aio.insecure_channel(f'localhost:{elixir_server.port}')
        session = SessionContext(elixir_server.session_id, channel)
        await session.initialize()
        
        # Set up variables
        await session.set_variable('temperature', 0.7)
        await session.set_variable('search_depth', 5)
        
        # Create custom DSPy module that uses tools
        class ResearchAssistant(VariableAwareChainOfThought):
            def __init__(self, session_context):
                super().__init__(
                    "question -> research_plan, findings, answer",
                    session_context=session_context
                )
                self.search_tool = session_context.tools['search_web']
                
            async def forward(self, question):
                # Sync variables
                await self.sync_variables()
                
                # Use tool with variable
                depth = await self.session_context.get_variable('search_depth')
                search_results = await self.search_tool(
                    query=question,
                    max_results=depth
                )
                
                # Continue with reasoning
                return await super().forward(
                    question=question,
                    context=search_results
                )
        
        # Use the assistant
        assistant = ResearchAssistant(session)
        result = await assistant.forward("What are the key features of DSPy?")
        
        assert result.research_plan is not None
        assert result.findings is not None
        assert result.answer is not None
        assert "DSPy" in result.answer
    
    @pytest.mark.asyncio
    async def test_streaming_tool_with_variable_updates(self, elixir_server):
        """Test streaming tool that responds to variable changes."""
        channel = grpc.aio.insecure_channel(f'localhost:{elixir_server.port}')
        session = SessionContext(elixir_server.session_id, channel)
        await session.initialize()
        
        # Set initial configuration
        await session.set_variable('stream_delay', 0.1)
        await session.set_variable('stream_format', 'json')
        
        # Get streaming tool
        stream_tool = session.tools['stream_data']
        
        # Start consuming stream
        chunks = []
        async for chunk in stream_tool(source="test_feed"):
            chunks.append(chunk)
            
            # Change format mid-stream
            if len(chunks) == 5:
                await session.set_variable('stream_format', 'xml')
        
        # Verify format changed mid-stream
        json_chunks = [c for c in chunks[:5] if c.startswith('{')]
        xml_chunks = [c for c in chunks[5:] if c.startswith('<')]
        
        assert len(json_chunks) == 5
        assert len(xml_chunks) > 0
```

### 4. Performance Tests

```elixir
# test/dspex/bridge/performance_test.exs
defmodule DSPex.Bridge.PerformanceTest do
  use ExUnit.Case
  
  @moduletag :performance
  
  test "baseline tool execution performance" do
    {:ok, session_id} = SessionStore.create_session()
    
    :ok = SessionStore.register_tool(session_id, "noop", %{
      name: "noop",
      handler: fn _args, _ctx -> {:ok, "done"} end
    })
    
    # Measure execution time
    {time, _} = :timer.tc(fn ->
      for _ <- 1..1000 do
        SessionStore.execute_tool(session_id, "noop", %{})
      end
    end)
    
    avg_time = time / 1000 / 1000  # Convert to ms
    assert avg_time < 1.0, "Tool execution should average < 1ms, got #{avg_time}ms"
  end
  
  test "variable access performance" do
    {:ok, session_id} = SessionStore.create_session()
    
    # Register 100 variables
    var_ids = for i <- 1..100 do
      {:ok, var_id} = SessionStore.register_variable(
        session_id,
        :"var_#{i}",
        :float,
        :rand.uniform()
      )
      var_id
    end
    
    # Measure read performance
    {time, _} = :timer.tc(fn ->
      for _ <- 1..10, var_id <- var_ids do
        SessionStore.get_variable(session_id, var_id)
      end
    end)
    
    avg_time = time / 1000 / 1000  # Total ms per read
    assert avg_time < 0.1, "Variable read should average < 0.1ms, got #{avg_time}ms"
  end
end
```

```python
# tests/test_performance.py
import pytest
import asyncio
import time
from dspex_bridge import SessionContext

@pytest.mark.performance
class TestPerformance:
    """Performance benchmarks for the bridge."""
    
    @pytest.mark.asyncio
    async def test_variable_cache_performance(self, session_context_with_stub):
        """Test that variable caching improves performance."""
        session = session_context_with_stub
        
        # Mock variable response
        session.stub.GetVariable.return_value = Mock(
            variable=create_mock_variable("test", 42)
        )
        
        # First access (cache miss)
        start = time.time()
        await session.get_variable("test")
        uncached_time = time.time() - start
        
        # Second access (cache hit)
        start = time.time()
        for _ in range(100):
            await session.get_variable("test")
        cached_time = (time.time() - start) / 100
        
        # Cache should be at least 10x faster
        assert cached_time < uncached_time / 10
        
    @pytest.mark.asyncio
    async def test_concurrent_tool_execution(self, live_session):
        """Test concurrent tool execution performance."""
        echo_tool = live_session.tools['echo']
        
        # Execute 100 tools concurrently
        start = time.time()
        tasks = [
            echo_tool(message=f"Message {i}")
            for i in range(100)
        ]
        results = await asyncio.gather(*tasks)
        duration = time.time() - start
        
        assert len(results) == 100
        assert duration < 2.0  # Should complete in < 2 seconds
        
        # Calculate throughput
        throughput = 100 / duration
        print(f"Tool throughput: {throughput:.1f} calls/second")
```

### 5. Load Tests

```python
# tests/test_load.py
import pytest
import asyncio
import grpc
from concurrent.futures import ProcessPoolExecutor

@pytest.mark.load
class TestLoadScenarios:
    """Load tests to verify system behavior under stress."""
    
    @pytest.mark.asyncio
    async def test_many_sessions(self, elixir_server):
        """Test system with many concurrent sessions."""
        async def create_and_use_session(session_num):
            channel = grpc.aio.insecure_channel(f'localhost:{elixir_server.port}')
            
            # Create new session
            session_id = await create_session_via_grpc(channel)
            session = SessionContext(session_id, channel)
            await session.initialize()
            
            # Perform some operations
            await session.set_variable(f'session_{session_num}_var', session_num)
            result = await session.tools['echo'](message=f"Session {session_num}")
            
            # Verify isolation
            var_value = await session.get_variable(f'session_{session_num}_var')
            assert var_value == session_num
            
            await channel.close()
            return True
        
        # Create 50 concurrent sessions
        tasks = [create_and_use_session(i) for i in range(50)]
        results = await asyncio.gather(*tasks)
        
        assert all(results)
        
    @pytest.mark.asyncio
    async def test_variable_watch_scalability(self, live_session):
        """Test variable watching with many concurrent watchers."""
        # Create 100 variables
        for i in range(100):
            await live_session.set_variable(f'watch_var_{i}', 0)
        
        # Create 20 watchers, each watching 10 variables
        watchers = []
        for i in range(20):
            var_names = [f'watch_var_{j}' for j in range(i*5, (i+1)*5)]
            
            async def watch_and_count(vars_to_watch):
                count = 0
                async for update in live_session.watch_variables(vars_to_watch):
                    count += 1
                    if count >= 50:  # Stop after 50 updates
                        break
                return count
            
            watchers.append(asyncio.create_task(watch_and_count(var_names)))
        
        # Trigger updates
        update_task = asyncio.create_task(self._trigger_updates(live_session))
        
        # Wait for watchers
        counts = await asyncio.gather(*watchers)
        update_task.cancel()
        
        # Each watcher should have received updates
        assert all(c >= 50 for c in counts)
```

### 6. Failure Mode Tests

```elixir
# test/dspex/bridge/failure_mode_test.exs
defmodule DSPex.Bridge.FailureModeTest do
  use ExUnit.Case
  
  @moduletag :failure
  
  test "handles tool execution timeout gracefully" do
    {:ok, session_id} = SessionStore.create_session()
    
    :ok = SessionStore.register_tool(session_id, "slow_tool", %{
      name: "slow_tool",
      handler: fn _args, _ctx ->
        Process.sleep(5000)  # 5 second delay
        {:ok, "done"}
      end,
      timeout: 1000  # 1 second timeout
    })
    
    assert {:error, :timeout} = 
      SessionStore.execute_tool(session_id, "slow_tool", %{})
  end
  
  test "handles session expiration during operation" do
    {:ok, session_id} = SessionStore.create_session(ttl: 100)  # 100ms TTL
    
    # Register variable
    {:ok, var_id} = SessionStore.register_variable(session_id, :test, :float, 1.0)
    
    # Wait for expiration
    Process.sleep(150)
    
    # Should fail gracefully
    assert {:error, :session_not_found} = 
      SessionStore.get_variable(session_id, var_id)
  end
  
  test "handles concurrent variable updates safely" do
    {:ok, session_id} = SessionStore.create_session()
    {:ok, var_id} = SessionStore.register_variable(session_id, :counter, :integer, 0)
    
    # Spawn 100 concurrent updates
    tasks = for i <- 1..100 do
      Task.async(fn ->
        SessionStore.update_variable(session_id, var_id, i)
      end)
    end
    
    # Wait for all updates
    Task.await_many(tasks)
    
    # Final value should be one of the updates (last write wins)
    {:ok, var} = SessionStore.get_variable(session_id, var_id)
    assert var.value in 1..100
  end
end
```

## Test Execution Strategy

### Continuous Integration Pipeline

```yaml
# .github/workflows/test.yml
name: Test Suite

on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Setup Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.14'
          otp-version: '25'
      
      - name: Run Elixir Unit Tests
        run: |
          mix deps.get
          mix test --only unit
      
      - name: Setup Python
        uses: actions/setup-python@v2
        with:
          python-version: '3.10'
      
      - name: Run Python Unit Tests
        run: |
          pip install -r requirements-test.txt
          pytest tests/ -m "not integration and not e2e"
  
  integration-tests:
    runs-on: ubuntu-latest
    needs: unit-tests
    steps:
      - name: Run Integration Tests
        run: |
          mix test --only integration
          pytest tests/ -m integration
  
  e2e-tests:
    runs-on: ubuntu-latest
    needs: integration-tests
    steps:
      - name: Run E2E Tests
        run: |
          # Start Elixir server in background
          mix run --no-halt &
          sleep 5
          
          # Run Python E2E tests
          pytest tests/ -m e2e
  
  performance-tests:
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - name: Run Performance Benchmarks
        run: |
          mix test --only performance
          pytest tests/ -m performance
          
      - name: Upload Benchmark Results
        uses: actions/upload-artifact@v2
        with:
          name: benchmarks
          path: benchmark_results/
```

### Local Development Testing

```bash
# Run all tests
make test

# Run specific test categories
make test-unit
make test-integration
make test-e2e

# Run with coverage
make test-coverage

# Run performance benchmarks
make benchmark

# Run load tests (requires more resources)
make test-load
```

## Test Data and Fixtures

### Elixir Test Helpers

```elixir
# test/support/test_tools.ex
defmodule TestTools do
  @moduledoc "Mock tool implementations for testing"
  
  def echo_handler(%{"message" => message}, _context) do
    {:ok, "Echo: #{message}"}
  end
  
  def mock_search(%{"query" => query} = args, _context) do
    # Simulate search with quality scores
    results = for i <- 1..5 do
      %{
        title: "Result #{i} for: #{query}",
        url: "https://example.com/#{i}",
        quality: :rand.uniform() * args["min_quality"] + args["min_quality"]
      }
    end
    
    {:ok, results}
  end
  
  def calculator_handler(%{"expression" => expr}, _context) do
    # Safe evaluation of simple math
    try do
      {result, _} = Code.eval_string(expr, [], __ENV__)
      {:ok, result}
    rescue
      _ -> {:error, "Invalid expression"}
    end
  end
end
```

### Python Test Fixtures

```python
# tests/conftest.py
import pytest
import asyncio
import grpc
from unittest.mock import Mock, AsyncMock

@pytest.fixture
def mock_channel():
    """Provides a mock gRPC channel."""
    return Mock(spec=grpc.aio.Channel)

@pytest.fixture
def session_context_with_stub(mock_channel):
    """Provides a SessionContext with mocked gRPC stub."""
    from dspex_bridge import SessionContext
    
    context = SessionContext("test_session", mock_channel)
    context.stub = AsyncMock()
    return context

@pytest.fixture
async def elixir_test_server():
    """Starts a real Elixir test server."""
    # Implementation would actually start Elixir process
    server = ElixirTestServer()
    await server.start(port=50054)
    yield server
    await server.stop()
```

## Debugging Failed Tests

### Enable Debug Logging

```elixir
# config/test.exs
config :logger, level: :debug
config :dspex, :grpc_debug, true
```

```python
# Enable gRPC debug logging
import logging
logging.basicConfig(level=logging.DEBUG)
grpc_logger = logging.getLogger('grpc')
grpc_logger.setLevel(logging.DEBUG)
```

### Common Issues and Solutions

1. **Port conflicts**: Use dynamic port allocation in tests
2. **Timing issues**: Use proper async/await and timeouts
3. **State leakage**: Ensure proper test isolation
4. **Resource cleanup**: Always close channels and connections

## Metrics and Reporting

Track these metrics across test runs:

1. **Test execution time**: Should remain stable
2. **Memory usage**: Check for leaks in long-running tests
3. **gRPC latency**: P50, P95, P99 percentiles
4. **Variable operation throughput**: Ops/second
5. **Concurrent session limit**: Maximum stable sessions

This comprehensive testing strategy ensures the unified gRPC bridge is robust, performant, and ready for production use.