defmodule DSPex.PythonBridge.PoolConfig do
  @moduledoc """
  Configuration helper for the minimal Python pooling system.

  This module provides convenient access to pool configuration parameters
  and handles configuration validation and defaults for the Golden Path
  architecture.
  """

  alias DSPex.PythonBridge.Types

  @doc """
  Gets the complete pool configuration with all defaults applied.
  """
  @spec get_pool_config() :: Types.pool_config()
  def get_pool_config do
    config = DSPex.Config.get(:minimal_python_pool)

    %{
      pool_size: config.pool_size,
      overflow: config.overflow,
      checkout_timeout: config.checkout_timeout,
      operation_timeout: config.operation_timeout,
      python_executable: config.python_executable,
      script_path: config.script_path,
      health_check_enabled: config.health_check_enabled,
      session_tracking_enabled: config.session_tracking_enabled
    }
  end

  @doc """
  Gets a specific pool configuration value with optional default.
  """
  @spec get_pool_config(atom(), term()) :: term()
  def get_pool_config(key, default \\ nil) do
    DSPex.Config.get(:minimal_python_pool, key, default)
  end

  @doc """
  Validates the current pool configuration.
  """
  @spec validate_pool_config() :: :ok | {:error, [String.t()]}
  def validate_pool_config do
    case DSPex.Config.validate() do
      :ok ->
        :ok

      {:error, issues} ->
        # Filter for minimal_python_pool related issues
        pool_issues =
          Enum.filter(
            issues,
            &String.contains?(&1, [
              "pool_size",
              "overflow",
              "checkout_timeout",
              "operation_timeout"
            ])
          )

        case pool_issues do
          [] -> :ok
          problems -> {:error, problems}
        end
    end
  end

  @doc """
  Gets NimblePool configuration options from the pool config.
  """
  @spec get_nimble_pool_options() :: keyword()
  def get_nimble_pool_options do
    config = get_pool_config()

    [
      pool_size: config.pool_size,
      max_overflow: config.overflow,
      checkout_timeout: config.checkout_timeout
    ]
  end

  @doc """
  Gets worker initialization options from the pool config.
  """
  @spec get_worker_init_options() :: map()
  def get_worker_init_options do
    config = get_pool_config()

    %{
      python_executable: config.python_executable,
      script_path: config.script_path,
      operation_timeout: config.operation_timeout,
      health_check_enabled: config.health_check_enabled
    }
  end

  @doc """
  Gets session tracking configuration.
  """
  @spec get_session_config() :: map()
  def get_session_config do
    config = get_pool_config()

    %{
      enabled: config.session_tracking_enabled,
      # 5 minutes
      cleanup_interval: 300_000,
      # 30 minutes
      session_timeout: 1_800_000
    }
  end

  @doc """
  Gets health check configuration.
  """
  @spec get_health_config() :: map()
  def get_health_config do
    config = get_pool_config()

    %{
      enabled: config.health_check_enabled,
      # 1 minute
      check_interval: 60_000,
      failure_threshold: 3,
      # 5 seconds
      recovery_delay: 5_000
    }
  end

  @doc """
  Determines if the pool should be started based on configuration.
  """
  @spec should_start_pool?() :: true
  def should_start_pool? do
    config = get_pool_config()
    config.pool_size > 0
  end

  @doc """
  Gets the Python script path, resolving relative paths.
  """
  @spec get_script_path() :: String.t() | Path.t()
  def get_script_path do
    script_path = get_pool_config(:script_path)

    if Path.type(script_path) == :absolute do
      script_path
    else
      # Resolve relative to the application root
      Application.app_dir(:dspex, script_path)
    end
  end

  @doc """
  Gets the Python executable path with validation.
  """
  @spec get_python_executable() :: {:ok, String.t()} | {:error, String.t()}
  def get_python_executable do
    executable = get_pool_config(:python_executable)

    case System.find_executable(executable) do
      nil -> {:error, "Python executable not found: #{executable}"}
      path -> {:ok, path}
    end
  end

  @doc """
  Creates a configuration summary for logging and debugging.
  """
  @spec config_summary() :: map()
  def config_summary do
    config = get_pool_config()

    %{
      pool_size: config.pool_size,
      overflow: config.overflow,
      timeouts: %{
        checkout: config.checkout_timeout,
        operation: config.operation_timeout
      },
      features: %{
        health_checks: config.health_check_enabled,
        session_tracking: config.session_tracking_enabled
      },
      python: %{
        executable: config.python_executable,
        script_path: config.script_path
      }
    }
  end

  @doc """
  Validates that required files exist for the pool configuration.
  """
  @spec validate_files() :: :ok | {:error, [String.t()]}
  def validate_files do
    issues = []

    # Check Python executable
    issues =
      case get_python_executable() do
        {:ok, _} -> issues
        {:error, error} -> [error | issues]
      end

    # Check script path
    script_path = get_script_path()

    issues =
      if File.exists?(script_path) do
        issues
      else
        ["Python script not found: #{script_path}" | issues]
      end

    case issues do
      [] -> :ok
      problems -> {:error, Enum.reverse(problems)}
    end
  end

  @doc """
  Gets environment-specific configuration overrides.
  """
  @spec get_env_overrides() :: map()
  def get_env_overrides do
    env = Application.get_env(:dspex, :env, :dev)

    case env do
      :test ->
        %{
          pool_size: 2,
          overflow: 1,
          checkout_timeout: 10_000,
          operation_timeout: 15_000
        }

      :dev ->
        %{
          pool_size: 2,
          overflow: 1,
          health_check_enabled: true
        }

      :prod ->
        %{
          pool_size: System.schedulers_online() * 2,
          overflow: System.schedulers_online(),
          health_check_enabled: true,
          session_tracking_enabled: true
        }

      _ ->
        %{}
    end
  end
end
