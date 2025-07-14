defmodule DSPex.Adapters.ErrorHandlerTest do
  use ExUnit.Case, async: true

  alias DSPex.Adapters.ErrorHandler

  @moduletag :layer_1

  setup do
    # Reset test environment
    System.put_env("TEST_MODE", "mock_adapter")
    :ok
  end

  describe "wrap_error/2" do
    test "wraps timeout errors with proper context" do
      error = ErrorHandler.wrap_error({:error, :timeout}, %{operation: :test})

      assert error.type == :timeout
      assert error.message == "Operation timed out"
      assert error.recoverable == true
      assert is_integer(error.retry_after)
      assert error.context.operation == :test
      assert error.test_layer == :layer_1
    end

    test "wraps connection failed errors" do
      error = ErrorHandler.wrap_error({:error, :connection_failed}, %{adapter: :test})

      assert error.type == :connection_failed
      assert error.message == "Failed to connect to adapter backend"
      assert error.context.adapter == :test
    end

    test "wraps validation failed errors" do
      error = ErrorHandler.wrap_error({:error, {:validation_failed, "invalid input"}}, %{})

      assert error.type == :validation_failed
      assert error.message == "Input validation failed: invalid input"
      assert error.recoverable == false
      assert error.retry_after == nil
    end

    test "wraps program not found errors" do
      error = ErrorHandler.wrap_error({:error, {:program_not_found, "test_prog"}}, %{})

      assert error.type == :program_not_found
      assert error.message == "Program not found: test_prog"
      assert error.recoverable == false
      assert error.context.program_id == "test_prog"
    end

    test "wraps bridge errors" do
      bridge_details = %{type: :protocol_error, message: "Bad format"}
      error = ErrorHandler.wrap_error({:error, {:bridge_error, bridge_details}}, %{})

      assert error.type == :bridge_error
      assert error.message =~ "Python bridge error"
      assert error.context.bridge_details == bridge_details
    end

    test "wraps string error reasons" do
      error = ErrorHandler.wrap_error({:error, "Custom error message"}, %{})

      assert error.type == :unknown
      assert error.message == "Custom error message"
      assert error.recoverable == false
    end

    test "wraps unexpected errors" do
      error = ErrorHandler.wrap_error(:unexpected_atom, %{})

      assert error.type == :unexpected
      assert error.message =~ "Unexpected error"
      assert error.recoverable == false
    end

    test "includes test layer information" do
      System.put_env("TEST_MODE", "full_integration")
      error = ErrorHandler.wrap_error({:error, :timeout}, %{})

      assert error.test_layer == :layer_3
    end
  end

  describe "helper functions" do
    test "should_retry?/1 returns recoverable status" do
      recoverable_error = ErrorHandler.wrap_error({:error, :timeout}, %{})
      non_recoverable_error = ErrorHandler.wrap_error({:error, {:validation_failed, "bad"}}, %{})

      assert ErrorHandler.should_retry?(recoverable_error) == true
      assert ErrorHandler.should_retry?(non_recoverable_error) == false
    end

    test "get_retry_delay/1 returns delay from error" do
      error = ErrorHandler.wrap_error({:error, :timeout}, %{})
      delay = ErrorHandler.get_retry_delay(error)

      assert is_integer(delay)
      assert delay > 0
    end

    test "get_error_context/1 returns context map" do
      context = %{operation: :test, data: "value"}
      error = ErrorHandler.wrap_error({:error, :timeout}, context)

      assert ErrorHandler.get_error_context(error) == context
    end

    test "is_test_error?/1 identifies test errors" do
      test_error = ErrorHandler.wrap_error({:error, :timeout}, %{})

      assert ErrorHandler.is_test_error?(test_error) == true
    end

    test "format_error/1 formats error messages" do
      error = ErrorHandler.wrap_error({:error, :timeout}, %{})
      formatted = ErrorHandler.format_error(error)

      assert is_binary(formatted)
      assert formatted =~ "timeout"
      assert formatted =~ "Operation timed out"
      assert formatted =~ "[layer_1]"
    end

    test "format_error/1 without test layer" do
      # Create error without test layer context
      error = %ErrorHandler{
        type: :timeout,
        message: "Test timeout",
        context: %{},
        recoverable: true,
        retry_after: 1000,
        test_layer: nil
      }

      formatted = ErrorHandler.format_error(error)
      assert formatted == "timeout: Test timeout"
      refute formatted =~ "["
    end
  end

  describe "test layer specific behavior" do
    test "layer_1 has fast retry delays" do
      System.put_env("TEST_MODE", "mock_adapter")
      error = ErrorHandler.wrap_error({:error, :timeout}, %{})

      assert error.retry_after == 100
    end

    test "layer_2 has medium retry delays" do
      System.put_env("TEST_MODE", "bridge_mock")
      error = ErrorHandler.wrap_error({:error, :timeout}, %{})

      assert error.retry_after == 500
    end

    test "layer_3 has slow retry delays" do
      System.put_env("TEST_MODE", "full_integration")
      error = ErrorHandler.wrap_error({:error, :timeout}, %{})

      assert error.retry_after == 5000
    end

    test "layer_1 never retries connection failures (mock should not fail)" do
      System.put_env("TEST_MODE", "mock_adapter")
      error = ErrorHandler.wrap_error({:error, :connection_failed}, %{})

      assert error.recoverable == false
    end

    test "layer_2 and layer_3 retry connection failures" do
      System.put_env("TEST_MODE", "bridge_mock")
      error1 = ErrorHandler.wrap_error({:error, :connection_failed}, %{})

      System.put_env("TEST_MODE", "full_integration")
      error2 = ErrorHandler.wrap_error({:error, :connection_failed}, %{})

      assert error1.recoverable == true
      assert error2.recoverable == true
    end

    test "bridge error retry logic varies by test layer" do
      # Layer 1: No bridge, so no retries
      System.put_env("TEST_MODE", "mock_adapter")
      error1 = ErrorHandler.wrap_error({:error, {:bridge_error, %{type: :timeout}}}, %{})

      # Layer 2: Protocol errors don't retry, timeouts do
      System.put_env("TEST_MODE", "bridge_mock")
      error2a = ErrorHandler.wrap_error({:error, {:bridge_error, %{type: :protocol_error}}}, %{})
      error2b = ErrorHandler.wrap_error({:error, {:bridge_error, %{type: :timeout}}}, %{})

      # Layer 3: Most errors retry except validation
      System.put_env("TEST_MODE", "full_integration")

      error3a =
        ErrorHandler.wrap_error({:error, {:bridge_error, %{type: :validation_error}}}, %{})

      error3b = ErrorHandler.wrap_error({:error, {:bridge_error, %{type: :timeout}}}, %{})

      # No bridge in mock
      assert error1.recoverable == false
      # Protocol errors don't retry
      assert error2a.recoverable == false
      # Timeouts retry
      assert error2b.recoverable == true
      # Validation errors don't retry
      assert error3a.recoverable == false
      # Other errors retry
      assert error3b.recoverable == true
    end
  end

  describe "legacy handle_adapter_error/2" do
    test "handles adapter errors with context" do
      result =
        ErrorHandler.handle_adapter_error(DSPex.Adapters.Mock, {:program_not_found, "test"})

      assert {:error, enriched_error} = result
      assert Map.has_key?(enriched_error, :error)
      assert Map.has_key?(enriched_error, :adapter)
      assert Map.has_key?(enriched_error, :timestamp)
      assert Map.has_key?(enriched_error, :formatted_message)
      assert Map.has_key?(enriched_error, :classification)
      assert Map.has_key?(enriched_error, :recovery_strategy)
    end

    test "handles timeout errors" do
      result = ErrorHandler.handle_timeout_error(DSPex.Adapters.Mock, 5000)

      assert {:error, {:timeout, message}} = result
      assert message =~ "5000ms"
    end

    test "handles unexpected errors with full context" do
      result =
        ErrorHandler.handle_unexpected_error(
          DSPex.Adapters.Mock,
          :throw,
          "test error",
          []
        )

      assert {:error, {:unexpected_error, message}} = result
      assert message =~ "Unexpected throw"
    end

    test "with_error_handling/3 wraps operations" do
      # Success case
      result =
        ErrorHandler.with_error_handling(DSPex.Adapters.Mock, :test_op, fn ->
          {:ok, "success"}
        end)

      assert {:ok, "success"} = result

      # Error case
      result =
        ErrorHandler.with_error_handling(DSPex.Adapters.Mock, :test_op, fn ->
          {:error, "failure"}
        end)

      assert {:error, _enriched} = result

      # Exception case
      result =
        ErrorHandler.with_error_handling(DSPex.Adapters.Mock, :test_op, fn ->
          raise "test exception"
        end)

      assert {:error, _enriched} = result
    end
  end

  describe "error classification and recovery" do
    test "suggest_recovery/1 provides appropriate strategies" do
      assert ErrorHandler.suggest_recovery(:configuration_error) == :immediate_failure
      assert ErrorHandler.suggest_recovery(:connection_error) == :retry_with_backoff
      assert ErrorHandler.suggest_recovery(:timeout_error) == :retry
      assert ErrorHandler.suggest_recovery(:validation_error) == :immediate_failure
      assert ErrorHandler.suggest_recovery(:execution_error) == :log_and_continue
      assert ErrorHandler.suggest_recovery(:resource_error) == :failover
      assert ErrorHandler.suggest_recovery(:unknown_error) == :log_and_continue
    end

    test "format_error/1 handles different error types" do
      config_error = {:configuration_error, "Missing config"}
      conn_error = {:connection_error, "Cannot connect"}
      timeout_error = {:timeout, "Operation timeout"}
      validation_error = {:validation_error, "field", "invalid"}
      not_found_error = {:not_found, "resource"}
      permission_error = {:permission_denied, "resource"}

      assert ErrorHandler.format_error(config_error) =~ "Configuration error"
      assert ErrorHandler.format_error(conn_error) =~ "Connection error"
      assert ErrorHandler.format_error(timeout_error) =~ "Operation timed out"
      assert ErrorHandler.format_error(validation_error) =~ "Validation error"
      assert ErrorHandler.format_error(not_found_error) =~ "Resource not found"
      assert ErrorHandler.format_error(permission_error) =~ "Permission denied"

      # String errors
      assert ErrorHandler.format_error("simple error") == "simple error"

      # Unknown errors
      assert ErrorHandler.format_error(:unknown) =~ "An error occurred"
    end

    test "enrich_error/2 adds context and metadata" do
      context = %{
        adapter: DSPex.Adapters.Mock,
        operation: :test,
        metadata: %{request_id: "123"}
      }

      enriched = ErrorHandler.enrich_error({:timeout, "test"}, context)

      assert enriched.error == {:timeout, "test"}
      assert enriched.adapter == DSPex.Adapters.Mock
      assert enriched.operation == :test
      assert %DateTime{} = enriched.timestamp
      assert is_binary(enriched.formatted_message)

      assert enriched.classification in [
               :configuration_error,
               :connection_error,
               :timeout_error,
               :validation_error,
               :execution_error,
               :resource_error,
               :unknown_error
             ]

      assert enriched.recovery_strategy in [
               :retry,
               :retry_with_backoff,
               :failover,
               :log_and_continue,
               :immediate_failure
             ]

      assert enriched.metadata.request_id == "123"
    end

    test "track_error/2 logs error metrics" do
      context = %{adapter: DSPex.Adapters.Mock, operation: :test}

      # Should not crash
      assert :ok = ErrorHandler.track_error({:timeout, "test"}, context)
    end
  end
end
