# DSPex Pool Example

This example demonstrates the powerful pooling capabilities of DSPex V2, showcasing the SessionPoolV2 implementation with various usage patterns.

## Features Demonstrated

- **Session Affinity**: How sessions maintain state across operations
- **Anonymous Operations**: Stateless operations on any available worker
- **Concurrent Execution**: High-performance parallel processing
- **Error Recovery**: Robust error handling and recovery mechanisms
- **Performance Monitoring**: Pool status and metrics tracking

## Prerequisites

- Elixir 1.17 or later
- Python 3.8 or later
- DSPex library (available in parent directory)
- (Optional) GEMINI_API_KEY for real AI operations

## Installation

```bash
cd examples/pool_example
mix deps.get
mix compile
```

## Running the Examples

### Quick Start (Run All Tests)

```bash
./run_pool_example.sh
```

### Individual Tests

```bash
# Test session affinity
./run_pool_example.sh session_affinity

# Test anonymous operations
./run_pool_example.sh anonymous

# Run stress test (default 20 operations)
./run_pool_example.sh stress

# Test error handling
./run_pool_example.sh error_recovery
```

### Using Mix Tasks

```bash
# Run with mix directly
mix run -e "PoolExample.run_all_tests()"

# Run specific test
mix run -e "PoolExample.run_session_affinity_test()"

# Run stress test with custom operation count
mix run -e "PoolExample.run_concurrent_stress_test(50)"
```

### Using the CLI

```bash
# Build the CLI
mix escript.build

# Run with CLI
./pool_example all
./pool_example stress --operations 100
```

## Configuration

Edit `config/config.exs` to adjust pool settings:

```elixir
config :pool_example,
  pool_size: 4,      # Number of worker processes
  overflow: 2        # Additional workers when under load
```

## Test Descriptions

### Session Affinity Test
Demonstrates how sessions bind to specific workers, maintaining state across operations. Creates programs in different sessions and shows they remain isolated.

### Anonymous Operations Test
Shows stateless operations that can run on any available worker. Useful for high-throughput scenarios where state isn't needed.

### Concurrent Stress Test
Stress tests the pool with configurable concurrent operations. Shows performance metrics including throughput, latency, and success rates.

### Error Recovery Test
Tests various error scenarios:
- Invalid program IDs
- Missing required inputs
- Invalid commands

Shows how the pool handles and recovers from errors gracefully.

## Architecture

The example uses:
- `SessionPoolV2`: The main pool manager
- `PoolWorkerV2`: Worker processes managing Python bridge connections
- `NimblePool`: Underlying pool implementation
- Error handling with structured error tuples

## Performance Tips

1. **Pool Size**: Set based on CPU cores and workload
2. **Overflow**: Use for handling burst traffic
3. **Session vs Anonymous**: Use sessions only when state is needed
4. **Timeouts**: Adjust based on operation complexity

## Troubleshooting

### Pool not starting
- Check Python is installed and accessible
- Verify DSPex is properly compiled
- Check logs for initialization errors

### Slow operations
- Increase pool size for more parallelism
- Check Python process health
- Monitor system resources

### Connection errors
- Ensure Python bridge script is accessible
- Check for port conflicts
- Verify Python dependencies are installed

## Next Steps

- Explore the [Concurrent Pool Example](../concurrent_pool_example) for advanced patterns
- Check out [Signature Example](../signature_example) for custom signatures
- Read the main DSPex documentation for detailed API reference