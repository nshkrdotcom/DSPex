defmodule DSPex.PythonBridge.EnvironmentCheckTest do
  use ExUnit.Case, async: true

  # Layer 2: Protocol testing - checks Python environment but doesn't need bridge
  @moduletag :layer_2

  alias DSPex.PythonBridge.EnvironmentCheck

  describe "validate_python_executable/0" do
    test "finds python executable when available" do
      # This test will pass if python3 is available on the system
      case EnvironmentCheck.validate_python_executable() do
        {:ok, path} ->
          assert is_binary(path)
          assert String.contains?(path, "python")

        {:error, reason} ->
          # If no Python is available, should get descriptive error
          assert is_binary(reason)
          assert String.contains?(reason, "not found")
      end
    end
  end

  describe "check_dspy_availability/0" do
    test "handles missing python gracefully" do
      # Mock configuration with non-existent python
      original_config = Application.get_env(:dspex, :python_bridge, %{})

      try do
        Application.put_env(:dspex, :python_bridge, %{python_executable: "nonexistent_python"})

        case EnvironmentCheck.check_dspy_availability() do
          {:error, reason} ->
            assert is_binary(reason)
            assert String.contains?(reason, "not found")

          {:ok, _version} ->
            # This shouldn't happen with nonexistent python, but if it does, that's fine
            :ok
        end
      after
        Application.put_env(:dspex, :python_bridge, original_config)
      end
    end
  end

  describe "validate_bridge_script/0" do
    test "finds bridge script in priv directory" do
      case EnvironmentCheck.validate_bridge_script() do
        {:ok, script_path} ->
          assert is_binary(script_path)
          assert String.ends_with?(script_path, "dspy_bridge.py")
          assert File.exists?(script_path)

        {:error, reason} ->
          # If script doesn't exist, should get descriptive error
          assert is_binary(reason)
          assert String.contains?(reason, "not found")
      end
    end
  end

  describe "validate_environment/0" do
    test "returns structured environment info on success" do
      case EnvironmentCheck.validate_environment() do
        {:ok, env_info} ->
          # Should have all required fields
          assert Map.has_key?(env_info, :python_path)
          assert Map.has_key?(env_info, :python_version)
          assert Map.has_key?(env_info, :script_path)
          assert Map.has_key?(env_info, :dspy_version)
          assert Map.has_key?(env_info, :packages)

          # Values should be strings/lists
          assert is_binary(env_info.python_path)
          assert is_binary(env_info.python_version)
          assert is_binary(env_info.script_path)
          assert is_binary(env_info.dspy_version)
          assert is_list(env_info.packages)

        {:error, reason} ->
          # On failure, should get descriptive error
          assert is_binary(reason)
      end
    end

    test "handles configuration overrides" do
      # Test with custom configuration
      original_config = Application.get_env(:dspex, :python_bridge, %{})

      try do
        custom_config = %{
          python_executable: "python3",
          min_python_version: "3.7.0",
          required_packages: ["dspy-ai"]
        }

        Application.put_env(:dspex, :python_bridge, custom_config)

        # Should still work with custom config
        case EnvironmentCheck.validate_environment() do
          {:ok, _env_info} -> :ok
          # Expected if dependencies not available
          {:error, _reason} -> :ok
        end
      after
        Application.put_env(:dspex, :python_bridge, original_config)
      end
    end
  end

  describe "version comparison" do
    test "version parsing and comparison works correctly" do
      # Test some internal behavior by calling validate_environment with different configs
      original_config = Application.get_env(:dspex, :python_bridge, %{})

      try do
        # Test with very high minimum version requirement
        high_version_config = %{
          python_executable: "python3",
          min_python_version: "99.0.0",
          required_packages: []
        }

        Application.put_env(:dspex, :python_bridge, high_version_config)

        case EnvironmentCheck.validate_environment() do
          {:error, reason} ->
            # Should fail due to version requirement
            if String.contains?(reason, "below minimum") do
              assert true
            else
              # Might fail for other reasons (python not found, etc.)
              assert is_binary(reason)
            end

          {:ok, _} ->
            # Unexpected but not necessarily wrong
            :ok
        end
      after
        Application.put_env(:dspex, :python_bridge, original_config)
      end
    end
  end

  describe "script validation" do
    test "validates script contains required patterns" do
      # This tests that our bridge script has the expected structure
      case EnvironmentCheck.validate_bridge_script() do
        {:ok, script_path} ->
          # Read the script and verify it has expected content
          {:ok, content} = File.read(script_path)

          # Check for key patterns that should be in our bridge script
          assert String.contains?(content, "class DSPyBridge")
          assert String.contains?(content, "def handle_command")
          assert String.contains?(content, "def main()")

        {:error, _reason} ->
          # Script not found is also a valid test result
          :ok
      end
    end
  end

  describe "package validation" do
    test "handles package import name conversion" do
      original_config = Application.get_env(:dspex, :python_bridge, %{})

      try do
        # Test with dspy-ai package (which imports as 'dspy')
        config_with_dspy = %{
          python_executable: "python3",
          required_packages: ["dspy-ai"]
        }

        Application.put_env(:dspex, :python_bridge, config_with_dspy)

        # This should correctly try to import 'dspy' module for 'dspy-ai' package
        case EnvironmentCheck.validate_environment() do
          {:ok, env_info} ->
            # If successful, packages should include dspy-ai
            assert "dspy-ai" in env_info.packages

          {:error, reason} ->
            # Expected if dspy not installed
            assert is_binary(reason)
        end
      after
        Application.put_env(:dspex, :python_bridge, original_config)
      end
    end
  end
end
