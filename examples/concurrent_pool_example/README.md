# Concurrent Pool Example

This example showcases the advanced capabilities of SessionPoolV2 for managing and executing multiple operations in parallel, demonstrating efficiency and scalability.

## Overview

This advanced demonstration illustrates the practical benefits and usage patterns of the enhanced session pool for handling concurrent workloads. Key features demonstrated include:

1. **Concurrent Execution**: Three distinct operations running in parallel
2. **Session Affinity**: Worker affinity for stateful operations
3. **Pool Management**: Automatic resource management and error handling
4. **Performance Monitoring**: Timing analysis and benchmarking

## Prerequisites

- Elixir 1.18 or later
- Valid Gemini API key
- DSPex with SessionPoolV2 enabled

## Setup

1. **Set your API key**:
   ```bash
   export GEMINI_API_KEY="your-api-key-here"
   ```

2. **Install dependencies**:
   ```bash
   mix deps.get
   ```

## Usage

### CLI Usage (Recommended)

The easiest way to run the examples is using the provided shell script:

```bash
# Run concurrent operations demo
./run_concurrent_example.sh

# Demonstrate session affinity
./run_concurrent_example.sh affinity

# Run performance benchmark
./run_concurrent_example.sh benchmark

# Demonstrate error handling
./run_concurrent_example.sh errors

# Show help
./run_concurrent_example.sh help
```

Or use Mix tasks directly:

```bash
# Run concurrent operations demo
mix run_concurrent

# Demonstrate session affinity
mix run_concurrent affinity

# Run performance benchmark
mix run_concurrent benchmark

# Demonstrate error handling
mix run_concurrent errors
```

### Interactive Usage (IEx)

You can also run the examples interactively:

1. **Start the application**:
   ```bash
   iex -S mix
   ```

2. **Run the comprehensive concurrent operations demonstration**:
   ```elixir
   ConcurrentPoolExample.run_concurrent_operations()
   ```

This will launch three concurrent operations:
- **Text Classification**: Sentiment analysis of sample text
- **Translation**: English to French translation
- **Summarization**: Text summarization with length constraints

Expected output:
```
[info] Starting concurrent pool operations demonstration...
[info] Starting text classification in session classification_1234
[info] Starting translation in session translation_5678
[info] Starting summarization in session summarization_9012
[info] Classification completed in 1234ms
[info] Translation completed in 987ms
[info] Summarization completed in 1567ms
[info] All concurrent operations completed successfully!
```

### Session Affinity Demo

Demonstrate how SessionPoolV2 maintains worker affinity for related operations:

```elixir
ConcurrentPoolExample.demonstrate_session_affinity()
```

This runs multiple operations in the same session, showing how the pool maintains state and context across operations.

### Performance Benchmarking

Compare concurrent vs sequential execution performance:

```elixir
ConcurrentPoolExample.run_performance_benchmark()
```

This measures the performance difference between running operations sequentially vs concurrently, demonstrating the scalability benefits.

### Error Handling Demo

See how the pool handles various error conditions gracefully:

```elixir
ConcurrentPoolExample.demonstrate_error_handling()
```

This intentionally triggers error conditions to show the robust error handling capabilities.

## Key APIs Demonstrated

### SessionPoolV2.execute_in_session/3

Execute operations with session affinity:

```elixir
SessionPoolV2.execute_in_session(session_id, :predict, args)
```

### SessionPoolV2.execute_anonymous/2

Execute operations without session binding:

```elixir
SessionPoolV2.execute_anonymous(:predict, args)
```

## Architecture Benefits

This example demonstrates several key benefits of the SessionPoolV2 implementation:

### 1. Concurrency & Parallelism
- Multiple operations can execute simultaneously
- Efficient use of system resources
- Significantly faster than sequential execution

### 2. Session Affinity
- Related operations use the same worker process
- Maintains context and state across operations
- Reduces initialization overhead for stateful operations

### 3. Resource Management
- Automatic pool sizing and overflow handling
- Worker lifecycle management with health monitoring
- Graceful handling of worker failures

### 4. Error Handling & Recovery
- Circuit breaker patterns for fault tolerance
- Automatic retry logic with backoff strategies
- Comprehensive error classification and reporting

### 5. Performance Monitoring
- Built-in timing and metrics collection
- Performance benchmarking capabilities
- Monitoring of pool health and worker status

## Expected Performance

Typical performance improvements you can expect:

- **2-3x speedup** for I/O bound operations when running concurrently
- **Consistent response times** due to session affinity
- **Improved reliability** through error handling and recovery
- **Better resource utilization** with pool management

## Configuration

The pool can be configured for different workloads:

```elixir
# Enhanced workers with session affinity (default)
config :dspex, DSPex.PythonBridge.SessionPoolV2,
  worker_module: DSPex.PythonBridge.PoolWorkerV2Enhanced,
  pool_size: 4,
  overflow: 2

# Basic workers for simpler workloads
config :dspex, DSPex.PythonBridge.SessionPoolV2,
  worker_module: DSPex.PythonBridge.PoolWorkerV2,
  pool_size: 2,
  overflow: 1
```

## Error Scenarios Handled

The example demonstrates handling of various error conditions:

- **Network timeouts**: Automatic retry with exponential backoff
- **Invalid commands**: Graceful error reporting
- **Worker failures**: Automatic worker replacement
- **Pool exhaustion**: Overflow handling and queuing
- **Circuit breaker activation**: Temporary fault isolation

## Next Steps

After exploring this concurrent example:

1. **Experiment with different pool sizes** to find optimal configuration for your workload
2. **Try different session patterns** to understand when session affinity helps
3. **Monitor the performance metrics** to understand your application's behavior
4. **Implement your own operations** using the SessionPoolV2 patterns shown here

## Related Examples

- [Simple DSPy Example](../simple_dspy_example/) - Basic DSPex workflow
- DSPex Documentation - Complete API reference and guides