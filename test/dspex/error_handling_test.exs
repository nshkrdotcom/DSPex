defmodule DSPex.ErrorHandlingTest do
  @moduledoc """
  Comprehensive error condition testing across all modules.

  This test suite ensures that error conditions not only return appropriate
  error values but also log warnings/errors as expected.
  """
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import ExUnit.CaptureIO

  alias DSPex.{Config, Testing.TestMode}
  alias DSPex.PythonBridge.Protocol

  describe "configuration error handling" do
    @invalid_configs [
      {"DSPEX_BRIDGE_TIMEOUT", "not_a_number", :default_timeout, :python_bridge},
      {"DSPEX_HEALTH_CHECK_INTERVAL", "bad", :health_check_interval, :python_bridge_monitor},
      {"DSPEX_FAILURE_THRESHOLD", "xyz", :failure_threshold, :python_bridge_monitor}
    ]

    for {env_var, invalid_value, config_key, config_section} <- @invalid_configs do
      test "handles invalid #{env_var} = '#{invalid_value}'" do
        log =
          capture_log(fn ->
            System.put_env(unquote(env_var), unquote(invalid_value))

            config = Config.get(unquote(config_section))
            # Should return the default value from the Config module
            assert is_integer(config[unquote(config_key)])
            assert config[unquote(config_key)] > 0
          end)

        # Some use "Invalid integer value" and others use "Invalid non-negative integer value"
        assert log =~ "Invalid" and
                 log =~ "integer value for #{unquote(config_key)}: #{unquote(invalid_value)}"

        assert log =~ "[warning]"
      end
    end
  end

  describe "test mode error handling" do
    @invalid_test_modes [
      "invalid_mode",
      "layer_4",
      "unit_test",
      "123",
      ""
    ]

    for invalid_mode <- @invalid_test_modes do
      test "handles invalid TEST_MODE = '#{invalid_mode}'" do
        old_env = System.get_env("TEST_MODE")

        log =
          capture_log(fn ->
            System.put_env("TEST_MODE", unquote(invalid_mode))

            # Should fall back to default
            assert TestMode.current_test_mode() == :mock_adapter

            # Should still be functional
            assert is_atom(TestMode.get_adapter_module())
          end)

        assert log =~ "Invalid TEST_MODE: #{unquote(invalid_mode)}"
        assert log =~ "using default: mock_adapter"

        # Cleanup
        if old_env, do: System.put_env("TEST_MODE", old_env), else: System.delete_env("TEST_MODE")
      end
    end
  end

  describe "protocol error handling" do
    test "handles various malformed JSON inputs" do
      malformed_inputs = [
        {"", "empty string"},
        {"[", "incomplete array"},
        {"{", "incomplete object"},
        {"undefined", "undefined"},
        {<<0, 1, 2, 3>>, "binary garbage"}
      ]

      for {input, description} <- malformed_inputs do
        log =
          capture_log(fn ->
            result = Protocol.decode_response(input)

            assert match?({:error, _}, result) or match?({:error, _, _}, result),
                   "Expected error for #{description}, got: #{inspect(result)}"
          end)

        # All should log some kind of warning
        assert log =~ "[warning]", "Expected warning for #{description}"
      end
    end

    test "handles responses with wrong types for required fields" do
      wrong_type_responses = [
        %{"id" => "not_an_int", "success" => true, "result" => %{}},
        %{"id" => 1, "success" => "not_a_bool", "result" => %{}},
        %{"id" => 1, "success" => true, "result" => "not_a_map"}
      ]

      for response <- wrong_type_responses do
        json = Jason.encode!(response)

        _log =
          capture_log(fn ->
            result = Protocol.decode_response(json)
            # Should either return error or handle gracefully
            assert is_tuple(result)
          end)

        # May or may not log depending on implementation
        # but should not crash
      end
    end
  end

  describe "error propagation" do
    test "errors propagate through adapter layers" do
      # This test would require setting up failing conditions
      # and verifying errors bubble up correctly
      # Example structure:

      # 1. Make Python bridge unavailable
      # 2. Try to use PythonPort adapter
      # 3. Verify appropriate error is returned
      # 4. Verify error is logged at each layer
    end
  end

  describe "concurrent error handling" do
    test "handles multiple simultaneous errors gracefully" do
      # Save original value
      original = System.get_env("DSPEX_BRIDGE_TIMEOUT")

      # Spawn multiple processes that will all encounter errors
      # Note: Environment variables are process-global, so this test
      # actually tests concurrent Config.get calls with the same invalid value
      System.put_env("DSPEX_BRIDGE_TIMEOUT", "concurrent_invalid")

      tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            capture_log(fn ->
              Config.get(:python_bridge)
            end)
          end)
        end

      logs = Task.await_many(tasks)

      # All should have logged warnings
      assert length(logs) == 10

      # Each log should contain the warning about concurrent_invalid
      for log <- logs do
        assert log =~ "Invalid"
        assert log =~ "integer value"
        assert log =~ "concurrent_invalid"
      end

      # Cleanup
      if original do
        System.put_env("DSPEX_BRIDGE_TIMEOUT", original)
      else
        System.delete_env("DSPEX_BRIDGE_TIMEOUT")
      end
    end
  end

  describe "error recovery" do
    test "system recovers after invalid configuration is fixed" do
      # First set invalid value
      log1 =
        capture_log(fn ->
          System.put_env("DSPEX_BRIDGE_TIMEOUT", "invalid")
          config = Config.get(:python_bridge)
          # Returns default value
          assert config[:default_timeout] == 30_000
        end)

      assert log1 =~ "Invalid integer value"

      # Now fix it
      log2 =
        capture_log(fn ->
          System.put_env("DSPEX_BRIDGE_TIMEOUT", "5000")
          # Clear other potentially invalid env vars that might be set from other tests
          System.delete_env("DSPEX_HEALTH_CHECK_INTERVAL")
          System.delete_env("DSPEX_FAILURE_THRESHOLD")

          # Force reload
          Config.reload()
          config = Config.get(:python_bridge)
          # Uses new valid value
          assert config[:default_timeout] == 5000
        end)

      # Should not log warning about BRIDGE_TIMEOUT
      refute log2 =~ "Invalid integer value for default_timeout"
    end
  end
end
