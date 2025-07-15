defmodule DSPex.PythonBridge.PoolErrorHandlerTest do
  use ExUnit.Case, async: true
  
  alias DSPex.PythonBridge.PoolErrorHandler
  
  describe "error categorization" do
    test "categorizes connection errors correctly" do
      error = {:port_exited, 1}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.error_category == :connection_error
      
      error = {:connect_failed, "connection refused"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.error_category == :connection_error
    end
    
    test "categorizes timeout errors correctly" do
      error = {:timeout, "operation timeout"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.error_category == :timeout_error
      
      error = :timeout
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.error_category == :timeout_error
    end
    
    test "categorizes communication errors correctly" do
      error = {:encode_error, "invalid format"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.error_category == :communication_error
      
      error = {:decode_error, "malformed data"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.error_category == :communication_error
    end
    
    test "categorizes health check errors correctly" do
      error = {:health_check_failed, :timeout}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.error_category == :health_check_error
    end
    
    test "categorizes python errors correctly" do
      error = {:python_exception, "ZeroDivisionError"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.error_category == :python_error
      
      error = {:bridge_error, %{type: :runtime_error}}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.error_category == :python_error
    end
    
    test "categorizes resource errors correctly" do
      error = {:checkout_failed, "pool exhausted"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.error_category == :resource_error
      
      error = {:pool_exhausted, "no workers available"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.error_category == :resource_error
    end
    
    test "categorizes session errors correctly" do
      error = {:session_not_found, "session_123"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.error_category == :session_error
      
      error = {:session_expired, "session_456"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.error_category == :session_error
    end
    
    test "categorizes unknown errors as system errors" do
      error = {:unknown_error, "something went wrong"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.error_category == :system_error
      
      # String errors are now classified as communication errors (retryable)
      error = "random string error"
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.error_category == :communication_error
    end
  end
  
  describe "severity determination" do
    test "assigns critical severity to initialization errors" do
      error = {:init_failed, "worker startup failed"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.severity == :critical
    end
    
    test "assigns critical severity to resource errors" do
      error = {:checkout_failed, "pool exhausted"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.severity == :critical
    end
    
    test "assigns major severity to connection errors" do
      error = {:port_exited, 1}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.severity == :major
    end
    
    test "assigns minor severity to health check errors" do
      error = {:health_check_failed, :timeout}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.severity == :minor
    end
    
    test "upgrades severity based on attempt count" do
      context = %{attempt: 4}
      error = {:health_check_failed, :timeout}
      wrapped = PoolErrorHandler.wrap_pool_error(error, context)
      assert wrapped.severity == :major  # Upgraded from minor
    end
    
    test "sets critical severity when affecting all workers" do
      context = %{affecting_all_workers: true}
      error = {:health_check_failed, :timeout}
      wrapped = PoolErrorHandler.wrap_pool_error(error, context)
      assert wrapped.severity == :critical  # Upgraded due to scope
    end
  end
  
  describe "recovery strategy determination" do
    test "assigns immediate retry to communication errors" do
      error = {:encode_error, "invalid format"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.recovery_strategy == :immediate_retry
    end
    
    test "assigns backoff retry to connection errors" do
      error = {:port_exited, 1}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.recovery_strategy == :backoff_retry
    end
    
    test "assigns circuit break to resource errors" do
      error = {:checkout_failed, "pool exhausted"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.recovery_strategy == :circuit_break
    end
    
    test "assigns failover to python errors" do
      error = {:python_exception, "runtime error"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.recovery_strategy == :failover
    end
    
    test "assigns abandon after multiple attempts" do
      context = %{attempt: 3}
      error = {:checkout_failed, "pool exhausted"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, context)
      assert wrapped.recovery_strategy == :abandon
    end
    
    test "assigns abandon to system errors" do
      error = {:system_error, "kernel panic"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert wrapped.recovery_strategy == :abandon
    end
  end
  
  describe "retry logic" do
    test "should_retry? respects recovery strategy" do
      # Immediate retry allows up to 3 attempts
      error = {:encode_error, "invalid format"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      
      assert PoolErrorHandler.should_retry?(wrapped, 1) == true
      assert PoolErrorHandler.should_retry?(wrapped, 3) == true
      assert PoolErrorHandler.should_retry?(wrapped, 4) == false
    end
    
    test "should_retry? handles backoff retry" do
      # Backoff retry allows up to 5 attempts
      error = {:port_exited, 1}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      
      assert PoolErrorHandler.should_retry?(wrapped, 1) == true
      assert PoolErrorHandler.should_retry?(wrapped, 5) == true
      assert PoolErrorHandler.should_retry?(wrapped, 6) == false
    end
    
    test "should_retry? rejects circuit break and abandon strategies" do
      # Circuit break should not retry
      error = {:checkout_failed, "pool exhausted"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert PoolErrorHandler.should_retry?(wrapped, 1) == false
      
      # Abandon should not retry
      error = {:system_error, "fatal error"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      assert PoolErrorHandler.should_retry?(wrapped, 1) == false
    end
    
    test "should_retry? allows only one failover attempt" do
      error = {:python_exception, "runtime error"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      
      assert PoolErrorHandler.should_retry?(wrapped, 1) == true
      assert PoolErrorHandler.should_retry?(wrapped, 2) == false
    end
  end
  
  describe "retry delay calculation" do
    test "get_retry_delay returns correct delays for immediate retry" do
      error = {:encode_error, "invalid format"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      
      assert PoolErrorHandler.get_retry_delay(wrapped, 1) == 0
      assert PoolErrorHandler.get_retry_delay(wrapped, 2) == 100
      assert PoolErrorHandler.get_retry_delay(wrapped, 3) == 200
      assert PoolErrorHandler.get_retry_delay(wrapped, 4) == 200  # Last delay
    end
    
    test "get_retry_delay returns correct delays for backoff retry" do
      error = {:port_exited, 1}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      
      assert PoolErrorHandler.get_retry_delay(wrapped, 1) == 1_000
      assert PoolErrorHandler.get_retry_delay(wrapped, 2) == 2_000
      assert PoolErrorHandler.get_retry_delay(wrapped, 3) == 4_000
      assert PoolErrorHandler.get_retry_delay(wrapped, 6) == 16_000  # Last delay
    end
    
    test "get_retry_delay handles unknown strategies" do
      # Create a wrapped error and manually override strategy
      error = {:unknown_error, "test"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      wrapped_with_unknown = Map.put(wrapped, :recovery_strategy, :unknown_strategy)
      
      assert PoolErrorHandler.get_retry_delay(wrapped_with_unknown, 1) == 1_000
    end
  end
  
  describe "error context preservation" do
    test "preserves worker and session context" do
      context = %{
        worker_id: "worker_123",
        session_id: "session_456",
        operation: :execute_command,
        attempt: 2
      }
      
      error = {:timeout, "operation timeout"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, context)
      
      assert wrapped.context[:worker_id] == "worker_123"
      assert wrapped.context[:session_id] == "session_456"
      assert wrapped.context[:operation] == :execute_command
      assert wrapped.context[:attempt] == 2
    end
    
    test "adds timestamp and category to context" do
      before_time = System.os_time(:millisecond)
      
      error = {:timeout, "operation timeout"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      
      after_time = System.os_time(:millisecond)
      
      assert wrapped.context[:timestamp] >= before_time
      assert wrapped.context[:timestamp] <= after_time
      assert wrapped.context[:error_category] == :timeout_error
      assert wrapped.context[:recovery_strategy] == :backoff_retry
    end
  end
  
  describe "logging format" do
    test "format_for_logging includes all relevant information" do
      context = %{
        worker_id: "worker_123",
        session_id: "session_456",
        operation: :execute_command,
        attempt: 2
      }
      
      error = {:timeout, "operation timeout"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, context)
      
      formatted = PoolErrorHandler.format_for_logging(wrapped)
      
      assert formatted =~ "Pool Error:"
      assert formatted =~ "Category: timeout_error"
      assert formatted =~ "Severity: major"
      assert formatted =~ "Recovery: backoff_retry"
      assert formatted =~ "Worker: worker_123"
      assert formatted =~ "Session: session_456"
      assert formatted =~ "Attempt: 2"
    end
    
    test "format_for_logging handles missing context gracefully" do
      error = {:timeout, "operation timeout"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      
      formatted = PoolErrorHandler.format_for_logging(wrapped)
      
      assert formatted =~ "Worker: N/A"
      assert formatted =~ "Session: N/A"
      assert formatted =~ "Attempt: 1"
    end
  end
  
  describe "error wrapping structure" do
    test "wrapped error has correct structure" do
      context = %{worker_id: "worker_123"}
      error = {:timeout, "operation timeout"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, context)
      
      # Should be a PoolErrorHandler struct
      assert wrapped.__struct__ == PoolErrorHandler
      assert wrapped.pool_error == true
      
      # Should have all required fields
      assert is_atom(wrapped.error_category)
      assert is_atom(wrapped.severity)
      assert is_atom(wrapped.recovery_strategy)
      assert is_map(wrapped.context)
      assert is_binary(wrapped.message)
    end
    
    test "integrates with base ErrorHandler structure" do
      error = {:timeout, "operation timeout"}
      wrapped = PoolErrorHandler.wrap_pool_error(error, %{})
      
      # Should have ErrorHandler fields
      assert is_atom(wrapped.type)
      assert is_binary(wrapped.message)
      assert is_map(wrapped.context)
      assert is_boolean(wrapped.recoverable)
    end
  end
end