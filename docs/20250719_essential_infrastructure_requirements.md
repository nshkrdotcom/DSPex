# Essential Infrastructure Requirements for DSPex V2

## Executive Summary

This document outlines the essential infrastructure components required for a production-ready DSPex V2 deployment. Based on analysis of the cognitive orchestration specifications and architectural requirements, we identify core infrastructure needs, their specific use cases within DSPex, and implementation recommendations.

## Table of Contents

1. [Core Infrastructure Components](#core-infrastructure-components)
2. [Database Infrastructure](#database-infrastructure)
3. [Caching Infrastructure](#caching-infrastructure)
4. [Background Job Processing](#background-job-processing)
5. [Monitoring and Observability](#monitoring-and-observability)
6. [Resilience and Fault Tolerance](#resilience-and-fault-tolerance)
7. [Optional but Recommended Infrastructure](#optional-but-recommended-infrastructure)
8. [Infrastructure Sizing Guidelines](#infrastructure-sizing-guidelines)
9. [Implementation Timeline](#implementation-timeline)
10. [Configuration Examples](#configuration-examples)

## Core Infrastructure Components

### 1. Elixir/OTP Foundation

**Requirements:**
- Elixir 1.15+ 
- OTP 26+
- BEAM VM optimized for multi-core systems

**DSPex-Specific Needs:**
- Actor model for managing Python processes
- Supervision trees for fault tolerance
- Process isolation for concurrent execution
- ETS for in-memory state management

### 2. Python Runtime Environment

**Requirements:**
- Python 3.9+
- DSPy 2.4+
- Virtual environment management
- GPU support (optional but recommended)

**DSPex-Specific Needs:**
- Managed by Snakepit for process pooling
- Separate pools for different workload types:
  - General DSPy operations
  - Optimizer workloads (long-running)
  - Neural model inference

## Database Infrastructure

### PostgreSQL with Ecto

**Why Essential:**
DSPex requires persistent storage for:
- Program definitions and configurations
- Execution history and traces
- Optimization results and learned parameters
- Variable states and dependencies
- Audit trails for compliance

**Recommended Setup:**
```elixir
# config/config.exs
config :dspex, DSPex.Repo,
  username: "dspex",
  password: "secure_password",
  hostname: "localhost",
  database: "dspex_prod",
  pool_size: 20,
  queue_target: 5000,
  queue_interval: 1000,
  migration_primary_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime_usec]
```

**Schema Requirements:**
```sql
-- Core tables needed
CREATE TABLE cognitive_programs (
  id UUID PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  pipeline JSONB NOT NULL,
  variables JSONB DEFAULT '{}',
  optimization_history JSONB DEFAULT '[]',
  status VARCHAR(50) DEFAULT 'draft',
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE cognitive_executions (
  id UUID PRIMARY KEY,
  program_id UUID REFERENCES cognitive_programs(id),
  input JSONB NOT NULL,
  output JSONB,
  trace JSONB DEFAULT '[]',
  metrics JSONB DEFAULT '{}',
  duration_ms INTEGER,
  status VARCHAR(50) DEFAULT 'pending',
  error JSONB,
  created_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE optimization_results (
  id UUID PRIMARY KEY,
  program_id UUID REFERENCES cognitive_programs(id),
  optimizer_type VARCHAR(50) NOT NULL,
  parameters JSONB NOT NULL,
  performance_metrics JSONB NOT NULL,
  training_data_hash VARCHAR(64),
  created_at TIMESTAMPTZ NOT NULL
);

-- Indexes for performance
CREATE INDEX idx_executions_program_status ON cognitive_executions(program_id, status);
CREATE INDEX idx_executions_created_at ON cognitive_executions(created_at DESC);
CREATE INDEX idx_programs_status ON cognitive_programs(status);
```

## Caching Infrastructure

### Cachex (Recommended) or Nebulex

**Why Essential:**
- LLM API calls are expensive ($0.01-0.10 per call)
- Embedding computations are CPU/GPU intensive
- Repeated queries should return instantly
- Session affinity requires state storage

**Cache Layers Required:**

1. **LLM Response Cache**
   ```elixir
   defmodule DSPex.Cache.LLM do
     use Cachex.Spec
     
     def start_link(_) do
       Cachex.start_link(
         name: :llm_cache,
         limit: %{
           size: 10_000,  # Max 10k entries
           memory: 1_073_741_824  # 1GB max memory
         },
         ttl: :timer.hours(24),
         stats: true
       )
     end
   end
   ```

2. **Embedding Cache**
   ```elixir
   defmodule DSPex.Cache.Embeddings do
     use Cachex.Spec
     
     def start_link(_) do
       Cachex.start_link(
         name: :embedding_cache,
         limit: %{size: 50_000},
         ttl: :timer.days(7),
         stats: true,
         warmers: [
           warmer(module: DSPex.Cache.EmbeddingWarmer, state: {})
         ]
       )
     end
   end
   ```

3. **Optimization Results Cache**
   ```elixir
   defmodule DSPex.Cache.Optimizations do
     use Cachex.Spec
     
     def start_link(_) do
       Cachex.start_link(
         name: :optimization_cache,
         ttl: :timer.hours(1),
         fallback: &fetch_from_database/1
       )
     end
   end
   ```

**Cache Key Strategies:**
```elixir
# LLM cache key includes model, temperature, prompt hash
def llm_cache_key(prompt, model, temperature) do
  hash = :crypto.hash(:sha256, prompt) |> Base.encode16()
  "llm:#{model}:#{temperature}:#{hash}"
end

# Embedding cache key based on text content
def embedding_cache_key(text, model) do
  hash = :crypto.hash(:sha256, text) |> Base.encode16()
  "emb:#{model}:#{hash}"
end
```

## Background Job Processing

### Oban

**Why Essential:**
- Optimization runs can take hours
- LLM calls need retry logic
- Resource cleanup must be reliable
- Batch processing improves efficiency

**Required Queues:**

```elixir
# config/config.exs
config :dspex, Oban,
  repo: DSPex.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},  # 7 days
    {Oban.Plugins.Reindexer, schedule: "@daily"},
    {Oban.Plugins.Stager, interval: 5000}
  ],
  queues: [
    default: 10,
    optimization: 2,      # Long-running optimization jobs
    llm_calls: 20,       # Parallel LLM API calls
    embeddings: 5,       # Embedding computations
    cleanup: 3,          # Resource cleanup
    priority: 50         # High-priority user-facing jobs
  ]
```

**Job Examples:**

1. **Optimization Job**
   ```elixir
   defmodule DSPex.Workers.OptimizationWorker do
     use Oban.Worker,
       queue: :optimization,
       max_attempts: 3,
       priority: 1
     
     @impl Oban.Worker
     def perform(%Job{args: %{"program_id" => id, "config" => config}}) do
       with {:ok, program} <- fetch_program(id),
            {:ok, result} <- run_optimization(program, config) do
         store_optimization_result(program, result)
       end
     end
     
     def timeout(_job), do: :timer.hours(4)  # 4-hour timeout
   end
   ```

2. **LLM Retry Job**
   ```elixir
   defmodule DSPex.Workers.LLMCallWorker do
     use Oban.Worker,
       queue: :llm_calls,
       max_attempts: 5,
       backoff: &exponential_backoff/1
     
     def perform(%Job{args: args}) do
       case DSPex.LLM.call(args) do
         {:ok, response} -> 
           cache_response(args, response)
           {:ok, response}
         {:error, :rate_limit} ->
           {:snooze, 60}  # Retry in 60 seconds
         error ->
           error
       end
     end
     
     defp exponential_backoff(attempt) do
       trunc(:math.pow(2, attempt) * 1000)  # 2^n seconds
     end
   end
   ```

## Monitoring and Observability

### Telemetry + OpenTelemetry

**Why Essential:**
- Track performance bottlenecks
- Monitor LLM costs
- Identify optimization opportunities
- Debug production issues

**Telemetry Events:**

```elixir
defmodule DSPex.Telemetry do
  def setup do
    events = [
      # Execution events
      [:dspex, :execution, :start],
      [:dspex, :execution, :stop],
      [:dspex, :execution, :exception],
      
      # Module events
      [:dspex, :module, :execute, :start],
      [:dspex, :module, :execute, :stop],
      
      # LLM events
      [:dspex, :llm, :request, :start],
      [:dspex, :llm, :request, :stop],
      [:dspex, :llm, :tokens],
      
      # Cache events
      [:dspex, :cache, :hit],
      [:dspex, :cache, :miss],
      
      # Python bridge events
      [:dspex, :python, :call, :start],
      [:dspex, :python, :call, :stop],
      [:dspex, :python, :error]
    ]
    
    # Attach handlers
    :telemetry.attach_many(
      "dspex-metrics",
      events,
      &DSPex.Telemetry.Handlers.handle_event/4,
      nil
    )
  end
end
```

**Metrics Configuration:**

```elixir
defmodule DSPex.Telemetry.Metrics do
  use Supervisor
  import Telemetry.Metrics
  
  def metrics do
    [
      # Execution metrics
      counter("dspex.execution.count"),
      summary("dspex.execution.duration",
        unit: {:native, :millisecond},
        tags: [:status]
      ),
      
      # LLM metrics
      counter("dspex.llm.request.count", tags: [:provider, :model]),
      summary("dspex.llm.request.duration", tags: [:provider]),
      sum("dspex.llm.tokens.total", tags: [:provider, :type]),
      
      # Cost tracking
      sum("dspex.llm.cost.usd",
        measurement: &calculate_cost/1,
        tags: [:provider, :model]
      ),
      
      # Cache metrics
      counter("dspex.cache.hit", tags: [:cache_name]),
      counter("dspex.cache.miss", tags: [:cache_name]),
      value("dspex.cache.hit_rate",
        measurement: &calculate_hit_rate/1,
        tags: [:cache_name]
      ),
      
      # Python bridge metrics
      counter("dspex.python.call.count", tags: [:function]),
      summary("dspex.python.call.duration", tags: [:function]),
      counter("dspex.python.error.count", tags: [:error_type])
    ]
  end
end
```

### Phoenix LiveDashboard Integration

```elixir
# router.ex
live_dashboard "/dashboard",
  metrics: DSPex.Telemetry.Metrics,
  additional_pages: [
    llm_costs: DSPex.Dashboard.LLMCostsPage,
    executions: DSPex.Dashboard.ExecutionsPage,
    optimizations: DSPex.Dashboard.OptimizationsPage
  ]
```

## Resilience and Fault Tolerance

### Circuit Breakers (Fuse or custom)

**Why Essential:**
- LLM APIs have rate limits
- Python processes can crash
- Network failures are common
- Prevent cascade failures

**Implementation:**

```elixir
defmodule DSPex.CircuitBreaker do
  use GenServer
  
  @failure_threshold 5
  @reset_timeout :timer.seconds(60)
  
  defstruct [:name, :state, :failures, :last_failure]
  
  def call(name, fun) do
    GenServer.call(name, {:call, fun})
  end
  
  def handle_call({:call, fun}, _from, %{state: :open} = state) do
    if time_to_retry?(state) do
      try_call(fun, %{state | state: :half_open})
    else
      {:reply, {:error, :circuit_open}, state}
    end
  end
  
  def handle_call({:call, fun}, _from, %{state: :closed} = state) do
    try_call(fun, state)
  end
  
  defp try_call(fun, state) do
    case fun.() do
      {:ok, result} ->
        {:reply, {:ok, result}, reset_state(state)}
      {:error, _} = error ->
        new_state = record_failure(state)
        {:reply, error, new_state}
    end
  end
end
```

### Bulkhead Pattern for Resource Isolation

```elixir
defmodule DSPex.Bulkhead do
  def child_spec(opts) do
    %{
      id: opts[:name],
      start: {Task.Supervisor, :start_link, [[name: opts[:name]]]},
      type: :supervisor
    }
  end
  
  def run(bulkhead, fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    max_concurrency = Keyword.get(opts, :max_concurrency, 10)
    
    Task.Supervisor.async_nolink(bulkhead, fun, 
      max_concurrency: max_concurrency
    )
    |> Task.await(timeout)
  end
end
```

## Optional but Recommended Infrastructure

### 1. Broadway for Stream Processing

**Use Cases:**
- High-volume execution requests
- Real-time optimization feedback
- Event-driven architectures

```elixir
defmodule DSPex.Broadway.ExecutionPipeline do
  use Broadway
  
  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwayRabbitMQ.Producer,
          queue: "dspex_executions",
          connection: [host: "localhost"]
        },
        transformer: {__MODULE__, :transform, []},
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: 50,
          max_demand: 10
        ]
      ],
      batchers: [
        llm: [
          concurrency: 5,
          batch_size: 20,
          batch_timeout: 1000
        ]
      ]
    )
  end
end
```

### 2. Sentry for Error Tracking

```elixir
# config/prod.exs
config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: :prod,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  tags: %{
    app: "dspex"
  },
  included_environments: [:prod]
```

### 3. Prometheus + Grafana

```elixir
# Prometheus exporter
defmodule DSPex.PromEx do
  use PromEx, otp_app: :dspex
  
  @impl true
  def plugins do
    [
      PromEx.Plugins.Beam,
      PromEx.Plugins.Phoenix,
      PromEx.Plugins.Ecto,
      PromEx.Plugins.Oban,
      DSPex.PromEx.LLMPlugin,
      DSPex.PromEx.CachePlugin
    ]
  end
  
  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus-default",
      default_selected_interval: "30s"
    ]
  end
end
```

## Infrastructure Sizing Guidelines

### Development Environment
```yaml
resources:
  cpu: 2 cores
  memory: 4GB
  disk: 20GB SSD
  
services:
  postgres: 1 instance (2GB)
  redis: 1 instance (512MB)
  
concurrency:
  python_pools: 2 processes
  oban_queues: 5 workers total
```

### Production Environment (Small - 100 req/min)
```yaml
resources:
  cpu: 8 cores
  memory: 16GB
  disk: 100GB SSD
  
services:
  postgres: 
    instances: 1 primary + 1 replica
    memory: 4GB
    connections: 100
  redis:
    instances: 1
    memory: 2GB
    
concurrency:
  python_pools: 10 processes
  oban_queues: 50 workers total
  
caching:
  llm_cache: 10k entries
  embedding_cache: 50k entries
```

### Production Environment (Large - 1000+ req/min)
```yaml
resources:
  cpu: 32+ cores
  memory: 64GB+
  disk: 500GB SSD
  gpu: Optional (4x NVIDIA T4 for embeddings)
  
services:
  postgres:
    instances: 1 primary + 2 replicas
    memory: 16GB
    connections: 500
    pgbouncer: enabled
  redis:
    instances: Redis Cluster (3 masters, 3 replicas)
    memory: 8GB per instance
    
concurrency:
  python_pools: 50+ processes
  oban_queues: 200+ workers total
  
caching:
  llm_cache: 100k entries
  embedding_cache: 500k entries
  cdn: CloudFront/Fastly for static assets
```

## Implementation Timeline

### Week 1: Database and Core Infrastructure
- [ ] Set up PostgreSQL with Ecto
- [ ] Configure connection pooling
- [ ] Create initial schema migrations
- [ ] Set up development seeds

### Week 2: Caching Layer
- [ ] Implement Cachex for LLM responses
- [ ] Add embedding cache
- [ ] Configure cache warming strategies
- [ ] Add cache metrics

### Week 3: Background Jobs
- [ ] Configure Oban with queues
- [ ] Implement optimization workers
- [ ] Add retry logic for LLM calls
- [ ] Create cleanup jobs

### Week 4: Monitoring and Resilience
- [ ] Set up Telemetry events
- [ ] Configure OpenTelemetry export
- [ ] Implement circuit breakers
- [ ] Add health checks

### Week 5: Production Hardening
- [ ] Load testing and tuning
- [ ] Set up alerting rules
- [ ] Document runbooks
- [ ] Deploy to staging

## Configuration Examples

### Complete Production Configuration

```elixir
# config/prod.exs
import Config

# Database
config :dspex, DSPex.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "20")),
  ssl: true,
  ssl_opts: [
    verify: :verify_peer,
    cacerts: :public_key.cacerts_get(),
    server_name_indication: to_charlist(System.get_env("DB_HOST")),
    customize_hostname_check: [
      match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
    ]
  ]

# Caching
config :dspex, :caches,
  llm: [
    name: :llm_cache,
    adapter: Cachex,
    ttl: :timer.hours(24),
    limit: 10_000,
    stats: true
  ],
  embeddings: [
    name: :embedding_cache,
    adapter: Cachex,
    ttl: :timer.days(7),
    limit: 50_000,
    stats: true
  ]

# Background Jobs
config :dspex, Oban,
  repo: DSPex.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Reindexer, schedule: "@daily"},
    {Oban.Plugins.Stager, interval: 5000},
    {Oban.Plugins.Gossip, interval: 1000}
  ],
  queues: [
    default: 20,
    optimization: 4,
    llm_calls: 50,
    embeddings: 10,
    cleanup: 5,
    priority: 100
  ]

# Monitoring
config :dspex, DSPex.PromEx,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: [
    host: System.get_env("GRAFANA_HOST"),
    auth_token: System.get_env("GRAFANA_TOKEN"),
    upload_dashboards_on_start: true
  ]

# Circuit Breakers
config :dspex, :circuit_breakers,
  llm_api: [
    failure_threshold: 5,
    reset_timeout: 60_000,
    timeout: 30_000
  ],
  python_bridge: [
    failure_threshold: 3,
    reset_timeout: 30_000,
    timeout: 120_000
  ]

# Rate Limiting
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4]},
  pools: %{
    llm_requests: [
      size: 10,
      max_overflow: 5
    ]
  }
```

### Docker Compose for Development

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: dspex
      POSTGRES_PASSWORD: dspex_dev
      POSTGRES_DB: dspex_dev
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dspex"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    ports:
      - "9090:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'

  grafana:
    image: grafana/grafana:latest
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
      GF_USERS_ALLOW_SIGN_UP: false
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - "3001:3000"
    depends_on:
      - prometheus

volumes:
  postgres_data:
  redis_data:
  prometheus_data:
  grafana_data:
```

## Conclusion

These infrastructure components form the foundation of a production-ready DSPex deployment. The combination of PostgreSQL for persistence, Cachex for performance, Oban for reliability, and comprehensive monitoring ensures that DSPex can scale from development to handling thousands of requests per minute while maintaining observability and fault tolerance.

The modular approach allows starting with essential components and gradually adding optional infrastructure as usage grows. Each component is specifically chosen to address the unique challenges of cognitive orchestration: long-running optimizations, expensive LLM calls, complex state management, and the need for absolute reliability in production environments.