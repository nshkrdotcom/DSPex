# gRPC Tool Bridge Testing Strategy

## Table of Contents

1. [Testing Philosophy](#testing-philosophy)
2. [Test Categories](#test-categories)
3. [Unit Testing](#unit-testing)
4. [Integration Testing](#integration-testing)
5. [End-to-End Testing](#end-to-end-testing)
6. [Failure Mode Testing](#failure-mode-testing)
7. [Performance Testing](#performance-testing)
8. [Test Infrastructure](#test-infrastructure)
9. [CI/CD Integration](#cicd-integration)

## Testing Philosophy

The gRPC tool bridge is a critical cross-language component that requires comprehensive testing at multiple levels:

1. **Test the Failures First**: Network issues, timeouts, and protocol errors are inevitable
2. **Mock the Boundaries**: Test each component in isolation before integration
3. **End-to-End is King**: The ultimate proof is a complete round-trip across languages
4. **Measure Everything**: Performance regressions must be caught early

## Test Categories

### Test Pyramid

```
        /\
       /  \  E2E Tests (10%)
      /    \  - Full system flows
     /      \  - Cross-language scenarios
    /--------\
   /          \ Integration Tests (30%)
  /            \ - gRPC communication
 /              \ - Protocol verification
/________________\
     Unit Tests (60%)
     - Component logic
     - Serialization
     - Error handling
```

## Unit Testing

### Python Unit Tests

#### Testing AsyncGRPCProxyTool

```python
# test_async_grpc_proxy_tool.py
import pytest
import asyncio
from unittest.mock import AsyncMock, MagicMock
import grpc

from grpc_tool_bridge import AsyncGRPCProxyTool, ToolExecutionError

class TestAsyncGRPCProxyTool:
    """Test the core proxy tool functionality."""
    
    @pytest.fixture
    def mock_session_context(self):
        """Create mock session context with gRPC stub."""
        context = MagicMock()
        context.session_id = "test_session_123"
        context.stub = AsyncMock()
        return context
    
    @pytest.fixture
    def tool_spec(self):
        """Sample tool specification."""
        return ToolSpec(
            tool_id="test_tool_456",
            name="calculate_sum",
            description="Adds two numbers",
            type=ToolType.STANDARD,
            arguments=[
                ArgumentSpec(name="a", python_type="int", required=True),
                ArgumentSpec(name="b", python_type="int", required=True)
            ]
        )
    
    @pytest.mark.asyncio
    async def test_successful_execution(self, mock_session_context, tool_spec):
        """Test successful tool execution."""
        # Arrange
        tool = AsyncGRPCProxyTool(tool_spec, mock_session_context)
        mock_response = MagicMock()
        mock_response.success = True
        mock_response.result = serialize_value(42)
        mock_session_context.stub.ExecuteTool.return_value = mock_response
        
        # Act
        result = await tool(5, 37)
        
        # Assert
        assert result == 42
        mock_session_context.stub.ExecuteTool.assert_called_once()
        call_args = mock_session_context.stub.ExecuteTool.call_args[0][0]
        assert call_args.tool_id == "test_tool_456"
        assert len(call_args.args) == 2
    
    @pytest.mark.asyncio
    async def test_execution_error(self, mock_session_context, tool_spec):
        """Test tool execution error handling."""
        # Arrange
        tool = AsyncGRPCProxyTool(tool_spec, mock_session_context)
        mock_response = MagicMock()
        mock_response.success = False
        mock_response.error.type = "ValidationError"
        mock_response.error.message = "Invalid input"
        mock_response.error.details = {"field": "a", "reason": "negative"}
        mock_session_context.stub.ExecuteTool.return_value = mock_response
        
        # Act & Assert
        with pytest.raises(ToolExecutionError) as exc_info:
            await tool(-5, 10)
        
        assert exc_info.value.tool_name == "calculate_sum"
        assert exc_info.value.error_type == "ValidationError"
        assert "Invalid input" in str(exc_info.value)
        assert exc_info.value.details["field"] == "a"
    
    @pytest.mark.asyncio
    async def test_grpc_error(self, mock_session_context, tool_spec):
        """Test gRPC communication error handling."""
        # Arrange
        tool = AsyncGRPCProxyTool(tool_spec, mock_session_context)
        mock_session_context.stub.ExecuteTool.side_effect = grpc.aio.AioRpcError(
            code=grpc.StatusCode.UNAVAILABLE,
            details="Service unavailable"
        )
        
        # Act & Assert
        with pytest.raises(ToolCommunicationError) as exc_info:
            await tool(5, 10)
        
        assert exc_info.value.tool_name == "calculate_sum"
        assert exc_info.value.code == grpc.StatusCode.UNAVAILABLE
    
    @pytest.mark.asyncio
    async def test_timeout(self, mock_session_context, tool_spec):
        """Test execution timeout handling."""
        # Arrange
        tool = AsyncGRPCProxyTool(tool_spec, mock_session_context)
        
        async def slow_execution(*args):
            await asyncio.sleep(60)  # Longer than timeout
            
        mock_session_context.stub.ExecuteTool = slow_execution
        
        # Act & Assert
        with pytest.raises(asyncio.TimeoutError):
            # Override default timeout for test
            await asyncio.wait_for(tool(5, 10), timeout=0.1)
```

#### Testing Serialization

```python
# test_serialization.py
import pytest
import pandas as pd
from google.protobuf.wrappers_pb2 import StringValue, Int64Value
from google.protobuf.any_pb2 import Any

from grpc_tool_bridge import serialize_value, deserialize_value

class TestSerialization:
    """Test value serialization/deserialization."""
    
    @pytest.mark.parametrize("value,expected_type", [
        ("hello", StringValue),
        (42, Int64Value),
        (3.14, DoubleValue),
        (True, BoolValue),
        (None, NullValue),
        ([1, 2, 3], ListValue),
        ({"key": "value"}, Struct)
    ])
    def test_basic_types(self, value, expected_type):
        """Test serialization of basic Python types."""
        # Act
        serialized = serialize_value(value)
        deserialized = deserialize_value(serialized)
        
        # Assert
        assert isinstance(serialized, Any)
        assert deserialized == value
    
    def test_dataframe_serialization(self):
        """Test pandas DataFrame serialization."""
        # Arrange
        df = pd.DataFrame({
            'A': [1, 2, 3],
            'B': ['x', 'y', 'z']
        })
        
        # Act
        serialized = serialize_value(df)
        deserialized = deserialize_value(serialized)
        
        # Assert
        assert isinstance(deserialized, pd.DataFrame)
        pd.testing.assert_frame_equal(df, deserialized)
        assert serialized.type_url == "type.googleapis.com/pandas.DataFrame"
    
    def test_nested_structures(self):
        """Test complex nested data structures."""
        # Arrange
        data = {
            "users": [
                {"id": 1, "name": "Alice", "scores": [95, 87, 92]},
                {"id": 2, "name": "Bob", "scores": [88, 91, 85]}
            ],
            "metadata": {
                "version": "1.0",
                "count": 2
            }
        }
        
        # Act
        serialized = serialize_value(data)
        deserialized = deserialize_value(serialized)
        
        # Assert
        assert deserialized == data
    
    def test_unknown_type_fallback(self):
        """Test serialization of unknown types."""
        # Arrange
        class CustomObject:
            def __str__(self):
                return "custom_object"
        
        obj = CustomObject()
        
        # Act
        serialized = serialize_value(obj)
        deserialized = deserialize_value(serialized)
        
        # Assert
        assert deserialized == "custom_object"
        assert "python.CustomObject" in serialized.type_url
```

### Elixir Unit Tests

#### Testing SessionStore

```elixir
# test/dspex/bridge/session_store_test.exs
defmodule DSPex.Bridge.SessionStoreTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Bridge.SessionStore
  
  setup do
    # Start a fresh SessionStore for each test
    {:ok, pid} = SessionStore.start_link()
    %{store: pid}
  end
  
  describe "session management" do
    test "creates and retrieves session", %{store: store} do
      # Create session
      assert {:ok, session} = SessionStore.create_session("test_123", %{})
      assert session.id == "test_123"
      
      # Retrieve session
      assert {:ok, retrieved} = SessionStore.get_session("test_123")
      assert retrieved.id == "test_123"
    end
    
    test "handles non-existent session", %{store: store} do
      assert {:error, :not_found} = SessionStore.get_session("missing")
    end
    
    test "prevents duplicate sessions", %{store: store} do
      assert {:ok, _} = SessionStore.create_session("dup_123", %{})
      assert {:error, :already_exists} = SessionStore.create_session("dup_123", %{})
    end
  end
  
  describe "tool management" do
    setup %{store: store} do
      {:ok, _} = SessionStore.create_session("session_123", %{})
      
      tools = [
        %{id: "tool_1", name: "search", type: :external},
        %{id: "tool_2", name: "calculate", type: :standard}
      ]
      
      {:ok, tools: tools}
    end
    
    test "registers tools for session", %{store: store, tools: tools} do
      assert :ok = SessionStore.register_tools("session_123", tools)
      
      # Verify tools are stored
      assert {:ok, tool} = SessionStore.get_tool("session_123", "tool_1")
      assert tool.name == "search"
    end
    
    test "isolation between sessions", %{store: store, tools: tools} do
      # Register tools for first session
      SessionStore.register_tools("session_123", tools)
      
      # Create second session
      {:ok, _} = SessionStore.create_session("session_456", %{})
      
      # Tools from first session not accessible
      assert {:error, :not_found} = SessionStore.get_tool("session_456", "tool_1")
    end
  end
  
  describe "variable management" do
    setup %{store: store} do
      {:ok, _} = SessionStore.create_session("session_123", %{})
      :ok
    end
    
    test "sets and gets variables", %{store: store} do
      # Set variable
      assert :ok = SessionStore.set_variable("session_123", "threshold", 0.95)
      
      # Get variable
      assert {:ok, 0.95} = SessionStore.get_variable("session_123", "threshold")
    end
    
    test "variable metadata", %{store: store} do
      metadata = %{type: "float", created_by: "elixir"}
      assert :ok = SessionStore.set_variable("session_123", "score", 85.5, metadata)
      
      assert {:ok, value, meta} = SessionStore.get_variable_with_metadata(
        "session_123", 
        "score"
      )
      assert value == 85.5
      assert meta.type == "float"
    end
  end
  
  describe "cleanup" do
    test "removes session and associated data", %{store: store} do
      # Setup session with tools and variables
      {:ok, _} = SessionStore.create_session("cleanup_123", %{})
      SessionStore.register_tools("cleanup_123", [%{id: "t1", name: "tool"}])
      SessionStore.set_variable("cleanup_123", "var", "value")
      
      # Cleanup
      assert :ok = SessionStore.cleanup_session("cleanup_123")
      
      # Verify everything is gone
      assert {:error, :not_found} = SessionStore.get_session("cleanup_123")
      assert {:error, :not_found} = SessionStore.get_tool("cleanup_123", "t1")
      assert {:error, :not_found} = SessionStore.get_variable("cleanup_123", "var")
    end
  end
end
```

## Integration Testing

### gRPC Mock Testing

#### Python Side with Mock gRPC Server

```python
# test_grpc_integration.py
import pytest
import grpc
from grpc_testing import server_from_dictionary, strict_real_time

from dspex_bridge_pb2 import *
from grpc_tool_bridge import ToolBridgeClient

class TestGRPCIntegration:
    """Test gRPC communication with mock server."""
    
    @pytest.fixture
    def mock_grpc_server(self):
        """Create mock gRPC server for testing."""
        # Define service behavior
        servicer = MockSnakepitBridgeServicer()
        services = {
            dspex_bridge_pb2.DESCRIPTOR.services_by_name['SnakepitBridge']: servicer
        }
        
        # Create test server
        return server_from_dictionary(services, strict_real_time())
    
    @pytest.mark.asyncio
    async def test_session_initialization(self, mock_grpc_server):
        """Test session initialization flow."""
        # Arrange
        with mock_grpc_server as server:
            channel = server.channel()
            client = ToolBridgeClient(channel)
            
            # Setup expected response
            server.set_response(
                'InitializeSession',
                InitializeSessionResponse(
                    success=True,
                    tool_count=3,
                    capabilities=["streaming", "variables"]
                )
            )
            
            # Act
            result = await client.initialize_session("test_session")
            
            # Assert
            assert result is True
            assert client.session_id == "test_session"
            
            # Verify request
            requests = server.requests_for('InitializeSession')
            assert len(requests) == 1
            assert requests[0].session_id == "test_session"
    
    @pytest.mark.asyncio
    async def test_tool_execution_success(self, mock_grpc_server):
        """Test successful tool execution."""
        with mock_grpc_server as server:
            channel = server.channel()
            client = ToolBridgeClient(channel)
            client.session_id = "test_session"
            
            # Setup response
            server.set_response(
                'ExecuteTool',
                ToolCallResponse(
                    success=True,
                    result=serialize_value({"answer": 42}),
                    metrics=ExecutionMetrics(duration_ms=15)
                )
            )
            
            # Execute
            result = await client.execute_tool("calculate", 40, 2)
            
            # Verify
            assert result == {"answer": 42}
    
    @pytest.mark.asyncio
    async def test_streaming_tool(self, mock_grpc_server):
        """Test streaming tool execution."""
        with mock_grpc_server as server:
            channel = server.channel()
            client = ToolBridgeClient(channel)
            client.session_id = "test_session"
            
            # Setup streaming response
            chunks = [
                ToolStreamChunk(
                    stream_id="stream_1",
                    sequence=0,
                    content={"data": serialize_value("chunk_1")}
                ),
                ToolStreamChunk(
                    stream_id="stream_1",
                    sequence=1,
                    content={"data": serialize_value("chunk_2")}
                ),
                ToolStreamChunk(
                    stream_id="stream_1",
                    sequence=2,
                    content={"complete": CompleteSignal(total_chunks=2)}
                )
            ]
            server.set_streaming_response('StreamTool', chunks)
            
            # Execute and collect results
            results = []
            async for chunk in client.stream_tool("process_data", [1, 2, 3]):
                results.append(chunk)
            
            # Verify
            assert results == ["chunk_1", "chunk_2"]
```

#### Elixir Side with Mock Python Client

```elixir
# test/dspex/grpc/bridge_server_integration_test.exs
defmodule DSPex.GRPC.BridgeServerIntegrationTest do
  use ExUnit.Case
  
  alias DSPex.GRPC.BridgeServer
  alias DSPex.Bridge.SessionStore
  alias DSPex.Tools.Registry
  
  setup do
    # Start required services
    start_supervised!(SessionStore)
    start_supervised!(Registry)
    
    # Create test session
    {:ok, _} = SessionStore.create_session("test_session", %{})
    
    # Register test tools
    tools = [
      %{
        id: "add_numbers",
        name: "add_numbers",
        type: :standard,
        func: fn [a, b], _kwargs -> {:ok, a + b} end
      }
    ]
    Registry.register_batch("test_session", tools)
    
    :ok
  end
  
  describe "tool execution" do
    test "executes tool successfully" do
      # Prepare request
      request = %ToolCallRequest{
        session_id: "test_session",
        tool_id: "add_numbers",
        args: [serialize_value(5), serialize_value(3)],
        kwargs: %{},
        request_id: "req_123"
      }
      
      # Execute
      response = BridgeServer.execute_tool(request, nil)
      
      # Verify
      assert response.success == true
      assert deserialize_value(response.result) == 8
      assert response.request_id == "req_123"
      assert response.metrics.duration_ms > 0
    end
    
    test "handles tool not found" do
      request = %ToolCallRequest{
        session_id: "test_session",
        tool_id: "missing_tool",
        args: [],
        kwargs: %{}
      }
      
      response = BridgeServer.execute_tool(request, nil)
      
      assert response.success == false
      assert response.error.type == "ToolNotFound"
    end
    
    test "handles invalid arguments" do
      request = %ToolCallRequest{
        session_id: "test_session",
        tool_id: "add_numbers",
        args: [serialize_value("not_a_number")],
        kwargs: %{}
      }
      
      response = BridgeServer.execute_tool(request, nil)
      
      assert response.success == false
      assert response.error.type == "ValidationError"
    end
  end
  
  describe "streaming execution" do
    test "streams results progressively" do
      # Register streaming tool
      streaming_tool = %{
        id: "count_to_n",
        name: "count_to_n",
        type: :streaming,
        func: fn [n], _kwargs, callback ->
          for i <- 1..n do
            callback.({:data, i})
            Process.sleep(10)
          end
          callback.({:complete, :ok})
        end
      }
      Registry.register_batch("test_session", [streaming_tool])
      
      # Create mock stream
      stream = MockGRPCStream.new()
      
      request = %ToolStreamRequest{
        session_id: "test_session",
        tool_id: "count_to_n",
        args: [serialize_value(3)],
        stream_id: "stream_123"
      }
      
      # Execute
      BridgeServer.stream_tool(request, stream)
      
      # Wait for completion
      Process.sleep(100)
      
      # Verify chunks
      chunks = MockGRPCStream.get_chunks(stream)
      assert length(chunks) == 4  # 3 data + 1 complete
      
      data_chunks = Enum.filter(chunks, &match?(%{content: {:data, _}}, &1))
      assert Enum.map(data_chunks, fn c -> 
        deserialize_value(c.content.data) 
      end) == [1, 2, 3]
      
      complete_chunk = List.last(chunks)
      assert match?(%{content: {:complete, _}}, complete_chunk)
    end
  end
end
```

## End-to-End Testing

### Complete Round-Trip Test

```python
# test_e2e_round_trip.py
import pytest
import asyncio
import subprocess
import time

from grpc_tool_bridge import GRPCToolBridge

class TestEndToEnd:
    """Full system integration tests."""
    
    @pytest.fixture(scope="module")
    def elixir_server(self):
        """Start real Elixir gRPC server."""
        # Start Elixir application
        proc = subprocess.Popen(
            ["mix", "run", "--no-halt"],
            cwd="../../../",  # Project root
            env={**os.environ, "MIX_ENV": "test", "GRPC_PORT": "50051"}
        )
        
        # Wait for server to start
        time.sleep(5)
        
        yield "localhost:50051"
        
        # Cleanup
        proc.terminate()
        proc.wait()
    
    @pytest.mark.asyncio
    async def test_complete_tool_flow(self, elixir_server):
        """Test complete flow: Python -> Elixir -> Python -> Elixir."""
        # Initialize bridge
        bridge = GRPCToolBridge(elixir_server)
        session_id = "e2e_test_session"
        
        # Step 1: Initialize session (Python -> Elixir)
        tools = await bridge.initialize(session_id)
        assert len(tools) > 0
        
        # Step 2: Execute a tool (Python -> Elixir)
        search_tool = tools.get("search_web")
        assert search_tool is not None
        
        results = await search_tool("DSPy framework")
        assert isinstance(results, list)
        assert len(results) > 0
        
        # Step 3: Set a variable (Python -> Elixir)
        await bridge.client.session_context.set_variable(
            "search_results", 
            results
        )
        
        # Step 4: Create ReAct agent (Python -> Elixir)
        agent_id = await bridge.create_react_agent(
            "Question -> Answer",
            tool_names=["search_web", "calculate"],
            max_iters=3
        )
        
        # Step 5: Execute agent (Elixir -> Python -> Elixir)
        # This triggers the full round-trip:
        # - Elixir calls Python to run agent
        # - Python agent calls back to Elixir to execute tools
        # - Results flow back through the layers
        
        agent_request = {
            "agent_id": agent_id,
            "input": {"question": "What is 2 + 2?"},
            "stream": True
        }
        
        chunks = []
        async for chunk in bridge.execute_agent_streaming(agent_request):
            chunks.append(chunk)
        
        # Verify we got thought/action/observation chunks
        thought_chunks = [c for c in chunks if c.get("type") == "thought"]
        action_chunks = [c for c in chunks if c.get("type") == "action"]
        result_chunks = [c for c in chunks if c.get("type") == "result"]
        
        assert len(thought_chunks) > 0
        assert len(action_chunks) > 0
        assert len(result_chunks) == 1
        
        # Verify final answer
        final_answer = result_chunks[0]["final_answer"]
        assert "4" in str(final_answer)
    
    @pytest.mark.asyncio
    async def test_concurrent_sessions(self, elixir_server):
        """Test multiple concurrent sessions."""
        # Create multiple bridges
        bridges = [
            GRPCToolBridge(elixir_server) for _ in range(5)
        ]
        
        # Initialize all sessions concurrently
        session_ids = [f"concurrent_session_{i}" for i in range(5)]
        
        init_tasks = [
            bridge.initialize(sid) 
            for bridge, sid in zip(bridges, session_ids)
        ]
        
        tools_list = await asyncio.gather(*init_tasks)
        
        # All should succeed
        assert all(len(tools) > 0 for tools in tools_list)
        
        # Execute tools concurrently
        exec_tasks = []
        for bridge, tools in zip(bridges, tools_list):
            tool = list(tools.values())[0]
            exec_tasks.append(tool("test_input"))
        
        results = await asyncio.gather(*exec_tasks, return_exceptions=True)
        
        # Verify no cross-session interference
        errors = [r for r in results if isinstance(r, Exception)]
        assert len(errors) == 0
```

## Failure Mode Testing

### Network Failure Scenarios

```python
# test_failure_modes.py
import pytest
import asyncio
import grpc
from unittest.mock import patch, AsyncMock

class TestFailureModes:
    """Test various failure scenarios."""
    
    @pytest.mark.asyncio
    async def test_connection_drop_during_stream(self):
        """Test handling of connection drop during streaming."""
        bridge = GRPCToolBridge("localhost:50051")
        await bridge.initialize("failure_test")
        
        # Mock connection drop after 2 chunks
        original_stream = bridge.client.stub.StreamTool
        chunks_sent = 0
        
        async def failing_stream(*args, **kwargs):
            async for chunk in original_stream(*args, **kwargs):
                nonlocal chunks_sent
                chunks_sent += 1
                if chunks_sent > 2:
                    raise grpc.aio.AioRpcError(
                        code=grpc.StatusCode.UNAVAILABLE,
                        details="Connection lost"
                    )
                yield chunk
        
        bridge.client.stub.StreamTool = failing_stream
        
        # Execute streaming tool
        tool = bridge.tools["large_data_processor"]
        results = []
        
        with pytest.raises(ToolCommunicationError) as exc_info:
            async for chunk in tool.stream(range(1000)):
                results.append(chunk)
        
        # Verify partial results were received
        assert len(results) == 2
        assert exc_info.value.code == grpc.StatusCode.UNAVAILABLE
    
    @pytest.mark.asyncio
    async def test_timeout_recovery(self):
        """Test timeout and retry mechanism."""
        bridge = GRPCToolBridge("localhost:50051")
        await bridge.initialize("timeout_test")
        
        # Mock slow tool
        call_count = 0
        
        async def slow_then_fast(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            
            if call_count == 1:
                # First call times out
                await asyncio.sleep(40)  # Longer than timeout
            else:
                # Retry succeeds quickly
                return ToolCallResponse(
                    success=True,
                    result=serialize_value("success")
                )
        
        bridge.client.stub.ExecuteTool = slow_then_fast
        
        # Execute with retry
        tool = bridge.tools["flaky_tool"]
        result = await bridge.execute_with_retry("flaky_tool", max_retries=2)
        
        # Verify retry worked
        assert result == "success"
        assert call_count == 2
    
    @pytest.mark.asyncio
    async def test_elixir_crash_recovery(self):
        """Test handling when Elixir process crashes."""
        bridge = GRPCToolBridge("localhost:50051")
        session_id = "crash_test"
        await bridge.initialize(session_id)
        
        # Simulate Elixir crash by killing session
        # (In real test, would actually crash the process)
        await bridge.client.stub.CleanupSession(
            CleanupSessionRequest(session_id=session_id, force=True)
        )
        
        # Try to use tool after crash
        tool = bridge.tools["any_tool"]
        
        with pytest.raises(ToolExecutionError) as exc_info:
            await tool("input")
        
        assert exc_info.value.error_type == "SessionExpired"
    
    @pytest.mark.asyncio
    async def test_malformed_protobuf(self):
        """Test handling of malformed protobuf messages."""
        bridge = GRPCToolBridge("localhost:50051")
        
        # Mock malformed response
        async def bad_response(*args, **kwargs):
            # Return object missing required fields
            return MagicMock(spec=ToolCallResponse)
        
        bridge.client.stub.ExecuteTool = bad_response
        
        with pytest.raises(ProtocolError):
            await bridge.execute_tool("any_tool", "input")
    
    @pytest.mark.asyncio
    async def test_rate_limit_handling(self):
        """Test rate limit error handling."""
        bridge = GRPCToolBridge("localhost:50051")
        await bridge.initialize("rate_limit_test")
        
        # Mock rate limit response
        bridge.client.stub.ExecuteTool = AsyncMock(
            return_value=ToolCallResponse(
                success=False,
                error=ErrorInfo(
                    type="RateLimitExceeded",
                    message="Too many requests",
                    details={"retry_after": "10"}
                )
            )
        )
        
        # Execute with retry
        start_time = time.time()
        
        with pytest.raises(ToolExecutionError) as exc_info:
            await bridge.execute_with_retry(
                "rate_limited_tool",
                max_retries=1
            )
        
        # Verify backoff was applied
        elapsed = time.time() - start_time
        assert elapsed >= 10  # Should have waited at least 10 seconds
        assert exc_info.value.error_type == "RateLimitExceeded"
```

### Memory and Resource Testing

```python
# test_resource_limits.py
import pytest
import psutil
import os

class TestResourceLimits:
    """Test resource consumption and limits."""
    
    @pytest.mark.asyncio
    async def test_large_payload_handling(self):
        """Test handling of large payloads."""
        bridge = GRPCToolBridge("localhost:50051")
        await bridge.initialize("large_payload_test")
        
        # Create large data structure (9MB - under 10MB limit)
        large_data = "x" * (9 * 1024 * 1024)
        
        # Should succeed
        tool = bridge.tools["echo_tool"]
        result = await tool(large_data)
        assert len(result) == len(large_data)
        
        # Create too-large data (11MB - over limit)
        too_large = "x" * (11 * 1024 * 1024)
        
        # Should fail with appropriate error
        with pytest.raises(ToolExecutionError) as exc_info:
            await tool(too_large)
        
        assert "message too large" in str(exc_info.value).lower()
    
    @pytest.mark.asyncio
    async def test_memory_leak_detection(self):
        """Test for memory leaks in long-running operations."""
        bridge = GRPCToolBridge("localhost:50051")
        await bridge.initialize("memory_test")
        
        process = psutil.Process(os.getpid())
        initial_memory = process.memory_info().rss / 1024 / 1024  # MB
        
        # Execute many operations
        tool = bridge.tools["simple_tool"]
        for i in range(1000):
            await tool(f"iteration_{i}")
            
            # Check memory every 100 iterations
            if i % 100 == 0:
                current_memory = process.memory_info().rss / 1024 / 1024
                memory_growth = current_memory - initial_memory
                
                # Memory growth should be bounded
                assert memory_growth < 100  # Less than 100MB growth
        
        # Force garbage collection
        import gc
        gc.collect()
        
        # Memory should return close to initial
        final_memory = process.memory_info().rss / 1024 / 1024
        assert final_memory - initial_memory < 50  # Less than 50MB retained
```

## Performance Testing

### Benchmarks

```python
# test_performance.py
import pytest
import time
import statistics
from concurrent.futures import ThreadPoolExecutor
import asyncio

class TestPerformance:
    """Performance benchmarks."""
    
    @pytest.mark.benchmark
    async def test_tool_latency(self, benchmark):
        """Benchmark single tool call latency."""
        bridge = GRPCToolBridge("localhost:50051")
        await bridge.initialize("perf_test")
        tool = bridge.tools["fast_tool"]
        
        # Warmup
        for _ in range(10):
            await tool("warmup")
        
        # Benchmark
        async def single_call():
            return await tool("benchmark_input")
        
        result = await benchmark(single_call)
        
        # Assert performance requirements
        assert benchmark.stats["mean"] < 0.005  # Less than 5ms average
        assert benchmark.stats["max"] < 0.030   # Less than 30ms max
    
    @pytest.mark.asyncio
    async def test_streaming_throughput(self):
        """Test streaming data throughput."""
        bridge = GRPCToolBridge("localhost:50051")
        await bridge.initialize("stream_perf_test")
        
        # Generate 10MB of data in 64KB chunks
        chunk_size = 64 * 1024
        num_chunks = (10 * 1024 * 1024) // chunk_size
        
        tool = bridge.tools["stream_processor"]
        chunks_received = 0
        start_time = time.time()
        
        async for chunk in tool.stream(num_chunks):
            chunks_received += 1
        
        elapsed = time.time() - start_time
        throughput_mbps = (10 / elapsed)
        
        # Performance assertions
        assert chunks_received == num_chunks
        assert throughput_mbps > 50  # At least 50MB/s
        print(f"Streaming throughput: {throughput_mbps:.2f} MB/s")
    
    @pytest.mark.asyncio
    async def test_concurrent_tool_scaling(self):
        """Test performance with concurrent tool calls."""
        bridge = GRPCToolBridge("localhost:50051")
        await bridge.initialize("concurrent_perf_test")
        tool = bridge.tools["cpu_bound_tool"]
        
        # Test different concurrency levels
        concurrency_levels = [1, 10, 50, 100]
        results = {}
        
        for level in concurrency_levels:
            start_time = time.time()
            
            # Execute concurrent calls
            tasks = [
                tool(f"task_{i}") 
                for i in range(level)
            ]
            await asyncio.gather(*tasks)
            
            elapsed = time.time() - start_time
            throughput = level / elapsed
            results[level] = throughput
            
            print(f"Concurrency {level}: {throughput:.2f} calls/sec")
        
        # Verify scaling
        # Throughput should increase with concurrency (up to a point)
        assert results[10] > results[1] * 5   # At least 5x speedup
        assert results[50] > results[10] * 2  # Continued scaling
    
    @pytest.mark.asyncio
    async def test_batch_vs_sequential(self):
        """Compare batch vs sequential execution."""
        bridge = GRPCToolBridge("localhost:50051")
        await bridge.initialize("batch_perf_test")
        
        # Prepare 50 tool calls
        requests = [
            {"tool_id": "compute_tool", "args": [i], "kwargs": {}}
            for i in range(50)
        ]
        
        # Sequential execution
        seq_start = time.time()
        seq_results = []
        for req in requests:
            result = await bridge.execute_tool(**req)
            seq_results.append(result)
        seq_time = time.time() - seq_start
        
        # Batch execution
        batch_start = time.time()
        batch_results = await bridge.execute_batch(requests)
        batch_time = time.time() - batch_start
        
        # Verify results match
        assert seq_results == batch_results
        
        # Batch should be significantly faster
        speedup = seq_time / batch_time
        assert speedup > 5  # At least 5x faster
        print(f"Batch speedup: {speedup:.2f}x")
```

### Load Testing

```python
# test_load.py
import asyncio
import random
from locust import task, between, events
from locust.contrib.fasthttp import FastHttpUser

class ToolBridgeLoadTest(FastHttpUser):
    """Load test for tool bridge."""
    
    wait_time = between(0.1, 0.5)
    
    def on_start(self):
        """Initialize session for user."""
        self.session_id = f"load_test_{random.randint(1000, 9999)}"
        self.tool_ids = ["search", "calculate", "process"]
        
        # Initialize session via gRPC
        # (In practice, might use HTTP gateway)
        response = self.client.post(
            "/api/sessions",
            json={"session_id": self.session_id}
        )
        response.raise_for_status()
    
    @task(weight=70)
    def execute_tool(self):
        """Execute a random tool."""
        tool_id = random.choice(self.tool_ids)
        
        with self.client.post(
            f"/api/sessions/{self.session_id}/tools/{tool_id}/execute",
            json={
                "args": [random.randint(1, 100)],
                "kwargs": {"option": random.choice(["A", "B", "C"])}
            },
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Got status {response.status_code}")
    
    @task(weight=20)
    def stream_tool(self):
        """Execute streaming tool."""
        with self.client.get(
            f"/api/sessions/{self.session_id}/tools/stream_data/stream",
            stream=True,
            catch_response=True
        ) as response:
            chunks = 0
            for chunk in response.iter_lines():
                chunks += 1
                if chunks > 100:  # Limit chunks in test
                    break
            
            if chunks > 0:
                response.success()
            else:
                response.failure("No chunks received")
    
    @task(weight=10)
    def batch_execute(self):
        """Execute batch of tools."""
        batch = [
            {
                "tool_id": random.choice(self.tool_ids),
                "args": [i],
                "kwargs": {}
            }
            for i in range(random.randint(5, 15))
        ]
        
        with self.client.post(
            f"/api/sessions/{self.session_id}/tools/batch",
            json={"requests": batch},
            catch_response=True
        ) as response:
            if response.status_code == 200:
                results = response.json()["results"]
                if len(results) == len(batch):
                    response.success()
                else:
                    response.failure("Incomplete batch results")
            else:
                response.failure(f"Got status {response.status_code}")
```

## Test Infrastructure

### Docker Compose for Testing

```yaml
# docker-compose.test.yml
version: '3.8'

services:
  elixir:
    build:
      context: .
      dockerfile: Dockerfile.test
    environment:
      - MIX_ENV=test
      - GRPC_PORT=50051
    ports:
      - "50051:50051"
    volumes:
      - ./test/fixtures:/app/test/fixtures
    healthcheck:
      test: ["CMD", "grpcurl", "-plaintext", "localhost:50051", "list"]
      interval: 5s
      timeout: 2s
      retries: 5

  python:
    build:
      context: ./snakepit
      dockerfile: Dockerfile.test
    depends_on:
      elixir:
        condition: service_healthy
    environment:
      - ELIXIR_GRPC_ADDR=elixir:50051
      - PYTHONPATH=/app
    volumes:
      - ./snakepit/tests:/app/tests
      - ./test-results:/app/test-results
    command: pytest -v --junit-xml=/app/test-results/junit.xml

  toxiproxy:
    image: shopify/toxiproxy
    ports:
      - "8474:8474"  # API
      - "50052:50052"  # Proxied gRPC
    command: ["-host=0.0.0.0", "-config=/config/toxiproxy.json"]
    volumes:
      - ./test/toxiproxy.json:/config/toxiproxy.json
```

### Test Fixtures

```python
# conftest.py
import pytest
import asyncio
import tempfile
import shutil

@pytest.fixture(scope="session")
def event_loop():
    """Create event loop for async tests."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()

@pytest.fixture
def temp_workspace():
    """Create temporary workspace for tests."""
    workspace = tempfile.mkdtemp()
    yield workspace
    shutil.rmtree(workspace)

@pytest.fixture
def mock_llm():
    """Mock LLM for testing agents."""
    class MockLLM:
        async def generate(self, prompt, **kwargs):
            # Return deterministic responses for testing
            if "calculate" in prompt.lower():
                return "I need to calculate 2 + 2. Let me use the calculator tool."
            elif "search" in prompt.lower():
                return "I'll search for that information."
            else:
                return "Based on the information provided, the answer is 42."
    
    return MockLLM()
```

## CI/CD Integration

### GitHub Actions Workflow

```yaml
# .github/workflows/test-tool-bridge.yml
name: Tool Bridge Tests

on:
  push:
    paths:
      - 'lib/dspex/bridge/**'
      - 'lib/dspex/grpc/**'
      - 'snakepit/priv/python/grpc_tool_bridge/**'
      - 'protos/**'
  pull_request:

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        include:
          - language: elixir
            otp: 25
            elixir: 1.14
          - language: python
            python: 3.9
          - language: python
            python: 3.11
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Elixir
        if: matrix.language == 'elixir'
        uses: erlef/setup-beam@v1
        with:
          otp-version: ${{ matrix.otp }}
          elixir-version: ${{ matrix.elixir }}
      
      - name: Setup Python
        if: matrix.language == 'python'
        uses: actions/setup-python@v4
        with:
          python-version: ${{ matrix.python }}
      
      - name: Install dependencies
        run: |
          if [ "${{ matrix.language }}" = "elixir" ]; then
            mix deps.get
            mix compile
          else
            pip install -r requirements-test.txt
          fi
      
      - name: Run unit tests
        run: |
          if [ "${{ matrix.language }}" = "elixir" ]; then
            mix test --only unit
          else
            pytest tests/unit -v --cov=grpc_tool_bridge
          fi
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3

  integration-tests:
    runs-on: ubuntu-latest
    needs: unit-tests
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Start services
        run: docker-compose -f docker-compose.test.yml up -d
      
      - name: Run integration tests
        run: |
          docker-compose -f docker-compose.test.yml \
            run --rm python \
            pytest tests/integration -v -s
      
      - name: Run E2E tests
        run: |
          docker-compose -f docker-compose.test.yml \
            run --rm python \
            pytest tests/e2e -v -s --tb=short
      
      - name: Collect logs
        if: failure()
        run: |
          docker-compose -f docker-compose.test.yml logs > test-logs.txt
          
      - name: Upload test artifacts
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: test-results
          path: |
            test-results/
            test-logs.txt

  performance-tests:
    runs-on: ubuntu-latest
    needs: integration-tests
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Start services
        run: docker-compose -f docker-compose.test.yml up -d
      
      - name: Run benchmarks
        run: |
          docker-compose -f docker-compose.test.yml \
            run --rm python \
            pytest tests/performance -v --benchmark-only \
            --benchmark-json=benchmark-results.json
      
      - name: Store benchmark results
        uses: benchmark-action/github-action-benchmark@v1
        with:
          tool: 'pytest'
          output-file-path: benchmark-results.json
          github-token: ${{ secrets.GITHUB_TOKEN }}
          auto-push: true
      
      - name: Check performance regression
        run: |
          python scripts/check_performance_regression.py \
            --current benchmark-results.json \
            --threshold 10  # Allow 10% regression

  chaos-tests:
    runs-on: ubuntu-latest
    needs: integration-tests
    if: github.event_name == 'pull_request'
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Start services with Toxiproxy
        run: |
          docker-compose -f docker-compose.test.yml up -d
          sleep 10
      
      - name: Configure network failures
        run: |
          # Add latency
          curl -X POST http://localhost:8474/proxies/grpc/toxics \
            -d '{"type":"latency","attributes":{"latency":100}}'
          
          # Add random connection drops
          curl -X POST http://localhost:8474/proxies/grpc/toxics \
            -d '{"type":"timeout","attributes":{"timeout":500}}'
      
      - name: Run failure mode tests
        run: |
          docker-compose -f docker-compose.test.yml \
            run --rm -e GRPC_ADDR=toxiproxy:50052 python \
            pytest tests/failure_modes -v -s
```

## Summary

This comprehensive testing strategy ensures the gRPC tool bridge is:

1. **Robust**: Extensive failure mode testing catches edge cases
2. **Performant**: Automated benchmarks prevent regressions
3. **Reliable**: E2E tests verify the complete system works
4. **Maintainable**: Clear test structure and good coverage

The multi-layered approach catches issues at the appropriate level, from unit tests for basic logic to chaos tests for production resilience. Integration with CI/CD ensures quality gates are enforced on every change.