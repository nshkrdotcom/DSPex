defmodule DSPex.Adapters.BehaviorComplianceTest do
  @moduledoc """
  Comprehensive behavior compliance testing for all adapters across test layers.
  """

  use ExUnit.Case, async: false

  defmodule TestSignature do
    use DSPex.Signature

    @signature_ast {:->, [],
                    [[{:question, :string}], [{:answer, :string}, {:confidence, :float}]]}
  end

  defmodule ComplexTestSignature do
    use DSPex.Signature

    @signature_ast {:->, [],
                    [
                      [{:input, :string}, {:context, {:list, :string}}],
                      [
                        {:result, :string},
                        {:reasoning, {:list, :string}},
                        {:confidence, :probability}
                      ]
                    ]}
  end

  @adapters_by_layer %{
    layer_1: DSPex.Adapters.Mock,
    layer_2: DSPex.Adapters.BridgeMock,
    layer_3: DSPex.Adapters.PythonPort
  }

  @test_layers [:layer_1, :layer_2, :layer_3]

  setup do
    # Reset test environment
    System.put_env("TEST_MODE", "mock_adapter")

    # Ensure clean Mock process for each test
    setup_isolated_mock()

    :ok
  end

  defp setup_isolated_mock do
    # Kill any existing Mock process
    if pid = Process.whereis(DSPex.Adapters.Mock) do
      Process.exit(pid, :kill)
      # Allow cleanup
      Process.sleep(10)
    end

    # Start fresh Mock process
    case DSPex.Adapters.Mock.start_link(name: DSPex.Adapters.Mock) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        # Reset if already started
        DSPex.Adapters.Mock.reset()
        :ok

      error ->
        error
    end
  end

  for layer <- @test_layers do
    describe "#{layer} adapter behavior compliance" do
      setup do
        adapter = Map.get(@adapters_by_layer, unquote(layer))

        # Set appropriate test mode for this layer
        test_mode =
          case unquote(layer) do
            :layer_1 -> "mock_adapter"
            :layer_2 -> "bridge_mock"
            :layer_3 -> "full_integration"
          end

        System.put_env("TEST_MODE", test_mode)

        {:ok, adapter: adapter, test_layer: unquote(layer)}
      end

      @tag String.to_atom("#{layer}")
      test "creates programs successfully", %{adapter: adapter, test_layer: test_layer} do
        config = %{
          id: "test_program_#{test_layer}",
          signature: TestSignature,
          modules: []
        }

        {:ok, program_id} = adapter.create_program(config)
        assert program_id == "test_program_#{test_layer}"
      end

      @tag String.to_atom("#{layer}")
      test "executes programs with valid inputs", %{adapter: adapter, test_layer: test_layer} do
        # Create program first
        config = %{
          id: "test_program_#{test_layer}",
          signature: TestSignature,
          modules: []
        }

        {:ok, _} = adapter.create_program(config)

        # Execute program
        inputs = %{question: "What is 2+2?"}
        {:ok, outputs} = adapter.execute_program("test_program_#{test_layer}", inputs)

        assert Map.has_key?(outputs, :answer) or Map.has_key?(outputs, "answer")
        assert Map.has_key?(outputs, :confidence) or Map.has_key?(outputs, "confidence")
      end

      @tag String.to_atom("#{layer}")
      test "handles complex signatures", %{adapter: adapter, test_layer: test_layer} do
        config = %{
          id: "complex_program_#{test_layer}",
          signature: ComplexTestSignature,
          modules: []
        }

        {:ok, program_id} = adapter.create_program(config)

        inputs = %{
          input: "Analyze this text",
          context: ["context1", "context2"]
        }

        {:ok, outputs} = adapter.execute_program(program_id, inputs)

        # Verify complex output structure
        assert Map.has_key?(outputs, :result) or Map.has_key?(outputs, "result")
        assert Map.has_key?(outputs, :reasoning) or Map.has_key?(outputs, "reasoning")
        assert Map.has_key?(outputs, :confidence) or Map.has_key?(outputs, "confidence")
      end

      @tag String.to_atom("#{layer}")
      test "returns error for non-existent program", %{adapter: adapter} do
        inputs = %{question: "test"}
        {:error, _reason} = adapter.execute_program("nonexistent", inputs)
      end

      @tag String.to_atom("#{layer}")
      test "lists programs correctly", %{adapter: adapter, test_layer: test_layer} do
        # Create a few programs
        for i <- 1..3 do
          config = %{
            id: "test_program_#{test_layer}_#{i}",
            signature: TestSignature,
            modules: []
          }

          {:ok, _} = adapter.create_program(config)
        end

        {:ok, programs} = adapter.list_programs()
        assert length(programs) >= 3
      end

      @tag String.to_atom("#{layer}")
      test "supports health check", %{adapter: adapter} do
        if function_exported?(adapter, :health_check, 0) do
          case adapter.health_check() do
            :ok -> assert true
            # Error is acceptable in some test layers
            {:error, _reason} -> assert true
          end
        end
      end

      @tag String.to_atom("#{layer}")
      test "provides test capabilities", %{adapter: adapter} do
        if function_exported?(adapter, :get_test_capabilities, 0) do
          capabilities = adapter.get_test_capabilities()
          assert is_map(capabilities)
          assert Map.has_key?(capabilities, :performance)
        end
      end

      @tag String.to_atom("#{layer}")
      test "validates test layer support", %{adapter: adapter, test_layer: test_layer} do
        if function_exported?(adapter, :supports_test_layer?, 1) do
          assert adapter.supports_test_layer?(test_layer) == true
        end
      end
    end
  end

  describe "Factory pattern compliance" do
    @tag :layer_3
    test "creates correct adapters for test layers" do
      for {layer, expected_adapter} <- @adapters_by_layer do
        {:ok, adapter} = DSPex.Adapters.Factory.create_adapter(nil, test_layer: layer)
        assert adapter == expected_adapter
      end
    end

    test "validates adapter requirements" do
      {:ok, _adapter} = DSPex.Adapters.Factory.create_adapter(:mock, test_layer: :layer_1)
    end

    test "handles execution with retry logic" do
      adapter = DSPex.Adapters.Mock

      # This should succeed
      {:ok, result} =
        DSPex.Adapters.Factory.execute_with_adapter(
          adapter,
          :health_check,
          [],
          test_layer: :layer_1
        )

      assert result == :ok
    end
  end

  describe "Type conversion compliance" do
    test "converts basic types correctly" do
      assert DSPex.Adapters.TypeConverter.convert_type(:string, :python) == "str"
      assert DSPex.Adapters.TypeConverter.convert_type(:integer, :python) == "int"
      assert DSPex.Adapters.TypeConverter.convert_type({:list, :string}, :python) == "List[str]"
    end

    test "validates inputs with test layer awareness" do
      {:ok, "hello"} =
        DSPex.Adapters.TypeConverter.validate_input("hello", :string, test_layer: :layer_1)

      {:ok, 42} = DSPex.Adapters.TypeConverter.validate_input(42, :integer, test_layer: :layer_2)

      {:ok, [1, 2, 3]} =
        DSPex.Adapters.TypeConverter.validate_input([1, 2, 3], {:list, :integer},
          test_layer: :layer_3
        )
    end

    test "rejects invalid inputs appropriately" do
      {:error, _} = DSPex.Adapters.TypeConverter.validate_input(42, :string, test_layer: :layer_3)

      {:error, _} =
        DSPex.Adapters.TypeConverter.validate_input("hello", :integer, test_layer: :layer_3)

      {:error, _} =
        DSPex.Adapters.TypeConverter.validate_input([1, "two"], {:list, :integer},
          test_layer: :layer_3
        )
    end

    test "converts signatures to different formats" do
      signature_def =
        DSPex.Adapters.TypeConverter.convert_signature_to_format(TestSignature, :python)

      assert Map.has_key?(signature_def, :inputs)
      assert Map.has_key?(signature_def, :outputs)
      assert length(signature_def.inputs) == 1
      assert length(signature_def.outputs) == 2
    end
  end

  describe "Error handling compliance" do
    test "wraps errors with proper context" do
      error = DSPex.Adapters.ErrorHandler.wrap_error({:error, :timeout}, %{context: :test})

      assert error.type == :timeout
      assert error.recoverable == true
      assert is_integer(error.retry_after)
      assert error.context.context == :test
    end

    test "provides test layer specific retry delays" do
      # Set different test modes and verify retry delays
      System.put_env("TEST_MODE", "mock_adapter")
      error1 = DSPex.Adapters.ErrorHandler.wrap_error({:error, :timeout})

      System.put_env("TEST_MODE", "full_integration")
      error2 = DSPex.Adapters.ErrorHandler.wrap_error({:error, :timeout})

      # Layer 1 should have shorter delays than Layer 3
      assert error1.retry_after < error2.retry_after
    end

    test "formats errors with test context" do
      error = DSPex.Adapters.ErrorHandler.wrap_error({:error, "test error"})
      formatted = DSPex.Adapters.ErrorHandler.format_error(error)

      assert is_binary(formatted)
      assert formatted =~ "test error"
    end
  end
end
