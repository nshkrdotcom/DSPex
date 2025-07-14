# DSPex Pooling Configuration

DSPex supports two modes of operation for the Python bridge:

1. **Single Bridge Mode** - One Python process handles all requests
2. **Pool Mode** - Multiple Python processes with session isolation

## Configuration

The mode is determined by the `:pooling_enabled` configuration:

```elixir
# config/config.exs or config/runtime.exs
config :dspex,
  pooling_enabled: false  # or true for pool mode
```

### Single Bridge Mode (Default)

When `pooling_enabled: false`, DSPex uses a single Python process:

- **Adapter**: `DSPex.Adapters.PythonPort`
- **Use Case**: Development, testing, low-traffic deployments
- **Benefits**: Simple, low resource usage
- **Limitations**: No concurrent request handling, shared state

### Pool Mode

When `pooling_enabled: true`, DSPex uses a pool of Python processes:

- **Adapter**: `DSPex.Adapters.PythonPool`
- **Use Case**: Production, high-traffic deployments
- **Benefits**: Concurrent requests, session isolation, fault tolerance
- **Configuration**:
  ```elixir
  config :dspex,
    pooling_enabled: true,
    pool_size: System.schedulers_online() * 2,
    pool_overflow: 2
  ```

## Testing Both Modes

The test suite covers both modes to ensure compatibility:

```bash
# Test with single bridge mode (default)
TEST_MODE=full_integration mix test

# Test with pool mode (when fixed)
TEST_MODE=full_integration POOLING_ENABLED=true mix test
```

## Adapter Selection

The system automatically selects the appropriate adapter based on configuration:

```elixir
# This returns PythonPort or PythonPool based on pooling_enabled
adapter = DSPex.Adapters.Registry.get_adapter()
```

Both adapters implement the same behavior, so code using them doesn't need to change.

## Current Status

- **Single Bridge Mode**: ✅ Fully functional
- **Pool Mode**: ⚠️ Worker initialization bug being fixed

The system defaults to single bridge mode until the pool worker initialization issue is resolved.