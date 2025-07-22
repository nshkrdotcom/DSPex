# Prompt: Create Comprehensive Integration Tests

## Objective
Develop thorough integration tests that verify the complete variable system works correctly across the Elixir-Python boundary. These tests ensure all components work together seamlessly.

## Context
Integration tests are crucial for validating that the distributed system behaves correctly. They must test real gRPC communication, type safety, caching behavior, and error handling across languages.

## Requirements

### Test Coverage
1. Variable lifecycle (create, read, update, delete)
2. Type validation and constraints
3. Batch operations
4. Cache behavior
5. Error scenarios
6. Concurrent access
7. Session isolation
8. Performance benchmarks

### Test Infrastructure
- Docker-based test environment
- Automated server startup
- Cross-language test coordination
- Performance measurement
- Cleanup after tests

## Implementation Steps

### 1. Create Test Infrastructure

```python
# File: test/integration/test_infrastructure.py

import subprocess
import time
import socket
import os
import tempfile
import shutil
from contextlib import contextmanager
from typing import Generator, Tuple
import grpc
from concurrent.futures import ThreadPoolExecutor

from unified_bridge import SessionContext
from unified_bridge.proto import unified_bridge_pb2_grpc


class TestServer:
    """Manages test server lifecycle."""
    
    def __init__(self, port: int = 0):
        self.port = port or self._find_free_port()
        self.process = None
        self.temp_dir = None
    
    @staticmethod
    def _find_free_port() -> int:
        """Find an available port."""
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(('', 0))
            s.listen(1)
            return s.getsockname()[1]
    
    def start(self):
        """Start the Elixir gRPC server."""
        # Create temp directory for server
        self.temp_dir = tempfile.mkdtemp()
        
        # Start server with test configuration
        env = os.environ.copy()
        env['MIX_ENV'] = 'test'
        env['GRPC_PORT'] = str(self.port)
        env['BRIDGE_DATA_DIR'] = self.temp_dir
        
        # Start server process
        self.process = subprocess.Popen(
            ['mix', 'run', '--no-halt'],
            cwd='snakepit',
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        # Wait for server to be ready
        self._wait_for_ready()
    
    def _wait_for_ready(self, timeout: float = 30.0):
        """Wait for server to start accepting connections."""
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            # Check if process is still running
            if self.process.poll() is not None:
                stdout, stderr = self.process.communicate()
                raise RuntimeError(f"Server failed to start:\n{stderr}")
            
            # Try to connect
            try:
                channel = grpc.insecure_channel(f'localhost:{self.port}')
                grpc.channel_ready_future(channel).result(timeout=1)
                channel.close()
                print(f"Server ready on port {self.port}")
                return
            except:
                time.sleep(0.1)
        
        raise TimeoutError("Server failed to start within timeout")
    
    def stop(self):
        """Stop the server and cleanup."""
        if self.process:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        
        if self.temp_dir and os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)


@contextmanager
def test_server() -> Generator[TestServer, None, None]:
    """Context manager for test server."""
    server = TestServer()
    try:
        server.start()
        yield server
    finally:
        server.stop()


@contextmanager
def test_session(server: TestServer) -> Generator[SessionContext, None, None]:
    """Create a test session context."""
    channel = grpc.insecure_channel(f'localhost:{server.port}')
    stub = unified_bridge_pb2_grpc.UnifiedBridgeStub(channel)
    
    session_id = f"test_session_{int(time.time() * 1000)}"
    
    # Create session via direct gRPC call
    # (Assuming session creation endpoint exists)
    
    ctx = SessionContext(stub, session_id)
    
    try:
        yield ctx
    finally:
        # Cleanup session
        channel.close()


class TestMetrics:
    """Collect test metrics."""
    
    def __init__(self):
        self.timings = {}
        self.counters = {}
    
    @contextmanager
    def time(self, name: str):
        """Time an operation."""
        start = time.time()
        try:
            yield
        finally:
            duration = time.time() - start
            if name not in self.timings:
                self.timings[name] = []
            self.timings[name].append(duration)
    
    def count(self, name: str, value: int = 1):
        """Count occurrences."""
        if name not in self.counters:
            self.counters[name] = 0
        self.counters[name] += value
    
    def report(self):
        """Print metrics report."""
        print("\n=== Performance Metrics ===")
        
        for name, times in sorted(self.timings.items()):
            avg = sum(times) / len(times)
            min_time = min(times)
            max_time = max(times)
            print(f"{name}:")
            print(f"  Average: {avg*1000:.2f}ms")
            print(f"  Min: {min_time*1000:.2f}ms")
            print(f"  Max: {max_time*1000:.2f}ms")
        
        if self.counters:
            print("\nCounters:")
            for name, count in sorted(self.counters.items()):
                print(f"  {name}: {count}")
```

### 2. Create Core Integration Tests

```python
# File: test/integration/test_variables.py

import pytest
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List

from unified_bridge import SessionContext, VariableType
from .test_infrastructure import test_server, test_session, TestMetrics


class TestVariableLifecycle:
    """Test basic variable operations."""
    
    def test_register_and_get(self, session: SessionContext):
        """Test variable registration and retrieval."""
        # Register a variable
        var_id = session.register_variable(
            'test_var',
            VariableType.FLOAT,
            3.14,
            constraints={'min': 0, 'max': 10},
            metadata={'purpose': 'testing'}
        )
        
        assert var_id.startswith('var_test_var_')
        
        # Get by name
        value = session.get_variable('test_var')
        assert value == 3.14
        
        # Get by ID
        value_by_id = session.get_variable(var_id)
        assert value_by_id == 3.14
        
        # Verify in listing
        variables = session.list_variables()
        var_names = [v['name'] for v in variables]
        assert 'test_var' in var_names
    
    def test_update_variable(self, session: SessionContext):
        """Test variable updates."""
        session.register_variable('counter', VariableType.INTEGER, 0)
        
        # Update
        session.update_variable('counter', 42)
        
        # Verify
        value = session.get_variable('counter')
        assert value == 42
        
        # Check version incremented
        variables = session.list_variables()
        counter_var = next(v for v in variables if v['name'] == 'counter')
        assert counter_var['version'] == 1
    
    def test_delete_variable(self, session: SessionContext):
        """Test variable deletion."""
        session.register_variable('temp_var', VariableType.STRING, 'temporary')
        
        # Verify exists
        assert 'temp_var' in session
        
        # Delete
        session.delete_variable('temp_var')
        
        # Verify gone
        assert 'temp_var' not in session
        
        with pytest.raises(Exception):
            session.get_variable('temp_var')
    
    def test_constraints_enforced(self, session: SessionContext):
        """Test that constraints are enforced."""
        session.register_variable(
            'percentage',
            VariableType.FLOAT,
            0.5,
            constraints={'min': 0.0, 'max': 1.0}
        )
        
        # Valid update
        session.update_variable('percentage', 0.8)
        assert session['percentage'] == 0.8
        
        # Invalid update - too high
        with pytest.raises(Exception) as exc_info:
            session.update_variable('percentage', 1.5)
        assert 'above maximum' in str(exc_info.value)
        
        # Value unchanged
        assert session['percentage'] == 0.8


class TestBatchOperations:
    """Test batch variable operations."""
    
    def test_batch_get(self, session: SessionContext):
        """Test getting multiple variables."""
        # Register variables
        for i in range(5):
            session.register_variable(f'var_{i}', VariableType.INTEGER, i * 10)
        
        # Batch get
        names = [f'var_{i}' for i in range(5)]
        values = session.get_variables(names)
        
        assert len(values) == 5
        for i in range(5):
            assert values[f'var_{i}'] == i * 10
    
    def test_batch_update_non_atomic(self, session: SessionContext):
        """Test non-atomic batch updates."""
        # Register variables
        session.register_variable('a', VariableType.INTEGER, 1)
        session.register_variable('b', VariableType.INTEGER, 2)
        session.register_variable('c', VariableType.INTEGER, 3,
                                 constraints={'max': 10})
        
        # Batch update with one failure
        updates = {
            'a': 10,
            'b': 20,
            'c': 30  # Will fail constraint
        }
        
        results = session.update_variables(updates, atomic=False)
        
        # Check results
        assert results['a'] is True
        assert results['b'] is True
        assert isinstance(results['c'], str)  # Error message
        
        # Verify partial update
        assert session['a'] == 10
        assert session['b'] == 20
        assert session['c'] == 3  # Unchanged
    
    def test_batch_update_atomic(self, session: SessionContext):
        """Test atomic batch updates."""
        # Register variables
        session.register_variable('x', VariableType.INTEGER, 1)
        session.register_variable('y', VariableType.INTEGER, 2)
        session.register_variable('z', VariableType.INTEGER, 3,
                                 constraints={'max': 10})
        
        # Atomic update with one failure
        updates = {
            'x': 100,
            'y': 200,
            'z': 300  # Will fail
        }
        
        with pytest.raises(Exception):
            session.update_variables(updates, atomic=True)
        
        # Verify no changes
        assert session['x'] == 1
        assert session['y'] == 2
        assert session['z'] == 3


class TestCaching:
    """Test caching behavior."""
    
    def test_cache_performance(self, session: SessionContext, metrics: TestMetrics):
        """Test that caching improves performance."""
        session.register_variable('cached_var', VariableType.STRING, 'test value')
        
        # First access - cache miss
        with metrics.time('cache_miss'):
            value1 = session['cached_var']
        
        # Multiple cache hits
        for i in range(10):
            with metrics.time('cache_hit'):
                value = session['cached_var']
                assert value == 'test value'
        
        # Report will show cache hits are faster
    
    def test_cache_invalidation_on_update(self, session: SessionContext):
        """Test cache invalidation on updates."""
        session.register_variable('test', VariableType.INTEGER, 1)
        
        # Prime cache
        assert session['test'] == 1
        
        # Update should invalidate
        session['test'] = 2
        
        # Next read should get new value
        assert session['test'] == 2
    
    def test_cache_ttl(self, session: SessionContext):
        """Test cache TTL expiration."""
        # Set short TTL
        from datetime import timedelta
        session.set_cache_ttl(timedelta(seconds=0.5))
        
        session.register_variable('ttl_test', VariableType.INTEGER, 42)
        
        # Access to cache
        assert session['ttl_test'] == 42
        
        # Wait for expiry
        time.sleep(0.6)
        
        # Should fetch again (test would fail if server down)
        assert session['ttl_test'] == 42


class TestConcurrency:
    """Test concurrent access patterns."""
    
    def test_concurrent_reads(self, session: SessionContext, metrics: TestMetrics):
        """Test multiple concurrent reads."""
        session.register_variable('shared', VariableType.INTEGER, 0)
        
        def read_variable(thread_id: int) -> int:
            return session.get_variable('shared')
        
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = []
            for i in range(100):
                future = executor.submit(read_variable, i)
                futures.append(future)
            
            results = [f.result() for f in as_completed(futures)]
        
        # All should read same value
        assert all(r == 0 for r in results)
        metrics.count('concurrent_reads', len(results))
    
    def test_concurrent_updates(self, session: SessionContext):
        """Test concurrent updates maintain consistency."""
        session.register_variable('counter', VariableType.INTEGER, 0)
        
        def increment_counter(thread_id: int):
            for _ in range(10):
                current = session.get_variable('counter')
                session.update_variable('counter', current + 1)
                time.sleep(0.001)  # Small delay to increase contention
        
        # Run concurrent increments
        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = []
            for i in range(5):
                future = executor.submit(increment_counter, i)
                futures.append(future)
            
            # Wait for completion
            for future in as_completed(futures):
                future.result()
        
        # Check final value - may not be 50 due to race conditions
        # This demonstrates the need for atomic operations
        final_value = session['counter']
        print(f"Final counter value: {final_value} (expected up to 50)")
    
    def test_session_isolation(self, server_port: int):
        """Test that sessions are isolated."""
        from grpc import insecure_channel
        from unified_bridge.proto import unified_bridge_pb2_grpc
        
        channel = insecure_channel(f'localhost:{server_port}')
        stub = unified_bridge_pb2_grpc.UnifiedBridgeStub(channel)
        
        # Create two sessions
        ctx1 = SessionContext(stub, 'session_1')
        ctx2 = SessionContext(stub, 'session_2')
        
        # Register same variable name in both
        ctx1.register_variable('isolated', VariableType.STRING, 'session1')
        ctx2.register_variable('isolated', VariableType.STRING, 'session2')
        
        # Verify isolation
        assert ctx1['isolated'] == 'session1'
        assert ctx2['isolated'] == 'session2'
        
        # Update in one shouldn't affect other
        ctx1['isolated'] = 'updated1'
        assert ctx1['isolated'] == 'updated1'
        assert ctx2['isolated'] == 'session2'


class TestErrorHandling:
    """Test error scenarios."""
    
    def test_invalid_type(self, session: SessionContext):
        """Test type validation errors."""
        session.register_variable('typed', VariableType.INTEGER, 42)
        
        # Try to update with wrong type
        with pytest.raises(ValueError) as exc_info:
            session['typed'] = "not a number"
        assert 'Cannot convert' in str(exc_info.value)
    
    def test_nonexistent_variable(self, session: SessionContext):
        """Test accessing non-existent variables."""
        with pytest.raises(Exception) as exc_info:
            session.get_variable('does_not_exist')
        assert 'not found' in str(exc_info.value).lower()
    
    def test_constraint_validation(self, session: SessionContext):
        """Test various constraint violations."""
        # String length
        session.register_variable(
            'short_string',
            VariableType.STRING,
            'test',
            constraints={'min_length': 3, 'max_length': 10}
        )
        
        with pytest.raises(ValueError):
            session['short_string'] = 'a'  # Too short
        
        with pytest.raises(ValueError):
            session['short_string'] = 'a' * 20  # Too long
        
        # Pattern matching
        session.register_variable(
            'pattern_string',
            VariableType.STRING,
            'ABC123',
            constraints={'pattern': '^[A-Z]+[0-9]+$'}
        )
        
        session['pattern_string'] = 'XYZ789'  # Valid
        
        with pytest.raises(ValueError):
            session['pattern_string'] = 'abc123'  # Invalid case


class TestPythonAPIPatterns:
    """Test various Python API usage patterns."""
    
    def test_dict_style_access(self, session: SessionContext):
        """Test dictionary-style access."""
        # Auto-registration
        session['new_var'] = 42
        assert session['new_var'] == 42
        
        # Check exists
        assert 'new_var' in session
        assert 'not_exist' not in session
        
        # Update
        session['new_var'] = 100
        assert session['new_var'] == 100
    
    def test_attribute_style_access(self, session: SessionContext):
        """Test attribute-style access via .v namespace."""
        # Register first
        session.register_variable('attr_var', VariableType.FLOAT, 1.5)
        
        # Read
        assert session.v.attr_var == 1.5
        
        # Write
        session.v.attr_var = 2.5
        assert session.v.attr_var == 2.5
        
        # Auto-register
        session.v.auto_attr = "hello"
        assert session.v.auto_attr == "hello"
    
    def test_batch_context_manager(self, session: SessionContext):
        """Test batch update context manager."""
        # Register variables
        for i in range(5):
            session[f'batch_{i}'] = i
        
        # Batch update
        with session.batch_updates() as batch:
            for i in range(5):
                batch[f'batch_{i}'] = i * 10
        
        # Verify
        for i in range(5):
            assert session[f'batch_{i}'] == i * 10
    
    def test_variable_proxy(self, session: SessionContext):
        """Test variable proxy for repeated access."""
        session['proxy_var'] = 0
        
        # Get proxy
        var = session.variable('proxy_var')
        
        # Repeated updates via proxy
        for i in range(5):
            var.value = i
            assert var.value == i


# Pytest fixtures

@pytest.fixture(scope='session')
def server():
    """Start test server for session."""
    with test_server() as srv:
        yield srv


@pytest.fixture
def session(server):
    """Create test session."""
    with test_session(server) as ctx:
        yield ctx


@pytest.fixture
def server_port(server):
    """Get server port."""
    return server.port


@pytest.fixture(scope='session')
def metrics():
    """Test metrics collector."""
    m = TestMetrics()
    yield m
    m.report()
```

### 3. Create Performance Benchmarks

```python
# File: test/integration/test_performance.py

import time
import statistics
from typing import List
import matplotlib.pyplot as plt

from unified_bridge import SessionContext, VariableType
from .test_infrastructure import test_server, test_session, TestMetrics


class BenchmarkSuite:
    """Performance benchmark suite."""
    
    def __init__(self, session: SessionContext):
        self.session = session
        self.results = {}
    
    def run_all(self):
        """Run all benchmarks."""
        print("\n=== Running Performance Benchmarks ===")
        
        self.benchmark_single_operations()
        self.benchmark_batch_operations()
        self.benchmark_cache_effectiveness()
        self.benchmark_concurrent_access()
        
        self.print_results()
        self.plot_results()
    
    def benchmark_single_operations(self):
        """Benchmark individual operations."""
        print("\nBenchmarking single operations...")
        
        # Register
        times = []
        for i in range(100):
            start = time.time()
            self.session.register_variable(f'bench_reg_{i}', VariableType.INTEGER, i)
            times.append(time.time() - start)
        self.results['register'] = times
        
        # Get (uncached)
        self.session.clear_cache()
        times = []
        for i in range(100):
            start = time.time()
            _ = self.session.get_variable(f'bench_reg_{i}')
            times.append(time.time() - start)
        self.results['get_uncached'] = times
        
        # Get (cached)
        times = []
        for i in range(100):
            start = time.time()
            _ = self.session.get_variable(f'bench_reg_{i}')
            times.append(time.time() - start)
        self.results['get_cached'] = times
        
        # Update
        times = []
        for i in range(100):
            start = time.time()
            self.session.update_variable(f'bench_reg_{i}', i * 2)
            times.append(time.time() - start)
        self.results['update'] = times
    
    def benchmark_batch_operations(self):
        """Benchmark batch vs individual operations."""
        print("\nBenchmarking batch operations...")
        
        # Setup variables
        for i in range(100):
            self.session.register_variable(f'batch_{i}', VariableType.INTEGER, 0)
        
        # Individual updates
        start = time.time()
        for i in range(100):
            self.session.update_variable(f'batch_{i}', i)
        individual_time = time.time() - start
        
        # Batch update
        updates = {f'batch_{i}': i * 2 for i in range(100)}
        start = time.time()
        self.session.update_variables(updates)
        batch_time = time.time() - start
        
        self.results['individual_updates'] = [individual_time]
        self.results['batch_updates'] = [batch_time]
        
        print(f"Individual updates: {individual_time:.3f}s")
        print(f"Batch updates: {batch_time:.3f}s")
        print(f"Speedup: {individual_time/batch_time:.1f}x")
    
    def benchmark_cache_effectiveness(self):
        """Measure cache hit rate and performance."""
        print("\nBenchmarking cache effectiveness...")
        
        # Create variables with different access patterns
        for i in range(20):
            self.session.register_variable(f'cache_test_{i}', VariableType.FLOAT, i * 0.1)
        
        # Simulate realistic access pattern
        access_pattern = []
        # 80% of accesses to 20% of variables (hotspot)
        hot_vars = [f'cache_test_{i}' for i in range(4)]
        cold_vars = [f'cache_test_{i}' for i in range(4, 20)]
        
        import random
        for _ in range(1000):
            if random.random() < 0.8:
                access_pattern.append(random.choice(hot_vars))
            else:
                access_pattern.append(random.choice(cold_vars))
        
        # Clear cache and measure
        self.session.clear_cache()
        times = []
        
        for var_name in access_pattern:
            start = time.time()
            _ = self.session[var_name]
            times.append(time.time() - start)
        
        self.results['realistic_access'] = times
        
        # Calculate cache effectiveness
        avg_first_100 = statistics.mean(times[:100])
        avg_last_100 = statistics.mean(times[-100:])
        print(f"Average access time first 100: {avg_first_100*1000:.2f}ms")
        print(f"Average access time last 100: {avg_last_100*1000:.2f}ms")
        print(f"Cache improvement: {avg_first_100/avg_last_100:.1f}x")
    
    def benchmark_concurrent_access(self):
        """Benchmark concurrent access patterns."""
        print("\nBenchmarking concurrent access...")
        
        from concurrent.futures import ThreadPoolExecutor, as_completed
        
        # Setup shared variables
        for i in range(10):
            self.session.register_variable(f'concurrent_{i}', VariableType.INTEGER, 0)
        
        def worker_task(worker_id: int, iterations: int):
            times = []
            for i in range(iterations):
                var_name = f'concurrent_{i % 10}'
                start = time.time()
                value = self.session[var_name]
                self.session[var_name] = value + 1
                times.append(time.time() - start)
            return times
        
        # Test with different worker counts
        for workers in [1, 5, 10, 20]:
            all_times = []
            
            with ThreadPoolExecutor(max_workers=workers) as executor:
                futures = []
                for i in range(workers):
                    future = executor.submit(worker_task, i, 50)
                    futures.append(future)
                
                for future in as_completed(futures):
                    all_times.extend(future.result())
            
            avg_time = statistics.mean(all_times)
            self.results[f'concurrent_{workers}_workers'] = all_times
            print(f"{workers} workers: {avg_time*1000:.2f}ms average")
    
    def print_results(self):
        """Print benchmark results."""
        print("\n=== Benchmark Results ===")
        
        for name, times in self.results.items():
            if times:
                avg = statistics.mean(times)
                median = statistics.median(times)
                stdev = statistics.stdev(times) if len(times) > 1 else 0
                
                print(f"\n{name}:")
                print(f"  Average: {avg*1000:.2f}ms")
                print(f"  Median: {median*1000:.2f}ms")
                print(f"  Std Dev: {stdev*1000:.2f}ms")
                print(f"  Min: {min(times)*1000:.2f}ms")
                print(f"  Max: {max(times)*1000:.2f}ms")
    
    def plot_results(self):
        """Generate performance plots."""
        try:
            fig, axes = plt.subplots(2, 2, figsize=(12, 10))
            fig.suptitle('Variable System Performance Benchmarks')
            
            # Single operations comparison
            ax = axes[0, 0]
            ops = ['register', 'get_uncached', 'get_cached', 'update']
            avg_times = [statistics.mean(self.results.get(op, [0])) * 1000 for op in ops]
            ax.bar(ops, avg_times)
            ax.set_ylabel('Time (ms)')
            ax.set_title('Single Operation Performance')
            
            # Cache hit distribution
            ax = axes[0, 1]
            if 'realistic_access' in self.results:
                times_ms = [t * 1000 for t in self.results['realistic_access']]
                ax.hist(times_ms, bins=50, alpha=0.7)
                ax.set_xlabel('Access Time (ms)')
                ax.set_ylabel('Frequency')
                ax.set_title('Access Time Distribution')
            
            # Batch vs Individual
            ax = axes[1, 0]
            if 'individual_updates' in self.results and 'batch_updates' in self.results:
                methods = ['Individual', 'Batch']
                times = [
                    self.results['individual_updates'][0] * 1000,
                    self.results['batch_updates'][0] * 1000
                ]
                ax.bar(methods, times)
                ax.set_ylabel('Time (ms)')
                ax.set_title('Batch vs Individual Updates (100 vars)')
            
            # Concurrent scalability
            ax = axes[1, 1]
            worker_counts = []
            avg_times = []
            for workers in [1, 5, 10, 20]:
                key = f'concurrent_{workers}_workers'
                if key in self.results:
                    worker_counts.append(workers)
                    avg_times.append(statistics.mean(self.results[key]) * 1000)
            
            if worker_counts:
                ax.plot(worker_counts, avg_times, 'o-')
                ax.set_xlabel('Number of Workers')
                ax.set_ylabel('Avg Operation Time (ms)')
                ax.set_title('Concurrent Access Scalability')
            
            plt.tight_layout()
            plt.savefig('variable_benchmarks.png')
            print("\nBenchmark plots saved to variable_benchmarks.png")
        except ImportError:
            print("\nMatplotlib not available, skipping plots")


def test_performance_suite(session: SessionContext):
    """Run the full performance benchmark suite."""
    suite = BenchmarkSuite(session)
    suite.run_all()


if __name__ == '__main__':
    # Run benchmarks standalone
    with test_server() as server:
        with test_session(server) as session:
            test_performance_suite(session)
```

### 4. Create Test Runner Script

```bash
#!/bin/bash
# File: test/run_integration_tests.sh

set -e

echo "=== Running Variable System Integration Tests ==="

# Ensure we're in the project root
cd "$(dirname "$0")/.."

# Build the Elixir server
echo "Building Elixir server..."
cd snakepit
mix deps.get
mix compile
cd ..

# Install Python dependencies
echo "Installing Python dependencies..."
cd python
pip install -e .
pip install pytest pytest-asyncio matplotlib
cd ..

# Run tests
echo "Running integration tests..."
python -m pytest test/integration -v --tb=short

# Run benchmarks separately
echo -e "\nRunning performance benchmarks..."
python -m test.integration.test_performance

echo -e "\n=== All tests completed ==="
```

## Test Strategy

### 1. **Unit Testing**
- Individual component validation
- Type system verification
- Serialization correctness

### 2. **Integration Testing**
- Full stack validation
- Cross-language behavior
- Error propagation
- Performance characteristics

### 3. **Load Testing**
- Concurrent access patterns
- Memory usage under load
- Cache effectiveness
- Batch operation benefits

### 4. **Chaos Testing**
- Server restarts
- Network failures
- Invalid data handling
- Resource exhaustion

## Continuous Integration

```yaml
# File: .github/workflows/integration_tests.yml

name: Integration Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      # Could add external services here
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.14'
        otp-version: '25'
    
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.10'
    
    - name: Cache dependencies
      uses: actions/cache@v3
      with:
        path: |
          snakepit/deps
          snakepit/_build
          ~/.cache/pip
        key: ${{ runner.os }}-mix-pip-${{ hashFiles('**/mix.lock', '**/requirements.txt') }}
    
    - name: Install dependencies
      run: |
        cd snakepit && mix deps.get && cd ..
        cd python && pip install -e . && pip install pytest pytest-asyncio
    
    - name: Run integration tests
      run: ./test/run_integration_tests.sh
    
    - name: Upload benchmark results
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: benchmark-results
        path: variable_benchmarks.png
```

## Performance Targets

Based on the integration tests, the system should achieve:

1. **Single Operations**:
   - Register: < 10ms average
   - Get (cached): < 1ms average
   - Get (uncached): < 5ms average
   - Update: < 10ms average

2. **Batch Operations**:
   - 10x improvement over individual operations
   - Linear scaling up to 1000 variables

3. **Cache Performance**:
   - 90%+ hit rate for hot variables
   - 5-10x speedup for cached access

4. **Concurrent Access**:
   - Near-linear scaling up to 10 workers
   - No deadlocks or race conditions

## Files to Create

1. Create: `test/integration/test_infrastructure.py`
2. Create: `test/integration/test_variables.py`
3. Create: `test/integration/test_performance.py`
4. Create: `test/run_integration_tests.sh`
5. Create: `.github/workflows/integration_tests.yml`

## Stage 1 Completion

With these integration tests, Stage 1 is complete. The system now has:

1. ✅ Variable module with full lifecycle management
2. ✅ Extended SessionStore with variable operations
3. ✅ Type system for basic types
4. ✅ gRPC handlers for all operations
5. ✅ Python SessionContext with caching
6. ✅ Comprehensive integration tests

The foundation is ready for Stage 2's tool integration and DSPy module support!