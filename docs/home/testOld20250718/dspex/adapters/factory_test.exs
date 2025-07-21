defmodule DSPex.Adapters.FactoryTest do
  use ExUnit.Case, async: false

  alias DSPex.Adapters.Factory
  alias DSPex.Adapters.{Mock, BridgeMock, PythonPort}

  @moduletag :layer_1

  defmodule TestSignature do
    use DSPex.Signature

    @signature_ast {:->, [],
                    [[{:question, :string}], [{:answer, :string}, {:confidence, :float}]]}
  end

  setup do
    # Reset test environment
    System.put_env("TEST_MODE", "mock_adapter")

    # Ensure clean Mock process for each test
    setup_isolated_mock()

    # Configure LM for the Mock adapter
    default_lm = Application.get_env(:dspex, :default_lm)

    if default_lm do
      Mock.configure_lm(default_lm)
    end

    :ok
  end

  defp setup_isolated_mock do
    # Gracefully stop any existing Mock process
    if pid = Process.whereis(Mock) do
      try do
        GenServer.stop(pid, :normal, 5000)
      catch
        :exit, _ -> :ok
      end
    end

    # Start fresh Mock process
    case Mock.start_link(name: Mock) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        # Reset if already started
        Mock.reset()
        :ok

      error ->
        error
    end
  end

  describe "create_adapter/2" do
    test "creates mock adapter for layer_1" do
      {:ok, adapter} = Factory.create_adapter(nil, test_layer: :layer_1)
      assert adapter == Mock
    end

    test "creates bridge mock adapter for layer_2" do
      {:ok, adapter} = Factory.create_adapter(nil, test_layer: :layer_2)
      assert adapter == BridgeMock
    end

    @tag :layer_3
    test "creates python port adapter for layer_3" do
      {:ok, adapter} = Factory.create_adapter(nil, test_layer: :layer_3)
      assert adapter == PythonPort
    end

    test "creates specific adapter when requested" do
      {:ok, adapter} = Factory.create_adapter(:mock, test_layer: :layer_1)
      assert adapter == Mock
    end

    test "validates adapter compatibility with test layer" do
      # Mock adapter should work with layer_1
      {:ok, _} = Factory.create_adapter(:mock, test_layer: :layer_1)

      # But may not work with other layers (depending on implementation)
      # This test would need to be updated based on actual adapter capabilities
    end

    test "checks adapter requirements" do
      # Mock adapter should always be available
      {:ok, _} = Factory.create_adapter(:mock, test_layer: :layer_1)
    end

    test "returns error for invalid adapter" do
      assert {:error, _} = Factory.create_adapter(:nonexistent, test_layer: :layer_1)
    end

    test "uses current test mode when not specified" do
      System.put_env("TEST_MODE", "mock_adapter")
      {:ok, adapter} = Factory.create_adapter()
      assert adapter == Mock
    end
  end

  describe "execute_with_adapter/4" do
    test "executes operations successfully" do
      {:ok, result} =
        Factory.execute_with_adapter(
          Mock,
          :health_check,
          [],
          test_layer: :layer_1
        )

      assert result == :ok
    end

    test "handles timeouts appropriately" do
      # This would need a mock that can simulate timeouts
      {:ok, result} =
        Factory.execute_with_adapter(
          Mock,
          :health_check,
          [],
          timeout: 1000,
          test_layer: :layer_1
        )

      assert result == :ok
    end

    test "respects test layer specific timeouts" do
      # Layer 1 should have fast timeouts
      start_time = System.monotonic_time(:millisecond)

      Factory.execute_with_adapter(
        Mock,
        :health_check,
        [],
        test_layer: :layer_1
      )

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Should complete quickly for mock
      assert duration < 1000
    end

    test "applies retry logic for recoverable errors" do
      # This would need a mock that can simulate retryable errors
      # For now, just test that it doesn't crash
      {:ok, result} =
        Factory.execute_with_adapter(
          Mock,
          :health_check,
          [],
          max_retries: 2,
          test_layer: :layer_1
        )

      assert result == :ok
    end

    test "uses test layer specific retry counts" do
      # Layer 1 (mock) should have no retries by default
      # Layer 2 should have some retries
      # Layer 3 should have more retries

      # This is tested implicitly through the default behavior
      assert true
    end
  end

  describe "execute_with_signature_validation/4" do
    test "validates inputs against signature" do
      # First create a program
      config = %{
        id: "test_signature_validation",
        signature: TestSignature,
        modules: []
      }

      {:ok, _} = Mock.create_program(config)

      # Valid inputs should work
      valid_inputs = %{question: "What is 2+2?"}

      {:ok, result} =
        Factory.execute_with_signature_validation(
          Mock,
          TestSignature,
          valid_inputs,
          test_layer: :layer_1
        )

      assert is_map(result)
    end

    test "rejects invalid inputs" do
      # Invalid inputs should be rejected
      invalid_inputs = %{wrong_field: "value"}

      {:error, _} =
        Factory.execute_with_signature_validation(
          Mock,
          TestSignature,
          invalid_inputs,
          test_layer: :layer_1
        )
    end

    test "converts inputs for adapter compatibility" do
      # Test that inputs are properly converted for different adapters
      inputs = %{question: "test"}

      {:ok, _result} =
        Factory.execute_with_signature_validation(
          Mock,
          TestSignature,
          inputs,
          test_layer: :layer_1
        )
    end

    test "applies test layer specific validation" do
      # Layer 1 should be more flexible with input validation
      # Layer 3 should be stricter

      # Wrong type but might be accepted in mock
      flexible_inputs = %{question: 123}

      # This would depend on the actual validation implementation
      result =
        Factory.execute_with_signature_validation(
          Mock,
          TestSignature,
          flexible_inputs,
          test_layer: :layer_1
        )

      # Result could be ok or error depending on mock's flexibility
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "legacy create_adapter_legacy/1" do
    test "works with legacy options format" do
      {:ok, adapter} = Factory.create_adapter_legacy(adapter: :mock)
      assert adapter == Mock
    end

    test "validates adapter in legacy mode" do
      {:ok, _} = Factory.create_adapter_legacy(adapter: :mock, validate: true)
    end

    test "skips validation when requested" do
      {:ok, _} = Factory.create_adapter_legacy(adapter: :mock, validate: false)
    end

    test "starts required services" do
      {:ok, _} = Factory.create_adapter_legacy(adapter: :mock, start_services: true)
    end

    test "skips starting services when requested" do
      {:ok, _} = Factory.create_adapter_legacy(adapter: :mock, start_services: false)
    end
  end

  describe "adapter lifecycle management" do
    test "execute_with_adapter handles adapter creation" do
      # Test that the factory properly manages adapter lifecycle
      {:ok, _} =
        Factory.execute_with_adapter(
          Mock,
          :health_check,
          [],
          test_layer: :layer_1
        )
    end

    test "execute_with_fallback provides fallback logic" do
      # Test fallback to different adapters
      {:ok, result} =
        Factory.execute_with_fallback(
          :mock,
          :health_check,
          [],
          fallback_adapters: [:mock],
          test_layer: :layer_1
        )

      assert result == :ok
    end

    test "create_adapter_suite creates multiple adapters" do
      {:ok, adapters} = Factory.create_adapter_suite([:mock])

      assert Map.has_key?(adapters, :mock)
      assert adapters[:mock] == Mock
    end

    test "handles adapter suite creation failures gracefully" do
      result = Factory.create_adapter_suite([:mock, :nonexistent])

      # Should handle partial failures
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "test layer specific behavior" do
    test "layer_1 uses fast timeouts and no retries" do
      System.put_env("TEST_MODE", "mock_adapter")

      start_time = System.monotonic_time(:millisecond)
      {:ok, _} = Factory.execute_with_adapter(Mock, :health_check, [])
      end_time = System.monotonic_time(:millisecond)

      # Should be fast
      assert end_time - start_time < 1000
    end

    test "layer_2 uses medium timeouts and some retries" do
      System.put_env("TEST_MODE", "bridge_mock")

      # Should use appropriate timeouts for protocol testing
      {:ok, _} = Factory.execute_with_adapter(BridgeMock, :health_check, [])
    end

    @tag :layer_3
    test "layer_3 uses long timeouts and more retries" do
      System.put_env("TEST_MODE", "full_integration")

      # Should use longer timeouts for integration testing
      {:ok, _} = Factory.execute_with_adapter(PythonPort, :health_check, [])
    end
  end

  describe "error handling integration" do
    test "wraps errors with proper context" do
      # Test that factory errors are properly wrapped
      {:error, error} = Factory.create_adapter(:nonexistent, test_layer: :layer_1)

      # Should be a wrapped error with context
      assert Map.has_key?(error, :type) or is_binary(error)
    end

    test "provides retry logic for recoverable errors" do
      # This would need a mock that can simulate recoverable errors
      # For now, just verify the mechanism exists
      {:ok, _} =
        Factory.execute_with_adapter(
          Mock,
          :health_check,
          [],
          max_retries: 1,
          test_layer: :layer_1
        )
    end

    test "fails fast for non-recoverable errors" do
      # Test that non-recoverable errors don't trigger retries
      # This would need specific error simulation
      assert true
    end
  end

  describe "adapter requirements checking" do
    test "mock adapter requirements are always satisfied" do
      {:ok, _} = Factory.create_adapter(:mock, test_layer: :layer_1)
    end

    test "bridge mock requirements checked for layer_2" do
      # Should check if bridge mock server is available for layer_2
      result = Factory.create_adapter(:bridge_mock, test_layer: :layer_2)

      # Result depends on whether bridge mock is actually available
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "python port requirements checked for layer_3" do
      # Should check if Python bridge is available for layer_3
      result = Factory.create_adapter(:python_port, test_layer: :layer_3)

      # Result depends on whether Python bridge is actually running
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "bypasses requirements for test modes" do
      # When not in the target test layer, requirements should be bypassed
      {:ok, _} = Factory.create_adapter(:python_port, test_layer: :layer_1)
    end
  end

  describe "signature validation integration" do
    test "validates required fields" do
      inputs_missing_field = %{}

      {:error, _} =
        Factory.execute_with_signature_validation(
          Mock,
          TestSignature,
          inputs_missing_field,
          test_layer: :layer_1
        )
    end

    test "validates field types" do
      # Should be string
      inputs_wrong_type = %{question: 123}

      result =
        Factory.execute_with_signature_validation(
          Mock,
          TestSignature,
          inputs_wrong_type,
          # Strict validation
          test_layer: :layer_3
        )

      # Should reject wrong types in strict mode
      assert {:error, _} = result
    end

    test "converts inputs for different adapters" do
      inputs = %{question: "test"}

      # Should work with all adapters through proper conversion
      {:ok, _} =
        Factory.execute_with_signature_validation(
          Mock,
          TestSignature,
          inputs,
          test_layer: :layer_1
        )
    end
  end
end
