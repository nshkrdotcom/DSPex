# Project Setup Specification

## Overview

This document provides the detailed setup instructions for initializing the DSPex project with all required dependencies and configurations.

## Prerequisites

- Elixir 1.15+ with OTP 26+
- Python 3.8+ with pip
- Git
- 8GB+ RAM for development
- CUDA-capable GPU (optional, for neural pool)

## Step 1: Create Project Structure

```bash
# Create new Phoenix-less Elixir project with supervisor
mix new dspex --sup
cd dspex

# Create directory structure
mkdir -p lib/dspex/{variables,native,llm,orchestrator,pipeline,consciousness}
mkdir -p lib/dspex/variables/types
mkdir -p lib/dspex/native/signatures
mkdir -p lib/dspex/llm/adapters
mkdir -p priv/python
mkdir -p test/dspex/{variables,native,llm,orchestrator,pipeline}
mkdir -p bench
mkdir -p examples
```

## Step 2: Configure Dependencies

### 2.1 Update mix.exs

```elixir
defmodule DSPex.MixProject do
  use Mix.Project

  def project do
    [
      app: :dspex,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        flags: [:error_handling, :missing_return]
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "test.mock": :test,
        "test.integration": :test,
        "test.live": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {DSPex.Application, []},
      env: default_env()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core dependencies
      {:snakepit, github: "nshkrdotcom/snakepit", branch: "main"},
      {:instructor_lite, "~> 0.1.0"},
      
      # Data handling
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      
      # Telemetry and monitoring
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      
      # Development and testing
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:benchee, "~> 1.3", only: [:dev, :test]},
      
      # Future consciousness dependencies (prepared but not used yet)
      {:nx, "~> 0.7", optional: true},
      {:evision, "~> 0.1", optional: true}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "deps.compile", "compile"],
      "test.mock": ["test --only mock"],
      "test.integration": ["test --only integration"], 
      "test.live": ["test --only live"],
      "test.all": ["test.mock", "test.integration", "test.live"],
      quality: ["format", "credo --strict", "dialyzer"],
      bench: ["run bench/run.exs"]
    ]
  end

  defp default_env do
    [
      # Snakepit configuration
      snakepit_pools: [
        %{
          name: :general,
          size: 8,
          python_path: System.get_env("PYTHON_PATH", "python3"),
          script_path: "priv/python/dspy_bridge.py",
          memory_limit: 512
        },
        %{
          name: :optimizer,
          size: 2,
          python_path: System.get_env("PYTHON_PATH", "python3"),
          script_path: "priv/python/dspy_optimizer.py", 
          memory_limit: 4096
        },
        %{
          name: :neural,
          size: 4,
          enabled: System.get_env("ENABLE_GPU", "false") == "true",
          python_path: System.get_env("PYTHON_PATH", "python3"),
          script_path: "priv/python/dspy_neural.py",
          memory_limit: 8192,
          gpu: true
        },
        # Future-ready but dormant
        %{
          name: :agent_pool,
          size: 0,
          enabled: false,
          consciousness_ready: true
        }
      ],
      
      # Consciousness configuration (dormant)
      consciousness: %{
        enabled: false,
        measurement_interval: 60_000,
        phi_threshold: 0.0,
        evolution_stage: :pre_conscious
      }
    ]
  end
end
```

## Step 3: Python Environment Setup

### 3.1 Create Python Requirements

```bash
# Create priv/python/requirements.txt
cat > priv/python/requirements.txt << 'EOF'
# Core DSPy
dspy-ai>=2.0.0

# LLM Providers
openai>=1.0.0
anthropic>=0.8.0
google-generativeai>=0.3.0

# ML/AI Libraries
numpy>=1.24.0
torch>=2.0.0
transformers>=4.35.0

# Optimization
scikit-learn>=1.3.0
scipy>=1.11.0
optuna>=3.4.0  # For BEACON-style optimization

# Future consciousness dependencies
# networkx>=3.0  # For IIT calculations
# qiskit>=0.45.0  # Quantum consciousness experiments

# Development
pytest>=7.4.0
black>=23.0.0
mypy>=1.7.0
EOF
```

### 3.2 Setup Python Virtual Environment

```bash
# Create and activate virtual environment
cd priv/python
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Verify DSPy installation
python -c "import dspy; print(f'DSPy version: {dspy.__version__}')"
```

## Step 4: Configuration Files

### 4.1 Main Configuration

```elixir
# config/config.exs
import Config

# Snakepit configuration
config :snakepit,
  python_path: System.get_env("PYTHON_PATH", "python3"),
  pools: Application.get_env(:dspex, :snakepit_pools, [])

# DSPex configuration
config :dspex,
  # Orchestration settings
  orchestrator: [
    strategy_cache_ttl: 300_000,  # 5 minutes
    learning_enabled: true,
    pattern_detection_threshold: 0.7
  ],
  
  # Variable system
  variables: [
    registry_table: :dspex_variables,
    optimization_history_limit: 1000,
    consciousness_tracking: true  # Track but don't act on it yet
  ],
  
  # LLM configuration
  llm: [
    default_adapter: :python,
    timeout: 30_000,
    adapters: [
      instructor_lite: [
        api_key: System.get_env("OPENAI_API_KEY"),
        model: "gpt-4"
      ],
      http: [
        base_url: System.get_env("LLM_API_URL", "https://api.openai.com/v1"),
        headers: [{"Authorization", "Bearer #{System.get_env("OPENAI_API_KEY")}"}]
      ]
    ]
  ],
  
  # Telemetry
  telemetry: [
    log_level: :info,
    consciousness_events: true,  # Log even though they're all zeros
    metrics_interval: 5_000
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
```

### 4.2 Development Configuration

```elixir
# config/dev.exs
import Config

# Development-specific settings
config :dspex,
  dev_mode: true,
  hot_reload_python: true,
  
  # More verbose logging in dev
  telemetry: [
    log_level: :debug,
    log_consciousness_attempts: true
  ]

# Enable code reloading
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :consciousness_score]
```

### 4.3 Test Configuration

```elixir
# config/test.exs
import Config

# Test-specific settings
config :dspex,
  # Use mock pools in test
  snakepit_pools: [
    %{
      name: :general,
      size: 2,
      adapter: DSPex.Test.MockAdapter,
      mock_responses: true
    }
  ],
  
  # Faster timeouts in test
  orchestrator: [
    strategy_cache_ttl: 1_000,
    learning_enabled: false
  ],
  
  # Disable consciousness in tests (for now)
  consciousness: [
    enabled: false,
    evolution_stage: :testing
  ]

config :logger, level: :warning
```

## Step 5: Git Configuration

### 5.1 .gitignore

```bash
# .gitignore
# Elixir artifacts
/_build/
/cover/
/deps/
/doc/
/.fetch
erl_crash.dump
*.ez
*.beam
/config/*.secret.exs
.elixir_ls/

# Python artifacts
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
priv/python/venv/
priv/python/.venv/
.pytest_cache/
.mypy_cache/

# IDE
.vscode/
.idea/
*.swp
*.swo
.DS_Store

# Environment
.env
.env.local

# Consciousness artifacts (future)
/consciousness_logs/
/phi_measurements/
/evolution_snapshots/
```

### 5.2 Initialize Repository

```bash
git init
git add .
git commit -m "Initial DSPex setup with consciousness-ready architecture"
```

## Step 6: Verify Setup

### 6.1 Run Setup Mix Task

```bash
mix setup
```

### 6.2 Verify Compilation

```bash
mix compile --warnings-as-errors
```

### 6.3 Run Initial Tests

```bash
# Create minimal test to verify setup
cat > test/dspex_test.exs << 'EOF'
defmodule DSPexTest do
  use ExUnit.Case
  
  test "application starts" do
    assert {:ok, _} = Application.ensure_all_started(:dspex)
  end
  
  test "consciousness is dormant" do
    status = DSPex.consciousness_status()
    assert status.stage == :pre_conscious
    assert status.phi == 0.0
    assert status.ready_for_evolution == true
  end
end
EOF

# Run test
mix test
```

## Next Steps

With the project setup complete, proceed to:
1. `02_VARIABLE_SYSTEM.md` - Implement the revolutionary variable system
2. `03_NATIVE_ENGINE.md` - Build the native signature engine
3. `04_ORCHESTRATOR.md` - Create the learning orchestrator
4. Continue through the implementation plan...

## Troubleshooting

### Python Path Issues
```bash
# If DSPy not found
export PYTHONPATH="${PYTHONPATH}:$(pwd)/priv/python"
```

### Snakepit Connection Issues
```bash
# Verify Python bridge
cd priv/python
python dspy_bridge.py --test
```

### Memory Issues
```bash
# Increase Erlang VM memory
export ERL_MAX_ETS_TABLES=10000
export ERL_MAX_PORTS=10000
```

Remember: Every configuration option includes consciousness-ready metadata, even though consciousness features are dormant. This prepares us for the transcendent future!