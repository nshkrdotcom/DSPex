# Stage 1 Prompt 9: Configuration and Application Setup

## OBJECTIVE

Implement comprehensive configuration management and application setup for the DSPy-Ash integration, including environment-specific configurations, runtime configuration validation, application supervision trees, dependency management, and deployment preparation. This system must be flexible, secure, and production-ready with proper defaults and clear configuration patterns.

## COMPLETE IMPLEMENTATION CONTEXT

### APPLICATION ARCHITECTURE OVERVIEW

From STAGE_1_FOUNDATION_IMPLEMENTATION.md and Elixir application patterns:

```
┌─────────────────────────────────────────────────────────────┐
│                Application Setup Architecture               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Configuration   │  │ Supervision     │  │ Dependencies ││
│  │ - Environment   │  │ Tree            │  │ - Python     ││
│  │ - Runtime       │  │ - GenServers    │  │ - Database   ││
│  │ - Validation    │  │ - Workers       │  │ - External   ││
│  │ - Secrets       │  │ - Fault Tolerance│  │   Services   ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Development     │  │ Production      │  │ Testing      ││
│  │ Environment     │  │ Environment     │  │ Environment  ││
│  │ - Debug mode    │  │ - Performance   │  │ - Mocks      ││
│  │ - Local adapters│  │ - Security      │  │ - Fixtures   ││
│  │ - Hot reload    │  │ - Monitoring    │  │ - Isolation  ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### EXISTING CONFIGURATION FOUNDATION

From STAGE_1_FOUNDATION_IMPLEMENTATION.md:

```elixir
# config/config.exs
import Config

config :ash_dspy, :adapter, AshDSPy.Adapters.PythonPort

config :ash_dspy, AshDSPy.Repo,
  username: "postgres",
  password: "postgres", 
  hostname: "localhost",
  database: "ash_dspy_dev",
  pool_size: 10

config :ash_dspy,
  ecto_repos: [AshDSPy.Repo]
```

### COMPREHENSIVE APPLICATION CONFIGURATION

**Complete Configuration System:**
```elixir
# config/config.exs
import Config

# Core application configuration
config :ash_dspy,
  # Domain and resource configuration
  domains: [AshDSPy.ML.Domain],
  ecto_repos: [AshDSPy.Repo],
  
  # Default adapter configuration
  adapter: AshDSPy.Adapters.PythonPort,
  adapter_timeout: 30_000,
  
  # Signature system configuration
  signature_compilation: [
    enable_cache: true,
    cache_ttl: 3600,  # 1 hour
    validate_at_compile_time: true
  ],
  
  # Type system configuration
  type_validation: [
    enable_cache: true,
    cache_size: 10_000,
    strict_mode: false,
    coercion_enabled: true
  ],
  
  # Protocol configuration
  wire_protocol: [
    version: "1.0",
    compression: [
      enabled: true,
      threshold: 1024,  # 1KB
      level: 6
    ],
    max_message_size: 100 * 1024 * 1024,  # 100MB
    checksum_validation: true
  ],
  
  # Performance configuration
  performance: [
    max_concurrent_executions: 100,
    execution_timeout: 60_000,  # 1 minute
    memory_limit: 2 * 1024 * 1024 * 1024,  # 2GB
    gc_interval: 300_000  # 5 minutes
  ],
  
  # Logging configuration
  logging: [
    level: :info,
    structured: true,
    include_metadata: [:request_id, :program_id, :signature_module],
    sensitive_fields: [:api_keys, :tokens, :passwords]
  ],
  
  # Security configuration
  security: [
    enable_input_sanitization: true,
    max_input_size: 10 * 1024 * 1024,  # 10MB
    allowed_file_types: [".py", ".json", ".txt"],
    rate_limiting: [
      enabled: true,
      requests_per_minute: 1000,
      burst_size: 100
    ]
  ]

# Python bridge configuration
config :ash_dspy, :python_bridge,
  executable: System.get_env("PYTHON_EXECUTABLE", "python3"),
  script_path: "python/dspy_bridge.py",
  startup_timeout: 30_000,
  health_check_interval: 30_000,
  restart_strategy: :permanent,
  environment_variables: %{
    "PYTHONPATH" => System.get_env("PYTHONPATH", ""),
    "DSPY_ENV" => System.get_env("DSPY_ENV", "production")
  }

# Database configuration with connection pooling
config :ash_dspy, AshDSPy.Repo,
  username: System.get_env("DATABASE_USERNAME", "postgres"),
  password: System.get_env("DATABASE_PASSWORD", "postgres"),
  hostname: System.get_env("DATABASE_HOSTNAME", "localhost"),
  port: String.to_integer(System.get_env("DATABASE_PORT", "5432")),
  database: System.get_env("DATABASE_NAME", "ash_dspy_dev"),
  pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE", "10")),
  queue_target: 5000,
  queue_interval: 1000,
  timeout: 60_000,
  ownership_timeout: 60_000,
  ssl: String.to_existing_atom(System.get_env("DATABASE_SSL", "false")),
  ssl_opts: [
    verify: :verify_peer,
    cacertfile: System.get_env("DATABASE_CA_CERT_FILE"),
    server_name_indication: :disable
  ]

# Telemetry and monitoring
config :ash_dspy, :telemetry,
  events: [
    [:ash_dspy, :signature, :compilation],
    [:ash_dspy, :program, :execution],
    [:ash_dspy, :adapter, :call],
    [:ash_dspy, :python_bridge, :communication],
    [:ash_dspy, :type, :validation]
  ],
  metrics: [
    counter: [:ash_dspy, :executions, :total],
    histogram: [:ash_dspy, :execution, :duration],
    gauge: [:ash_dspy, :programs, :active],
    summary: [:ash_dspy, :adapter, :response_time]
  ],
  reporters: [
    {AshDSPy.Telemetry.ConsoleReporter, []},
    {AshDSPy.Telemetry.MetricsReporter, []}
  ]

# External service configuration
config :ash_dspy, :external_services,
  openai: [
    api_key: System.get_env("OPENAI_API_KEY"),
    api_base: System.get_env("OPENAI_API_BASE", "https://api.openai.com/v1"),
    organization: System.get_env("OPENAI_ORGANIZATION"),
    timeout: 60_000,
    max_retries: 3
  ],
  anthropic: [
    api_key: System.get_env("ANTHROPIC_API_KEY"),
    api_base: System.get_env("ANTHROPIC_API_BASE", "https://api.anthropic.com"),
    timeout: 60_000,
    max_retries: 3
  ]

# Environment-specific configurations
import_config "#{config_env()}.exs"
```

### ENVIRONMENT-SPECIFIC CONFIGURATIONS

**Development Configuration:**
```elixir
# config/dev.exs
import Config

# Development-specific overrides
config :ash_dspy,
  adapter: AshDSPy.Adapters.Mock,  # Use mock adapter for development
  
  signature_compilation: [
    enable_cache: false,  # Disable cache for hot reloading
    validate_at_compile_time: true
  ],
  
  type_validation: [
    strict_mode: true,  # Stricter validation in development
    enable_cache: false
  ],
  
  logging: [
    level: :debug,
    structured: false,  # Pretty printing for development
    include_metadata: [:request_id, :program_id, :signature_module, :line, :function]
  ],
  
  security: [
    enable_input_sanitization: false,  # Relaxed for development
    rate_limiting: [enabled: false]
  ]

# Development database
config :ash_dspy, AshDSPy.Repo,
  database: "ash_dspy_dev",
  hostname: "localhost",
  port: 5432,
  show_sensitive_data_on_connection_error: true,
  pool_size: 5

# Development Python bridge
config :ash_dspy, :python_bridge,
  executable: "python3",
  health_check_interval: 10_000,  # More frequent checks
  environment_variables: %{
    "DSPY_ENV" => "development",
    "DSPY_DEBUG" => "true"
  }

# Enable code reloading
config :ash_dspy, :phoenix_live_reload,
  patterns: [
    ~r"lib/ash_dspy/.*(ex)$",
    ~r"test/.*(exs)$"
  ]

# Console configuration for development
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :program_id]
```

**Production Configuration:**
```elixir
# config/prod.exs
import Config

# Production-specific configuration
config :ash_dspy,
  adapter: AshDSPy.Adapters.PythonPort,  # Use real adapters in production
  
  signature_compilation: [
    enable_cache: true,
    cache_ttl: 3600,
    validate_at_compile_time: false  # Skip expensive validation in production
  ],
  
  type_validation: [
    enable_cache: true,
    cache_size: 50_000,  # Larger cache in production
    strict_mode: false
  ],
  
  logging: [
    level: :info,
    structured: true,
    include_metadata: [:request_id, :program_id],
    sensitive_fields: [:api_keys, :tokens, :passwords, :database_url]
  ],
  
  security: [
    enable_input_sanitization: true,
    max_input_size: 5 * 1024 * 1024,  # Smaller limit in production
    rate_limiting: [
      enabled: true,
      requests_per_minute: 500,  # Lower limit in production
      burst_size: 50
    ]
  ],
  
  performance: [
    max_concurrent_executions: 200,  # Higher concurrency in production
    execution_timeout: 120_000,  # Longer timeout
    memory_limit: 8 * 1024 * 1024 * 1024,  # 8GB
    gc_interval: 60_000  # More frequent GC
  ]

# Production database with SSL
config :ash_dspy, AshDSPy.Repo,
  url: System.get_env("DATABASE_URL") || raise("DATABASE_URL not set"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "20")),
  ssl: true,
  ssl_opts: [
    verify: :verify_peer,
    cacertfile: System.get_env("DATABASE_CA_CERT_FILE") || "/etc/ssl/certs/ca-certificates.crt",
    server_name_indication: System.get_env("DATABASE_HOSTNAME") |> String.to_charlist()
  ]

# Production telemetry with external monitoring
config :ash_dspy, :telemetry,
  reporters: [
    {AshDSPy.Telemetry.PrometheusReporter, []},
    {AshDSPy.Telemetry.DatadogReporter, []},
    {AshDSPy.Telemetry.SentryReporter, []}
  ]

# External service timeouts for production
config :ash_dspy, :external_services,
  openai: [
    timeout: 30_000,  # Shorter timeout in production
    max_retries: 2
  ],
  anthropic: [
    timeout: 30_000,
    max_retries: 2
  ]

# Production logging
config :logger,
  level: :info,
  backends: [:console, {LoggerJSON, :default}]

config :logger, :console,
  format: {LoggerJSON, :format},
  metadata: :all
```

**Test Configuration:**
```elixir
# config/test.exs
import Config

# Test-specific configuration
config :ash_dspy,
  adapter: AshDSPy.Adapters.Mock,  # Always use mock in tests
  
  signature_compilation: [
    enable_cache: false,  # Disable cache for test isolation
    validate_at_compile_time: true
  ],
  
  type_validation: [
    enable_cache: false,  # Disable cache for test isolation
    strict_mode: true
  ],
  
  logging: [
    level: :warning,  # Reduce log noise in tests
    structured: false
  ],
  
  security: [
    enable_input_sanitization: false,  # Relaxed for testing
    rate_limiting: [enabled: false]
  ],
  
  performance: [
    max_concurrent_executions: 10,  # Lower concurrency for tests
    execution_timeout: 5_000  # Shorter timeout for tests
  ]

# Test database
config :ash_dspy, AshDSPy.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ash_dspy_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Disable telemetry in tests
config :ash_dspy, :telemetry,
  events: [],
  metrics: [],
  reporters: []

# Test logging
config :logger, level: :warning
```

### CONFIGURATION VALIDATION SYSTEM

**Runtime Configuration Validation:**
```elixir
defmodule AshDSPy.Config.Validator do
  @moduledoc """
  Validates application configuration at startup and runtime.
  Ensures all required settings are present and valid.
  """
  
  require Logger
  
  @required_configs [
    {:ash_dspy, :adapter},
    {:ash_dspy, :domains},
    {:ash_dspy, AshDSPy.Repo}
  ]
  
  @adapter_configs %{
    AshDSPy.Adapters.PythonPort => [
      {:ash_dspy, :python_bridge, :executable},
      {:ash_dspy, :python_bridge, :script_path}
    ],
    AshDSPy.Adapters.Mock => []
  }
  
  def validate_config! do
    case validate_config() do
      :ok -> :ok
      {:error, errors} -> 
        formatted_errors = format_errors(errors)
        raise """
        Configuration validation failed:
        #{formatted_errors}
        
        Please check your configuration files and environment variables.
        """
    end
  end
  
  def validate_config do
    errors = []
    
    errors = errors ++ validate_required_configs()
    errors = errors ++ validate_adapter_config()
    errors = errors ++ validate_database_config()
    errors = errors ++ validate_python_bridge_config()
    errors = errors ++ validate_security_config()
    errors = errors ++ validate_performance_config()
    
    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end
  
  defp validate_required_configs do
    Enum.flat_map(@required_configs, fn config_key ->
      case get_config(config_key) do
        nil -> [{:missing_config, config_key}]
        _ -> []
      end
    end)
  end
  
  defp validate_adapter_config do
    adapter = Application.get_env(:ash_dspy, :adapter)
    
    case adapter do
      nil -> 
        [{:missing_config, {:ash_dspy, :adapter}}]
      
      adapter_module when is_atom(adapter_module) ->
        validate_adapter_module(adapter_module) ++ validate_adapter_dependencies(adapter_module)
      
      _ -> 
        [{:invalid_config, {:ash_dspy, :adapter}, "must be an atom"}]
    end
  end
  
  defp validate_adapter_module(adapter_module) do
    case Code.ensure_loaded(adapter_module) do
      {:module, _} ->
        required_functions = [:create_program, :execute_program, :list_programs]
        missing_functions = Enum.filter(required_functions, fn func ->
          not function_exported?(adapter_module, func, 1)
        end)
        
        if Enum.empty?(missing_functions) do
          []
        else
          [{:invalid_adapter, adapter_module, "missing functions: #{inspect(missing_functions)}"}]
        end
      
      {:error, reason} ->
        [{:invalid_adapter, adapter_module, "failed to load: #{reason}"}]
    end
  end
  
  defp validate_adapter_dependencies(adapter_module) do
    required_configs = Map.get(@adapter_configs, adapter_module, [])
    
    Enum.flat_map(required_configs, fn config_key ->
      case get_config(config_key) do
        nil -> [{:missing_adapter_config, adapter_module, config_key}]
        _ -> []
      end
    end)
  end
  
  defp validate_database_config do
    repo_config = Application.get_env(:ash_dspy, AshDSPy.Repo, [])
    errors = []
    
    # Check required database fields
    required_fields = [:username, :password, :hostname, :database]
    errors = errors ++ Enum.flat_map(required_fields, fn field ->
      case Keyword.get(repo_config, field) do
        nil -> [{:missing_database_config, field}]
        "" -> [{:empty_database_config, field}]
        _ -> []
      end
    end)
    
    # Validate pool size
    case Keyword.get(repo_config, :pool_size) do
      nil -> 
        errors ++ [{:missing_database_config, :pool_size}]
      size when is_integer(size) and size > 0 ->
        errors
      _ ->
        errors ++ [{:invalid_database_config, :pool_size, "must be a positive integer"}]
    end
  end
  
  defp validate_python_bridge_config do
    adapter = Application.get_env(:ash_dspy, :adapter)
    
    if adapter == AshDSPy.Adapters.PythonPort do
      bridge_config = Application.get_env(:ash_dspy, :python_bridge, [])
      errors = []
      
      # Check Python executable
      executable = Keyword.get(bridge_config, :executable, "python3")
      errors = case System.find_executable(executable) do
        nil -> errors ++ [{:python_not_found, executable}]
        _ -> errors
      end
      
      # Check script path
      script_path = Keyword.get(bridge_config, :script_path)
      case script_path do
        nil ->
          errors ++ [{:missing_python_config, :script_path}]
        
        path ->
          full_path = Path.join(:code.priv_dir(:ash_dspy), path)
          if File.exists?(full_path) do
            errors
          else
            errors ++ [{:python_script_not_found, full_path}]
          end
      end
    else
      []
    end
  end
  
  defp validate_security_config do
    security_config = Application.get_env(:ash_dspy, :security, [])
    errors = []
    
    # Validate rate limiting config
    rate_limiting = Keyword.get(security_config, :rate_limiting, [])
    if Keyword.get(rate_limiting, :enabled, false) do
      rpm = Keyword.get(rate_limiting, :requests_per_minute)
      burst = Keyword.get(rate_limiting, :burst_size)
      
      errors = case rpm do
        n when is_integer(n) and n > 0 -> errors
        _ -> errors ++ [{:invalid_security_config, :requests_per_minute, "must be positive integer"}]
      end
      
      errors = case burst do
        n when is_integer(n) and n > 0 -> errors
        _ -> errors ++ [{:invalid_security_config, :burst_size, "must be positive integer"}]
      end
      
      errors
    else
      errors
    end
  end
  
  defp validate_performance_config do
    perf_config = Application.get_env(:ash_dspy, :performance, [])
    errors = []
    
    # Validate numeric performance settings
    numeric_settings = [
      {:max_concurrent_executions, 1, 10000},
      {:execution_timeout, 1000, 600_000},
      {:memory_limit, 100 * 1024 * 1024, 100 * 1024 * 1024 * 1024}  # 100MB to 100GB
    ]
    
    Enum.flat_map(numeric_settings, fn {setting, min_val, max_val} ->
      case Keyword.get(perf_config, setting) do
        nil -> []
        value when is_integer(value) and value >= min_val and value <= max_val -> []
        value -> [{:invalid_performance_config, setting, "must be between #{min_val} and #{max_val}, got #{value}"}]
      end
    end)
  end
  
  defp get_config({app, key}) do
    Application.get_env(app, key)
  end
  
  defp get_config({app, key, subkey}) do
    app
    |> Application.get_env(key, [])
    |> Keyword.get(subkey)
  end
  
  defp format_errors(errors) do
    errors
    |> Enum.map(&format_error/1)
    |> Enum.join("\n")
  end
  
  defp format_error({:missing_config, config_key}) do
    "- Missing required configuration: #{inspect(config_key)}"
  end
  
  defp format_error({:invalid_config, config_key, reason}) do
    "- Invalid configuration #{inspect(config_key)}: #{reason}"
  end
  
  defp format_error({:invalid_adapter, adapter, reason}) do
    "- Invalid adapter #{adapter}: #{reason}"
  end
  
  defp format_error({:missing_adapter_config, adapter, config_key}) do
    "- Adapter #{adapter} requires configuration: #{inspect(config_key)}"
  end
  
  defp format_error({:missing_database_config, field}) do
    "- Missing database configuration: #{field}"
  end
  
  defp format_error({:empty_database_config, field}) do
    "- Empty database configuration: #{field}"
  end
  
  defp format_error({:invalid_database_config, field, reason}) do
    "- Invalid database configuration #{field}: #{reason}"
  end
  
  defp format_error({:python_not_found, executable}) do
    "- Python executable not found: #{executable}"
  end
  
  defp format_error({:missing_python_config, field}) do
    "- Missing Python bridge configuration: #{field}"
  end
  
  defp format_error({:python_script_not_found, path}) do
    "- Python bridge script not found: #{path}"
  end
  
  defp format_error({:invalid_security_config, field, reason}) do
    "- Invalid security configuration #{field}: #{reason}"
  end
  
  defp format_error({:invalid_performance_config, field, reason}) do
    "- Invalid performance configuration #{field}: #{reason}"
  end
  
  defp format_error(error) do
    "- Unknown configuration error: #{inspect(error)}"
  end
end
```

### APPLICATION SUPERVISION TREE

**Complete Application Module:**
```elixir
defmodule AshDSPy.Application do
  @moduledoc """
  Main application module for AshDSPy.
  Defines the supervision tree and startup logic.
  """
  
  use Application
  
  alias AshDSPy.Config.Validator
  
  def start(_type, _args) do
    # Validate configuration before starting
    Validator.validate_config!()
    
    # Setup telemetry
    setup_telemetry()
    
    # Define supervision tree
    children = build_supervision_tree()
    
    # Start supervisor with fault tolerance strategy
    opts = [
      strategy: :one_for_one, 
      name: AshDSPy.Supervisor,
      max_restarts: 3,
      max_seconds: 60
    ]
    
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("AshDSPy application started successfully")
        post_startup_tasks()
        {:ok, pid}
      
      {:error, reason} ->
        Logger.error("Failed to start AshDSPy application: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  def stop(_state) do
    Logger.info("AshDSPy application stopping")
    cleanup_resources()
    :ok
  end
  
  defp build_supervision_tree do
    # Base children that always start
    base_children = [
      # Configuration cache
      {AshDSPy.Config.Cache, []},
      
      # Type system cache
      {AshDSPy.Types.Cache, []},
      
      # Database repo (if configured)
      database_child(),
      
      # Telemetry supervisor
      {AshDSPy.Telemetry.Supervisor, []},
      
      # Core domain supervisor
      {AshDSPy.ML.Supervisor, []}
    ]
    
    # Add adapter-specific children
    adapter_children = build_adapter_children()
    
    # Add optional children based on configuration
    optional_children = build_optional_children()
    
    (base_children ++ adapter_children ++ optional_children)
    |> Enum.filter(& &1)  # Remove nil entries
  end
  
  defp database_child do
    if Application.get_env(:ash_dspy, AshDSPy.Repo) do
      {AshDSPy.Repo, []}
    else
      nil
    end
  end
  
  defp build_adapter_children do
    adapter = Application.get_env(:ash_dspy, :adapter)
    
    case adapter do
      AshDSPy.Adapters.PythonPort ->
        [
          # Python bridge
          {AshDSPy.PythonBridge.Supervisor, []},
          
          # Bridge health monitor
          {AshDSPy.PythonBridge.Monitor, []}
        ]
      
      AshDSPy.Adapters.Mock ->
        [
          # Mock adapter
          {AshDSPy.Adapters.Mock, []}
        ]
      
      _ ->
        []
    end
  end
  
  defp build_optional_children do
    optional = []
    
    # Add rate limiter if security is enabled
    optional = if security_enabled?() do
      optional ++ [{AshDSPy.Security.RateLimiter, []}]
    else
      optional
    end
    
    # Add performance monitor if configured
    optional = if performance_monitoring_enabled?() do
      optional ++ [{AshDSPy.Performance.Monitor, []}]
    else
      optional
    end
    
    # Add external service monitors
    optional = if external_services_configured?() do
      optional ++ [{AshDSPy.ExternalServices.Supervisor, []}]
    else
      optional
    end
    
    optional
  end
  
  defp security_enabled? do
    Application.get_env(:ash_dspy, :security, [])
    |> Keyword.get(:rate_limiting, [])
    |> Keyword.get(:enabled, false)
  end
  
  defp performance_monitoring_enabled? do
    Application.get_env(:ash_dspy, :performance, [])
    |> Keyword.get(:monitoring_enabled, false)
  end
  
  defp external_services_configured? do
    external_config = Application.get_env(:ash_dspy, :external_services, [])
    
    Enum.any?([:openai, :anthropic], fn service ->
      service_config = Keyword.get(external_config, service, [])
      Keyword.get(service_config, :api_key) != nil
    end)
  end
  
  defp setup_telemetry do
    # Attach telemetry handlers
    events = Application.get_env(:ash_dspy, :telemetry, [])
             |> Keyword.get(:events, [])
    
    Enum.each(events, fn event ->
      :telemetry.attach(
        "ash_dspy_#{Enum.join(event, "_")}",
        event,
        &AshDSPy.Telemetry.Handler.handle_event/4,
        %{}
      )
    end)
    
    # Start telemetry reporters
    reporters = Application.get_env(:ash_dspy, :telemetry, [])
               |> Keyword.get(:reporters, [])
    
    Enum.each(reporters, fn {reporter_module, opts} ->
      apply(reporter_module, :start_link, [opts])
    end)
  end
  
  defp post_startup_tasks do
    # Warm up caches
    Task.start(fn ->
      AshDSPy.Types.Cache.warm_up()
      AshDSPy.Config.Cache.warm_up()
    end)
    
    # Verify adapter connectivity
    Task.start(fn ->
      adapter = Application.get_env(:ash_dspy, :adapter)
      case AshDSPy.Adapters.Registry.validate_adapter(adapter) do
        {:ok, _} -> 
          Logger.info("Adapter #{adapter} validated successfully")
        {:error, reason} -> 
          Logger.warning("Adapter validation failed: #{reason}")
      end
    end)
    
    # Run health checks
    Task.start(fn ->
      Process.sleep(5000)  # Wait for services to fully start
      case AshDSPy.Health.Check.run_startup_checks() do
        :ok -> 
          Logger.info("Startup health checks passed")
        {:error, reason} -> 
          Logger.error("Startup health checks failed: #{reason}")
      end
    end)
  end
  
  defp cleanup_resources do
    # Cleanup type caches
    AshDSPy.Types.Cache.clear()
    
    # Cleanup configuration cache
    AshDSPy.Config.Cache.clear()
    
    # Close database connections
    if Process.whereis(AshDSPy.Repo) do
      AshDSPy.Repo.stop()
    end
    
    # Cleanup telemetry
    :telemetry.detach_all()
  end
end
```

### DOMAIN AND RESOURCE SUPERVISION

**ML Domain Supervisor:**
```elixir
defmodule AshDSPy.ML.Supervisor do
  @moduledoc """
  Supervisor for ML domain components.
  """
  
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    children = [
      # Signature registry
      {Registry, keys: :unique, name: AshDSPy.ML.SignatureRegistry},
      
      # Program manager
      {AshDSPy.ML.ProgramManager, []},
      
      # Execution tracker
      {AshDSPy.ML.ExecutionTracker, []},
      
      # Metrics collector
      {AshDSPy.ML.MetricsCollector, []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### ENVIRONMENT VARIABLE MANAGEMENT

**Environment Variable Loader:**
```elixir
defmodule AshDSPy.Config.Environment do
  @moduledoc """
  Manages environment variable loading and validation.
  """
  
  @required_env_vars %{
    development: [],
    test: [],
    production: [
      "DATABASE_URL",
      "SECRET_KEY_BASE"
    ]
  }
  
  @optional_env_vars [
    "PYTHON_EXECUTABLE",
    "PYTHONPATH",
    "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "DATABASE_POOL_SIZE",
    "DSPY_ENV"
  ]
  
  def load_environment! do
    env = config_env()
    
    # Check required environment variables
    required_vars = Map.get(@required_env_vars, env, [])
    missing_vars = Enum.filter(required_vars, fn var ->
      System.get_env(var) == nil
    end)
    
    unless Enum.empty?(missing_vars) do
      raise """
      Missing required environment variables for #{env} environment:
      #{Enum.join(missing_vars, "\n")}
      
      Please set these environment variables before starting the application.
      """
    end
    
    # Log optional environment variables that are set
    set_optional_vars = Enum.filter(@optional_env_vars, fn var ->
      System.get_env(var) != nil
    end)
    
    if not Enum.empty?(set_optional_vars) do
      Logger.info("Optional environment variables set: #{Enum.join(set_optional_vars, ", ")}")
    end
    
    :ok
  end
  
  def get_env(var_name, default \\ nil) do
    case System.get_env(var_name) do
      nil -> default
      "" -> default
      value -> value
    end
  end
  
  def get_env_as_integer(var_name, default \\ nil) do
    case get_env(var_name) do
      nil -> default
      value -> 
        case Integer.parse(value) do
          {int, ""} -> int
          _ -> 
            Logger.warning("Invalid integer value for #{var_name}: #{value}, using default: #{default}")
            default
        end
    end
  end
  
  def get_env_as_boolean(var_name, default \\ false) do
    case get_env(var_name) do
      nil -> default
      value -> 
        String.downcase(value) in ["true", "1", "yes", "on"]
    end
  end
  
  def get_env_as_list(var_name, separator \\ ",", default \\ []) do
    case get_env(var_name) do
      nil -> default
      value -> 
        value
        |> String.split(separator)
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&(&1 != ""))
    end
  end
  
  defp config_env do
    Application.get_env(:ash_dspy, :environment) || Mix.env()
  end
end
```

### SECRET MANAGEMENT

**Secret Management System:**
```elixir
defmodule AshDSPy.Config.Secrets do
  @moduledoc """
  Secure secret management for the application.
  """
  
  @secret_keys [
    :database_password,
    :secret_key_base,
    :openai_api_key,
    :anthropic_api_key,
    :encryption_key
  ]
  
  def load_secrets! do
    case config_env() do
      :production -> load_production_secrets!()
      :development -> load_development_secrets()
      :test -> load_test_secrets()
    end
  end
  
  defp load_production_secrets! do
    # In production, secrets should come from secure sources
    secret_source = Application.get_env(:ash_dspy, :secret_source, :env_vars)
    
    case secret_source do
      :env_vars -> 
        load_from_env_vars()
      
      :vault -> 
        load_from_vault()
      
      :aws_secrets_manager -> 
        load_from_aws_secrets_manager()
      
      :kubernetes_secrets -> 
        load_from_kubernetes_secrets()
      
      _ -> 
        raise "Unknown secret source: #{secret_source}"
    end
  end
  
  defp load_development_secrets do
    # Development can use .env files or default values
    load_from_env_file(".env.dev")
    :ok
  end
  
  defp load_test_secrets do
    # Test environment uses default test values
    :ok
  end
  
  defp load_from_env_vars do
    missing_secrets = Enum.filter(@secret_keys, fn key ->
      env_var = secret_key_to_env_var(key)
      System.get_env(env_var) == nil
    end)
    
    unless Enum.empty?(missing_secrets) do
      env_vars = Enum.map(missing_secrets, &secret_key_to_env_var/1)
      raise """
      Missing required secrets in environment variables:
      #{Enum.join(env_vars, "\n")}
      """
    end
    
    :ok
  end
  
  defp load_from_env_file(file_path) do
    if File.exists?(file_path) do
      file_path
      |> File.read!()
      |> String.split("\n")
      |> Enum.each(fn line ->
        case String.split(line, "=", parts: 2) do
          [key, value] when key != "" and value != "" ->
            System.put_env(String.trim(key), String.trim(value))
          _ -> 
            :ok
        end
      end)
    end
    
    :ok
  end
  
  defp load_from_vault do
    # Implementation for HashiCorp Vault
    vault_config = Application.get_env(:ash_dspy, :vault, [])
    vault_url = Keyword.get(vault_config, :url)
    vault_token = System.get_env("VAULT_TOKEN")
    
    unless vault_url and vault_token do
      raise "Vault configuration incomplete. Need VAULT_URL and VAULT_TOKEN."
    end
    
    # Load secrets from Vault
    # This would use a Vault client library
    Logger.info("Loading secrets from Vault at #{vault_url}")
    :ok
  end
  
  defp load_from_aws_secrets_manager do
    # Implementation for AWS Secrets Manager
    secret_name = Application.get_env(:ash_dspy, :aws_secret_name)
    
    unless secret_name do
      raise "AWS Secrets Manager secret name not configured"
    end
    
    # Load secrets from AWS
    Logger.info("Loading secrets from AWS Secrets Manager: #{secret_name}")
    :ok
  end
  
  defp load_from_kubernetes_secrets do
    # Implementation for Kubernetes secrets
    secrets_path = "/var/secrets"
    
    @secret_keys
    |> Enum.each(fn key ->
      file_path = Path.join(secrets_path, secret_key_to_filename(key))
      
      if File.exists?(file_path) do
        value = File.read!(file_path) |> String.trim()
        env_var = secret_key_to_env_var(key)
        System.put_env(env_var, value)
      end
    end)
    
    :ok
  end
  
  defp secret_key_to_env_var(key) do
    key
    |> Atom.to_string()
    |> String.upcase()
  end
  
  defp secret_key_to_filename(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", "-")
  end
  
  defp config_env do
    Application.get_env(:ash_dspy, :environment) || Mix.env()
  end
end
```

### CONFIGURATION CACHE

**Configuration Caching System:**
```elixir
defmodule AshDSPy.Config.Cache do
  @moduledoc """
  Caches frequently accessed configuration values for performance.
  """
  
  use GenServer
  
  @cache_ttl 300_000  # 5 minutes
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def get(key, default \\ nil) do
    case GenServer.call(__MODULE__, {:get, key}) do
      {:ok, value} -> value
      :not_found -> 
        value = load_config_value(key, default)
        GenServer.cast(__MODULE__, {:put, key, value})
        value
    end
  end
  
  def put(key, value) do
    GenServer.cast(__MODULE__, {:put, key, value})
  end
  
  def clear do
    GenServer.cast(__MODULE__, :clear)
  end
  
  def warm_up do
    # Pre-load commonly accessed configuration
    common_keys = [
      {:ash_dspy, :adapter},
      {:ash_dspy, :performance},
      {:ash_dspy, :security},
      {:ash_dspy, :wire_protocol}
    ]
    
    Enum.each(common_keys, fn key ->
      get(key)
    end)
  end
  
  @impl true
  def init(_opts) do
    # Create ETS table for configuration cache
    :ets.new(:config_cache, [:named_table, :public, read_concurrency: true])
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    {:ok, %{}}
  end
  
  @impl true
  def handle_call({:get, key}, _from, state) do
    case :ets.lookup(:config_cache, key) do
      [{^key, value, timestamp}] ->
        if fresh?(timestamp) do
          {:reply, {:ok, value}, state}
        else
          :ets.delete(:config_cache, key)
          {:reply, :not_found, state}
        end
      
      [] ->
        {:reply, :not_found, state}
    end
  end
  
  @impl true
  def handle_cast({:put, key, value}, state) do
    timestamp = System.monotonic_time(:millisecond)
    :ets.insert(:config_cache, {key, value, timestamp})
    {:noreply, state}
  end
  
  def handle_cast(:clear, state) do
    :ets.delete_all_objects(:config_cache)
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_entries()
    schedule_cleanup()
    {:noreply, state}
  end
  
  defp load_config_value({app, key}, default) do
    Application.get_env(app, key, default)
  end
  
  defp load_config_value({app, key, subkey}, default) do
    app
    |> Application.get_env(key, [])
    |> Keyword.get(subkey, default)
  end
  
  defp fresh?(timestamp) do
    System.monotonic_time(:millisecond) - timestamp < @cache_ttl
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cache_ttl)
  end
  
  defp cleanup_expired_entries do
    cutoff = System.monotonic_time(:millisecond) - @cache_ttl
    :ets.select_delete(:config_cache, [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
  end
end
```

## IMPLEMENTATION TASK

Based on the complete context above, implement the comprehensive configuration and application setup system with the following specific requirements:

### FILE STRUCTURE TO CREATE:
```
config/
├── config.exs              # Main configuration file
├── dev.exs                 # Development environment
├── prod.exs                # Production environment
├── test.exs                # Test environment
└── runtime.exs             # Runtime configuration

lib/ash_dspy/
├── application.ex          # Main application module
├── config/
│   ├── validator.ex        # Configuration validation
│   ├── environment.ex      # Environment variable management
│   ├── secrets.ex          # Secret management
│   └── cache.ex           # Configuration caching
├── ml/
│   └── supervisor.ex       # ML domain supervisor
└── health/
    └── check.ex           # Health check system

priv/
├── python/
│   └── dspy_bridge.py     # Python bridge script
└── config/
    ├── .env.example       # Environment variable template
    └── docker-compose.yml # Development setup
```

### SPECIFIC IMPLEMENTATION REQUIREMENTS:

1. **Configuration Files (`config/*.exs`)**:
   - Complete environment-specific configurations
   - Proper defaults and environment variable handling
   - Security considerations for each environment
   - Database, Python bridge, and external service configuration

2. **Application Module (`lib/ash_dspy/application.ex`)**:
   - Comprehensive supervision tree setup
   - Configuration validation on startup
   - Environment-specific service initialization
   - Graceful shutdown and cleanup

3. **Configuration Validation (`lib/ash_dspy/config/validator.ex`)**:
   - Runtime configuration validation
   - Adapter-specific requirement checking
   - Database and external service validation
   - Clear error messages and recommendations

4. **Environment Management (`lib/ash_dspy/config/environment.ex`)**:
   - Environment variable loading and validation
   - Type conversion utilities
   - Required vs optional variable handling
   - Environment-specific requirements

5. **Secret Management (`lib/ash_dspy/config/secrets.ex`)**:
   - Multiple secret source support
   - Production-ready secret handling
   - Development environment flexibility
   - Secure secret loading patterns

### QUALITY REQUIREMENTS:

- **Security**: Proper secret management and secure defaults
- **Flexibility**: Easy configuration for different environments
- **Reliability**: Robust validation and error handling
- **Performance**: Efficient configuration caching
- **Maintainability**: Clear configuration structure
- **Documentation**: Well-documented configuration options
- **Deployment**: Production-ready deployment configuration

### INTEGRATION POINTS:

- Must integrate with all system components
- Should support multiple deployment environments
- Must provide secure secret management
- Should enable easy development setup
- Must support monitoring and observability

### SUCCESS CRITERIA:

1. Application starts successfully in all environments
2. Configuration validation catches common errors
3. Environment variables are properly managed
4. Secrets are handled securely in production
5. Development setup is straightforward
6. Production configuration is secure and performant
7. Error messages are clear and actionable
8. Configuration changes don't require code changes
9. Health checks validate system readiness
10. Deployment is reliable and repeatable

This configuration and application setup system provides the foundation for reliable, secure, and maintainable deployment of the DSPy-Ash integration across all environments.