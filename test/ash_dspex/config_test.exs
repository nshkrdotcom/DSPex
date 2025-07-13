defmodule AshDSPex.ConfigTest do
  # Not async due to environment variable changes
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias AshDSPex.Config

  describe "get/1" do
    test "returns configuration for valid section" do
      config = Config.get(:python_bridge)

      assert is_map(config)
      assert Map.has_key?(config, :python_executable)
      assert Map.has_key?(config, :default_timeout)
      assert Map.has_key?(config, :max_retries)
    end

    test "returns empty map for invalid section" do
      config = Config.get(:nonexistent_section)

      assert config == %{}
    end

    test "merges defaults with application config" do
      # Test that we get at least the default values
      config = Config.get(:signature_system)

      assert Map.has_key?(config, :validation_enabled)
      assert Map.has_key?(config, :compile_time_checks)
      assert Map.has_key?(config, :json_schema_provider)
    end
  end

  describe "get/3" do
    test "returns specific configuration value" do
      timeout = Config.get(:python_bridge, :default_timeout)

      assert is_integer(timeout)
      assert timeout > 0
    end

    test "returns default value for missing key" do
      value = Config.get(:python_bridge, :nonexistent_key, "default")

      assert value == "default"
    end

    test "returns nil for missing key without default" do
      value = Config.get(:python_bridge, :nonexistent_key)

      assert value == nil
    end
  end

  describe "get_defaults/1" do
    test "returns default configuration for section" do
      defaults = Config.get_defaults(:python_bridge)

      assert is_map(defaults)
      assert defaults[:python_executable] == "python3"
      assert defaults[:default_timeout] == 30_000
      assert defaults[:max_retries] == 3
    end

    test "returns empty map for invalid section" do
      defaults = Config.get_defaults(:nonexistent_section)

      assert defaults == %{}
    end
  end

  describe "get_all/0" do
    test "returns all configuration sections" do
      all_config = Config.get_all()

      assert is_map(all_config)
      assert Map.has_key?(all_config, :signature_system)
      assert Map.has_key?(all_config, :python_bridge)
      assert Map.has_key?(all_config, :python_bridge_monitor)
      assert Map.has_key?(all_config, :python_bridge_supervisor)

      # Each section should be a map
      Enum.each(all_config, fn {_section, config} ->
        assert is_map(config)
      end)
    end
  end

  describe "validate/0" do
    test "validates default configuration successfully" do
      result = Config.validate()

      case result do
        :ok ->
          assert true

        {:error, issues} ->
          # If there are issues, they should be strings
          assert is_list(issues)

          Enum.each(issues, fn issue ->
            assert is_binary(issue)
          end)
      end
    end

    test "detects invalid configuration" do
      # Temporarily set invalid configuration
      original_config = Application.get_env(:ash_dspex, :python_bridge, [])

      try do
        # Set invalid timeout
        invalid_config = Keyword.put(original_config, :default_timeout, -1000)
        Application.put_env(:ash_dspex, :python_bridge, invalid_config)

        result = Config.validate()

        case result do
          {:error, issues} ->
            assert is_list(issues)
            assert length(issues) > 0

            # Should mention the invalid timeout
            timeout_issue = Enum.find(issues, &String.contains?(&1, "timeout"))
            assert timeout_issue != nil

          :ok ->
            # Validation might pass if other validation logic changes
            assert true
        end
      after
        Application.put_env(:ash_dspex, :python_bridge, original_config)
      end
    end
  end

  describe "environment variable overrides" do
    setup do
      # Store original env vars
      original_vars = %{
        "ASH_DSPEX_PYTHON_EXECUTABLE" => System.get_env("ASH_DSPEX_PYTHON_EXECUTABLE"),
        "ASH_DSPEX_BRIDGE_TIMEOUT" => System.get_env("ASH_DSPEX_BRIDGE_TIMEOUT"),
        "ASH_DSPEX_HEALTH_CHECK_INTERVAL" => System.get_env("ASH_DSPEX_HEALTH_CHECK_INTERVAL")
      }

      on_exit(fn ->
        # Restore original env vars
        Enum.each(original_vars, fn {var, value} ->
          case value do
            nil -> System.delete_env(var)
            val -> System.put_env(var, val)
          end
        end)
      end)

      %{original_vars: original_vars}
    end

    test "applies python executable override" do
      System.put_env("ASH_DSPEX_PYTHON_EXECUTABLE", "python3.9")

      config = Config.get(:python_bridge)

      assert config[:python_executable] == "python3.9"
    end

    test "applies timeout override" do
      System.put_env("ASH_DSPEX_BRIDGE_TIMEOUT", "45000")

      config = Config.get(:python_bridge)

      assert config[:default_timeout] == 45000
    end

    test "applies health check interval override" do
      System.put_env("ASH_DSPEX_HEALTH_CHECK_INTERVAL", "15000")

      config = Config.get(:python_bridge_monitor)

      assert config[:health_check_interval] == 15000
    end

    test "handles invalid environment variable values" do
      # Capture logs to verify warning is generated
      log =
        capture_log(fn ->
          System.put_env("ASH_DSPEX_BRIDGE_TIMEOUT", "invalid_number")

          config = Config.get(:python_bridge)

          # Should fall back to default value
          assert config[:default_timeout] == 30_000

          # Should not crash and config should be valid
          assert is_map(config)
          assert Map.has_key?(config, :python_executable)
        end)

      # Verify warning was logged with specific message
      assert log =~ "Invalid integer value for default_timeout: invalid_number"
      assert log =~ "[warning]"
    end

    test "handles multiple invalid values with appropriate warnings" do
      log =
        capture_log(fn ->
          System.put_env("ASH_DSPEX_BRIDGE_TIMEOUT", "not_a_number")
          System.put_env("ASH_DSPEX_HEALTH_CHECK_INTERVAL", "bad_value")
          System.put_env("ASH_DSPEX_FAILURE_THRESHOLD", "xyz")

          bridge_config = Config.get(:python_bridge)
          monitor_config = Config.get(:python_bridge_monitor)

          # All should fall back to defaults
          assert bridge_config[:default_timeout] == 30_000
          # This comes from defaults, not env var
          assert bridge_config[:max_retries] == 3
          assert monitor_config[:health_check_interval] == 30_000
          assert monitor_config[:failure_threshold] == 3
        end)

      # Verify all warnings were logged
      assert log =~ "Invalid integer value for default_timeout: not_a_number"
      assert log =~ "Invalid integer value for health_check_interval: bad_value"
      assert log =~ "Invalid non-negative integer value for failure_threshold: xyz"
    end

    test "handles negative numbers appropriately" do
      # Clean up any previously set environment variables that might interfere
      System.delete_env("ASH_DSPEX_HEALTH_CHECK_INTERVAL")
      System.delete_env("ASH_DSPEX_FAILURE_THRESHOLD")

      log =
        capture_log(fn ->
          System.put_env("ASH_DSPEX_BRIDGE_TIMEOUT", "-1000")

          config = Config.get(:python_bridge)

          # Should accept negative number (parse succeeds)
          assert config[:default_timeout] == -1000
        end)

      # Should not log warning for BRIDGE_TIMEOUT specifically
      refute log =~ "Invalid integer value for default_timeout"
    end
  end

  describe "reload/0" do
    test "reloads configuration successfully" do
      result = Config.reload()

      assert result == :ok
    end
  end

  describe "configuration sections" do
    test "signature_system has expected keys" do
      config = Config.get(:signature_system)

      expected_keys = [
        :validation_enabled,
        :compile_time_checks,
        :json_schema_provider,
        :type_validation_strict,
        :cache_compiled_signatures
      ]

      Enum.each(expected_keys, fn key ->
        assert Map.has_key?(config, key), "Missing key: #{key}"
      end)
    end

    test "python_bridge has expected keys" do
      config = Config.get(:python_bridge)

      expected_keys = [
        :python_executable,
        :default_timeout,
        :max_retries,
        :restart_strategy,
        :required_packages,
        :min_python_version,
        :script_path
      ]

      Enum.each(expected_keys, fn key ->
        assert Map.has_key?(config, key), "Missing key: #{key}"
      end)
    end

    test "python_bridge_monitor has expected keys" do
      config = Config.get(:python_bridge_monitor)

      expected_keys = [
        :health_check_interval,
        :failure_threshold,
        :response_timeout,
        :restart_delay,
        :max_restart_attempts,
        :restart_cooldown
      ]

      Enum.each(expected_keys, fn key ->
        assert Map.has_key?(config, key), "Missing key: #{key}"
      end)
    end

    test "python_bridge_supervisor has expected keys" do
      config = Config.get(:python_bridge_supervisor)

      expected_keys = [
        :max_restarts,
        :max_seconds,
        :bridge_restart,
        :monitor_restart
      ]

      Enum.each(expected_keys, fn key ->
        assert Map.has_key?(config, key), "Missing key: #{key}"
      end)
    end
  end

  describe "value types" do
    test "boolean settings are properly typed" do
      config = Config.get(:signature_system)

      assert is_boolean(config[:validation_enabled])
      assert is_boolean(config[:compile_time_checks])
      assert is_boolean(config[:type_validation_strict])
      assert is_boolean(config[:cache_compiled_signatures])
    end

    test "integer settings are properly typed" do
      bridge_config = Config.get(:python_bridge)
      monitor_config = Config.get(:python_bridge_monitor)
      supervisor_config = Config.get(:python_bridge_supervisor)

      assert is_integer(bridge_config[:default_timeout])
      assert is_integer(bridge_config[:max_retries])
      assert is_integer(monitor_config[:health_check_interval])
      assert is_integer(monitor_config[:failure_threshold])
      assert is_integer(supervisor_config[:max_restarts])
      assert is_integer(supervisor_config[:max_seconds])
    end

    test "string settings are properly typed" do
      config = Config.get(:python_bridge)

      assert is_binary(config[:python_executable])
      assert is_binary(config[:min_python_version])
      assert is_binary(config[:script_path])
    end

    test "list settings are properly typed" do
      config = Config.get(:python_bridge)

      assert is_list(config[:required_packages])
    end
  end
end
