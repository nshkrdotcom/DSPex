# Python Variables API Specification (Revised)

## Overview

This document specifies the Python-side API for the Variables feature within the unified gRPC Bridge. The API provides intuitive access to variables stored in Elixir sessions, with automatic type conversion, caching, real-time updates, optimization coordination, and comprehensive monitoring capabilities.

## Core Classes

### SessionContext Variable Methods

The `SessionContext` class provides all variable-related functionality with enhanced capabilities for optimization, batch operations, and monitoring.

#### Variable Retrieval

```python
async def get_variable(
    self, 
    name: str, 
    default: Any = None,
    bypass_cache: bool = False
) -> Any:
    """
    Retrieves a variable value from the session.
    
    Args:
        name: Variable name or ID to retrieve
        default: Default value if variable not found (None raises KeyError)
        bypass_cache: Force fetch from server, ignoring local cache
    
    Returns:
        The variable value with proper Python type
        
    Raises:
        KeyError: If variable not found and no default provided
        TypeError: If server returns incompatible type
        grpc.RpcError: On communication errors
        
    Examples:
        # Simple retrieval
        temperature = await session.get_variable('temperature')
        
        # With default value
        max_tokens = await session.get_variable('max_tokens', default=256)
        
        # Force server fetch
        current_temp = await session.get_variable('temperature', bypass_cache=True)
        
        # Type-specific returns
        model_name = await session.get_variable('model')  # Returns string
        threshold = await session.get_variable('threshold')  # Returns float
        embedding = await session.get_variable('context_embedding')  # Returns numpy array
    """
    
async def get_variables(
    self, 
    names: List[str], 
    defaults: Optional[Dict[str, Any]] = None,
    include_metadata: bool = False,
    include_stats: bool = False
) -> Dict[str, Any]:
    """
    Retrieves multiple variables in a single efficient call.
    
    Args:
        names: List of variable names to retrieve
        defaults: Optional dict of default values per variable
        include_metadata: Include variable metadata in response
        include_stats: Include access statistics
        
    Returns:
        Dict mapping variable names to values (or full info if metadata requested)
        
    Examples:
        # Get multiple variables
        vars = await session.get_variables(['temperature', 'max_tokens', 'model'])
        
        # With defaults
        vars = await session.get_variables(
            ['temp', 'tokens'],
            defaults={'temp': 0.7, 'tokens': 256}
        )
        
        # With full information
        vars_info = await session.get_variables(
            ['temperature', 'model'],
            include_metadata=True,
            include_stats=True
        )
        # Returns: {
        #     'temperature': {
        #         'value': 0.7,
        #         'metadata': {...},
        #         'stats': {'read_count': 42, 'cache_hits': 38, ...}
        #     },
        #     ...
        # }
    """
```

#### Variable Creation and Updates

```python
async def register_variable(
    self,
    name: str,
    type: str,
    initial_value: Any,
    constraints: Optional[Dict[str, Any]] = None,
    metadata: Optional[Dict[str, str]] = None,
    dependencies: Optional[List[str]] = None,
    access_rules: Optional[List[Dict]] = None
) -> str:
    """
    Creates a new variable with full type specification.
    
    Args:
        name: Variable name
        type: Variable type ('float', 'integer', 'string', 'boolean', 
              'choice', 'module', 'embedding', 'tensor')
        initial_value: Initial value (must match type)
        constraints: Type-specific constraints
        metadata: Additional metadata
        dependencies: List of variable IDs this depends on
        access_rules: Access control rules
        
    Returns:
        Variable ID
        
    Raises:
        ValueError: If type validation fails
        TypeError: If initial_value doesn't match type
        
    Examples:
        # Create temperature variable
        temp_id = await session.register_variable(
            'temperature',
            'float',
            0.7,
            constraints={'min': 0.0, 'max': 2.0}
        )
        
        # Create embedding variable
        embed_id = await session.register_variable(
            'context_embedding',
            'embedding',
            np.zeros(768),
            constraints={'dimensions': 768, 'normalize': True}
        )
        
        # Create with dependencies
        derived_id = await session.register_variable(
            'effective_temperature',
            'float',
            0.7,
            dependencies=[temp_id, style_id]
        )
    """

async def register_variables(
    self,
    variables: List[Dict[str, Any]]
) -> Dict[str, str]:
    """
    Registers multiple variables atomically.
    
    Args:
        variables: List of variable specifications
        
    Returns:
        Dict mapping variable names to IDs
        
    Examples:
        var_ids = await session.register_variables([
            {
                'name': 'temperature',
                'type': 'float',
                'initial_value': 0.7,
                'constraints': {'min': 0.0, 'max': 2.0}
            },
            {
                'name': 'model',
                'type': 'choice',
                'initial_value': 'gpt-4',
                'constraints': {'choices': ['gpt-4', 'claude-3', 'gemini']}
            }
        ])
    """

async def set_variable(
    self,
    name: str,
    value: Any,
    metadata: Optional[Dict[str, str]] = None,
    create_if_missing: bool = False,
    type_hint: Optional[str] = None
) -> None:
    """
    Sets a variable value in the session.
    
    Args:
        name: Variable name or ID
        value: New value (will be type-checked on server)
        metadata: Optional metadata about the update
        create_if_missing: Create variable if it doesn't exist
        type_hint: Type hint for creation (required if create_if_missing)
        
    Raises:
        ValueError: If value fails type validation
        KeyError: If variable not found and create_if_missing is False
        PermissionError: If variable is read-only
        TypeError: If create_if_missing but type inference fails
        
    Examples:
        # Simple update
        await session.set_variable('temperature', 0.9)
        
        # With metadata
        await session.set_variable(
            'temperature',
            0.9,
            metadata={'reason': 'user_preference', 'source': 'ui'}
        )
        
        # Create if missing with type hint
        await session.set_variable(
            'new_config', 
            {'key': 'value'}, 
            create_if_missing=True,
            type_hint='dict'
        )
    """

async def update_variables(
    self,
    updates: Dict[str, Any],
    metadata: Optional[Dict[str, str]] = None,
    atomic: bool = True
) -> Dict[str, Union[bool, str]]:
    """
    Updates multiple variables in a single transaction.
    
    Args:
        updates: Dict mapping variable names to new values
        metadata: Metadata applied to all updates
        atomic: If True, all updates must succeed or all fail
        
    Returns:
        Dict mapping variable names to success (True) or error message
        
    Examples:
        results = await session.update_variables({
            'temperature': 0.8,
            'max_tokens': 512,
            'model': 'gpt-4'
        }, atomic=True)
        
        # Check results
        for var, result in results.items():
            if result is not True:
                print(f"Failed to update {var}: {result}")
    """
```

#### Variable Dependencies

```python
async def add_dependency(
    self,
    from_variable: str,
    to_variable: str,
    dependency_type: str = 'data',
    metadata: Optional[Dict[str, str]] = None
) -> None:
    """
    Adds a dependency between variables.
    
    Args:
        from_variable: Variable that depends on another
        to_variable: Variable being depended upon
        dependency_type: Type of dependency ('data', 'constraint', 'optimization')
        metadata: Additional dependency metadata
        
    Raises:
        ValueError: If would create circular dependency
        KeyError: If variable not found
        
    Examples:
        # Temperature depends on base temperature
        await session.add_dependency(
            'effective_temperature',
            'base_temperature',
            dependency_type='data'
        )
    """

async def remove_dependency(
    self,
    from_variable: str,
    to_variable: str
) -> None:
    """Removes a dependency between variables."""

async def get_dependencies(
    self,
    variable: str,
    include_transitive: bool = False
) -> List[Dict[str, Any]]:
    """
    Gets all variables that this variable depends on.
    
    Args:
        variable: Variable name or ID
        include_transitive: Include indirect dependencies
        
    Returns:
        List of dependency information
        
    Examples:
        deps = await session.get_dependencies('effective_temperature')
        # Returns: [
        #     {'variable_id': 'var_base_temp_123', 'type': 'data'},
        #     {'variable_id': 'var_style_456', 'type': 'constraint'}
        # ]
    """

async def get_dependents(
    self,
    variable: str,
    include_transitive: bool = False
) -> List[Dict[str, Any]]:
    """Gets all variables that depend on this variable."""
```

#### Optimization Integration

```python
async def start_optimization(
    self,
    variable: str,
    optimizer_type: str,
    optimizer_config: Optional[Dict[str, Any]] = None,
    max_iterations: int = 100,
    convergence_threshold: float = 0.001,
    callback: Optional[Callable] = None
) -> str:
    """
    Starts optimization for a variable.
    
    Args:
        variable: Variable name or ID to optimize
        optimizer_type: Type of optimizer ('bayesian', 'grid_search', 'gradient')
        optimizer_config: Optimizer-specific configuration
        max_iterations: Maximum optimization iterations
        convergence_threshold: When to stop optimization
        callback: Optional callback for progress updates
        
    Returns:
        Optimization ID
        
    Raises:
        ValueError: If variable already being optimized
        PermissionError: If no optimize permission
        
    Examples:
        # Start Bayesian optimization
        opt_id = await session.start_optimization(
            'temperature',
            'bayesian',
            optimizer_config={
                'acquisition_function': 'ei',
                'n_initial_points': 5
            },
            max_iterations=50
        )
        
        # With progress callback
        def on_progress(iteration, value, metrics):
            print(f"Iteration {iteration}: {value} -> {metrics}")
            
        opt_id = await session.start_optimization(
            'learning_rate',
            'gradient',
            callback=on_progress
        )
    """

async def stop_optimization(self, variable: str) -> None:
    """
    Stops ongoing optimization for a variable.
    
    Args:
        variable: Variable name or ID
        
    Raises:
        ValueError: If not currently optimizing
    """

async def get_optimization_status(self, variable: str) -> Dict[str, Any]:
    """
    Gets current optimization status.
    
    Returns:
        Dict with optimization status:
        {
            'is_optimizing': bool,
            'optimization_id': str,
            'iteration': int,
            'best_value': Any,
            'best_metrics': Dict[str, float],
            'started_at': datetime,
            'last_update': datetime
        }
    """

async def get_optimization_history(
    self,
    variable: str,
    limit: int = 100,
    since: Optional[datetime] = None,
    optimizer_id: Optional[str] = None
) -> List[Dict[str, Any]]:
    """
    Gets optimization history for a variable.
    
    Args:
        variable: Variable name or ID
        limit: Maximum entries to return
        since: Only entries after this timestamp
        optimizer_id: Filter by specific optimization run
        
    Returns:
        List of optimization history entries
        
    Examples:
        history = await session.get_optimization_history(
            'temperature',
            limit=50
        )
        
        # Plot optimization progress
        iterations = [h['iteration'] for h in history]
        values = [h['value'] for h in history]
        metrics = [h['metrics']['accuracy'] for h in history]
    """

async def register_python_optimizer(
    self,
    name: str,
    optimizer_class: Type['BaseOptimizer']
) -> None:
    """
    Registers a Python-based optimizer.
    
    Args:
        name: Optimizer name for reference
        optimizer_class: Class implementing BaseOptimizer protocol
        
    Examples:
        from my_optimizers import CustomBayesianOptimizer
        
        await session.register_python_optimizer(
            'custom_bayesian',
            CustomBayesianOptimizer
        )
        
        # Now can use in start_optimization
        opt_id = await session.start_optimization(
            'temperature',
            'custom_bayesian'
        )
    """
```

#### Variable Observation (Streaming)

```python
async def watch_variable(
    self,
    name: str,
    include_initial: bool = True,
    filter_fn: Optional[Callable[[Any, Any], bool]] = None,
    throttle_ms: int = 0
) -> AsyncIterator[VariableUpdate]:
    """
    Watches a single variable for changes with filtering.
    
    Args:
        name: Variable name to watch
        include_initial: Emit current value immediately
        filter_fn: Optional filter function (old_value, new_value) -> bool
        throttle_ms: Minimum milliseconds between updates
        
    Yields:
        VariableUpdate objects with:
        - variable_id: str
        - value: Any
        - old_value: Any
        - metadata: Dict[str, str]
        - timestamp: datetime
        - source: str
        
    Examples:
        # Watch with filter for significant changes
        async for update in session.watch_variable(
            'temperature',
            filter_fn=lambda old, new: abs(new - old) > 0.05
        ):
            print(f"Significant change: {update.old_value} -> {update.value}")
            
        # Watch with throttling
        async for update in session.watch_variable(
            'metrics',
            throttle_ms=1000  # Max 1 update per second
        ):
            update_ui(update.value)
    """

async def watch_variables(
    self,
    names: List[str],
    include_initial: bool = True,
    filter_fn: Optional[Callable[[str, Any, Any], bool]] = None,
    throttle_ms: int = 0,
    debounce_ms: int = 0
) -> AsyncIterator[VariableUpdate]:
    """
    Watches multiple variables for changes with advanced options.
    
    Args:
        names: List of variable names to watch
        include_initial: Emit current values immediately
        filter_fn: Filter function (var_name, old_value, new_value) -> bool
        throttle_ms: Minimum ms between updates per variable
        debounce_ms: Wait ms after last change before emitting
        
    Examples:
        # Watch multiple with debouncing
        async for update in session.watch_variables(
            ['query', 'filters', 'sort'],
            debounce_ms=500  # Wait 500ms after changes settle
        ):
            # Rerun search with new parameters
            await perform_search()
    """

def cancel_watch(self, watch_task: asyncio.Task) -> None:
    """
    Cancels a variable watch task.
    
    Args:
        watch_task: The task returned by watch_variable(s)
        
    Examples:
        watch_task = asyncio.create_task(
            session.watch_variable('temperature')
        )
        
        # Later...
        session.cancel_watch(watch_task)
    """
```

#### Access Control

```python
async def set_variable_permissions(
    self,
    variable: str,
    rules: List[Dict[str, Any]]
) -> None:
    """
    Sets access permissions for a variable.
    
    Args:
        variable: Variable name or ID
        rules: List of access rules
        
    Access Rule Structure:
        {
            'session_pattern': str | 'any',
            'permissions': ['read', 'write', 'observe', 'optimize'],
            'conditions': Dict[str, str]
        }
        
    Examples:
        await session.set_variable_permissions(
            'api_key',
            [
                {
                    'session_pattern': 'any',
                    'permissions': ['read']
                },
                {
                    'session_pattern': 'admin_*',
                    'permissions': ['read', 'write', 'optimize']
                }
            ]
        )
    """

async def check_variable_access(
    self,
    variable: str,
    permission: str
) -> bool:
    """
    Checks if current session has specific access to a variable.
    
    Args:
        variable: Variable name or ID
        permission: Permission to check ('read', 'write', 'observe', 'optimize')
        
    Returns:
        True if access granted, False otherwise
    """
```

#### Variable History and Versioning

```python
async def get_variable_history(
    self,
    variable: str,
    limit: int = 100,
    offset: int = 0,
    include_metadata: bool = True
) -> List[Dict[str, Any]]:
    """
    Gets the value history of a variable.
    
    Args:
        variable: Variable name or ID
        limit: Maximum entries to return
        offset: Skip entries for pagination
        include_metadata: Include update metadata
        
    Returns:
        List of history entries:
        [
            {
                'version': 5,
                'value': 0.8,
                'updated_at': datetime(...),
                'updated_by': 'optimizer_123',
                'metadata': {'iteration': 42}
            },
            ...
        ]
    """

async def rollback_variable(
    self,
    variable: str,
    version: int,
    reason: Optional[str] = None
) -> None:
    """
    Rolls back a variable to a previous version.
    
    Args:
        variable: Variable name or ID
        version: Version number to rollback to
        reason: Optional reason for rollback
        
    Raises:
        ValueError: If version not found
        PermissionError: If cannot rollback
        
    Examples:
        # Rollback after failed optimization
        await session.rollback_variable(
            'temperature',
            version=5,
            reason='optimization_diverged'
        )
    """
```

#### Variable Export/Import

```python
async def export_variables(
    self,
    format: str = 'json',
    include_history: bool = False,
    include_dependencies: bool = True,
    filter_pattern: Optional[str] = None
) -> bytes:
    """
    Exports variables and their configuration.
    
    Args:
        format: Export format ('json', 'yaml', 'pickle', 'parquet')
        include_history: Include historical values
        include_dependencies: Include dependency graph
        filter_pattern: Regex pattern to filter variables
        
    Returns:
        Exported data as bytes
        
    Examples:
        # Export all variables as JSON
        export_data = await session.export_variables(
            format='json',
            include_history=True
        )
        
        # Save to file
        with open('variables_backup.json', 'wb') as f:
            f.write(export_data)
        
        # Export only model-related variables
        model_vars = await session.export_variables(
            filter_pattern=r'.*model.*'
        )
    """

async def import_variables(
    self,
    data: bytes,
    format: str = 'json',
    merge_strategy: str = 'replace',
    dry_run: bool = False
) -> Dict[str, Any]:
    """
    Imports variables from exported data.
    
    Args:
        data: Exported variable data
        format: Data format
        merge_strategy: How to handle conflicts ('replace', 'keep', 'merge')
        dry_run: Test import without applying
        
    Returns:
        Import summary:
        {
            'imported': 10,
            'skipped': 2,
            'errors': 0,
            'details': [...]
        }
        
    Examples:
        with open('variables_backup.json', 'rb') as f:
            data = f.read()
            
        # Test import first
        summary = await session.import_variables(
            data,
            dry_run=True
        )
        
        if summary['errors'] == 0:
            # Actually import
            await session.import_variables(data)
    """
```

#### Performance Monitoring

```python
async def get_variable_stats(
    self,
    variable: Optional[str] = None
) -> Dict[str, Any]:
    """
    Gets performance statistics for variables.
    
    Args:
        variable: Specific variable or None for all
        
    Returns:
        Statistics dict:
        {
            'read_count': int,
            'write_count': int,
            'cache_hits': int,
            'cache_misses': int,
            'cache_hit_rate': float,
            'avg_read_latency_ms': float,
            'avg_write_latency_ms': float,
            'total_optimization_time_s': float
        }
        
    Examples:
        # Get stats for specific variable
        stats = await session.get_variable_stats('temperature')
        print(f"Cache hit rate: {stats['cache_hit_rate']:.2%}")
        
        # Get overall stats
        overall = await session.get_variable_stats()
    """

def get_cache_info(self) -> Dict[str, Any]:
    """
    Gets local cache information.
    
    Returns:
        {
            'size': int,
            'ttl': float,
            'hit_rate': float,
            'eviction_count': int
        }
    """

def set_cache_config(
    self,
    ttl: Optional[float] = None,
    max_size: Optional[int] = None,
    eviction_policy: Optional[str] = None
) -> None:
    """
    Configures variable cache settings.
    
    Args:
        ttl: Time-to-live in seconds (0 to disable)
        max_size: Maximum cache entries
        eviction_policy: 'lru', 'lfu', or 'fifo'
        
    Examples:
        # Disable cache for real-time requirements
        session.set_cache_config(ttl=0)
        
        # Configure for large working set
        session.set_cache_config(
            ttl=5.0,
            max_size=10000,
            eviction_policy='lru'
        )
    """
```

### Advanced Caching

```python
class VariableCache:
    """Advanced caching with invalidation subscriptions and batch operations."""
    
    def __init__(self, ttl: float = 1.0, max_size: int = 1000):
        self._cache: Dict[str, CacheEntry] = {}
        self._lru = OrderedDict()
        self._ttl = ttl
        self._max_size = max_size
        self._invalidation_callbacks: Dict[str, List[Callable]] = {}
        self._stats = CacheStats()
        self._lock = asyncio.Lock()
        
    async def get_batch(
        self,
        var_ids: List[str],
        fetch_missing: Callable = None
    ) -> Dict[str, Any]:
        """
        Efficiently fetch multiple variables with single lock.
        
        Args:
            var_ids: Variable IDs to fetch
            fetch_missing: Async function to fetch missing variables
            
        Returns:
            Dict of variable values
        """
        
    def subscribe_invalidation(
        self,
        var_id: str,
        callback: Callable[[str, str], Awaitable[None]]
    ) -> str:
        """
        Subscribe to cache invalidation events.
        
        Args:
            var_id: Variable to monitor
            callback: Async function called on invalidation
            
        Returns:
            Subscription ID for later removal
        """
        
    async def invalidate_pattern(self, pattern: str, reason: str = "") -> int:
        """
        Invalidate all variables matching pattern.
        
        Args:
            pattern: Regex pattern
            reason: Invalidation reason
            
        Returns:
            Number of entries invalidated
        """
```

### DSPy Integration Enhancements

```python
class DSPyOptimizationBridge:
    """Enhanced bridge between DSPex variables and DSPy optimization."""
    
    def __init__(self, session_context: SessionContext):
        self.session_context = session_context
        self._optimization_tasks: Dict[str, asyncio.Task] = {}
        self._registered_optimizers: Dict[str, Type] = {}
        
    async def create_variable_aware_optimizer(
        self,
        optimizer_class: Type,
        variable_mappings: Dict[str, str],
        **kwargs
    ) -> 'VariableAwareOptimizer':
        """
        Create DSPy optimizer that syncs with DSPex variables.
        
        The optimizer will:
        1. Read initial values from variables
        2. Update variables with optimized values
        3. Track optimization history in variables
        
        Examples:
            from dspy.teleprompt import BootstrapFewShot
            
            optimizer = await bridge.create_variable_aware_optimizer(
                BootstrapFewShot,
                variable_mappings={
                    'teacher_temperature': 'temperature',
                    'max_bootstrapped_demos': 'max_demos'
                },
                metric=accuracy_metric
            )
            
            optimized_program = await optimizer.compile(
                student,
                trainset=train_data
            )
        """
        
    async def sync_dspy_parameters(
        self,
        dspy_module: dspy.Module,
        variable_prefix: str = ""
    ) -> Dict[str, str]:
        """
        Automatically sync DSPy module parameters with variables.
        
        Creates variables for all module parameters and returns mappings.
        
        Examples:
            cot = dspy.ChainOfThought("question -> answer")
            mappings = await bridge.sync_dspy_parameters(
                cot,
                variable_prefix="cot_"
            )
            # Creates variables like 'cot_temperature', 'cot_max_tokens'
        """
```

## Usage Examples

### Complete Optimization Workflow

```python
import asyncio
from dspex_bridge import SessionContext

async def optimization_workflow():
    # Initialize session
    channel = grpc.aio.insecure_channel('localhost:50051')
    session = SessionContext('session_123', channel)
    await session.initialize()
    
    # Register variables with dependencies
    temp_id = await session.register_variable(
        'base_temperature',
        'float',
        0.7,
        constraints={'min': 0.0, 'max': 2.0}
    )
    
    style_id = await session.register_variable(
        'style_modifier',
        'float',
        1.0,
        constraints={'min': 0.5, 'max': 1.5}
    )
    
    # Derived variable with dependencies
    effective_id = await session.register_variable(
        'effective_temperature',
        'float',
        0.7,
        dependencies=[temp_id, style_id]
    )
    
    # Start optimization with callback
    def on_progress(iteration, value, metrics):
        print(f"Iteration {iteration}: temp={value:.3f}, accuracy={metrics.get('accuracy', 0):.3f}")
    
    opt_id = await session.start_optimization(
        'base_temperature',
        'bayesian',
        optimizer_config={
            'acquisition_function': 'ei',
            'xi': 0.01
        },
        callback=on_progress
    )
    
    # Monitor optimization
    while True:
        status = await session.get_optimization_status('base_temperature')
        if not status['is_optimizing']:
            break
        await asyncio.sleep(1)
    
    print(f"Optimization complete! Best value: {status['best_value']}")
    
    # Export results
    export_data = await session.export_variables(
        include_history=True,
        filter_pattern=r'.*temperature.*'
    )
    
    with open('optimization_results.json', 'wb') as f:
        f.write(export_data)
```

### Real-Time Adaptive System

```python
async def adaptive_reasoning_system():
    session = SessionContext('adaptive_session', channel)
    await session.initialize()
    
    # Register module-type variable for strategy selection
    await session.register_variable(
        'reasoning_strategy',
        'module',
        'ChainOfThought',
        constraints={
            'choices': ['Predict', 'ChainOfThought', 'ReAct', 'ProgramOfThought']
        }
    )
    
    # Register performance threshold
    await session.register_variable(
        'complexity_threshold',
        'float',
        0.5,
        constraints={'min': 0.0, 'max': 1.0}
    )
    
    # Module resolver
    resolver = ModuleVariableResolver(session)
    
    # Watch for strategy changes
    async def strategy_watcher():
        async for update in session.watch_variable('reasoning_strategy'):
            print(f"Strategy changed to: {update.value}")
            # Recreate module with new strategy
            
    watcher_task = asyncio.create_task(strategy_watcher())
    
    # Adaptive question answering
    async def answer_question(question: str):
        # Assess complexity
        complexity = len(question.split()) / 20.0  # Simple heuristic
        
        # Auto-adjust strategy based on complexity
        threshold = await session.get_variable('complexity_threshold')
        if complexity > threshold:
            await session.set_variable('reasoning_strategy', 'ChainOfThought')
        else:
            await session.set_variable('reasoning_strategy', 'Predict')
        
        # Create module based on current strategy
        qa_module = await resolver.create_module(
            'reasoning_strategy',
            "question -> answer"
        )
        
        # Answer with automatic strategy
        return await qa_module.forward(question=question)
    
    # Test with questions of varying complexity
    simple_q = "What is 2+2?"
    complex_q = "Explain the philosophical implications of consciousness in artificial intelligence systems"
    
    simple_ans = await answer_question(simple_q)
    complex_ans = await answer_question(complex_q)
    
    # Get performance stats
    stats = await session.get_variable_stats()
    print(f"Total variable updates: {stats['write_count']}")
    print(f"Cache hit rate: {stats['cache_hit_rate']:.2%}")
    
    # Cleanup
    watcher_task.cancel()
```

### Batch Processing with Progress Tracking

```python
async def batch_processing_with_variables():
    # Register variables for batch configuration
    batch_vars = await session.register_variables([
        {
            'name': 'batch_size',
            'type': 'integer',
            'initial_value': 32,
            'constraints': {'min': 1, 'max': 256}
        },
        {
            'name': 'processing_temperature',
            'type': 'float',
            'initial_value': 0.7
        },
        {
            'name': 'progress',
            'type': 'float',
            'initial_value': 0.0,
            'constraints': {'min': 0.0, 'max': 100.0}
        }
    ])
    
    # Watch progress from another client
    async def progress_monitor():
        async for update in session.watch_variable(
            'progress',
            throttle_ms=500  # Update at most every 500ms
        ):
            print(f"Progress: {update.value:.1f}%")
    
    monitor_task = asyncio.create_task(progress_monitor())
    
    # Process batches
    total_items = 1000
    batch_size = await session.get_variable('batch_size')
    
    for i in range(0, total_items, batch_size):
        # Get current temperature for this batch
        temp = await session.get_variable('processing_temperature')
        
        # Process batch (simplified)
        batch = items[i:i+batch_size]
        results = await process_batch(batch, temperature=temp)
        
        # Update progress
        progress = (i + len(batch)) / total_items * 100
        await session.set_variable(
            'progress',
            progress,
            metadata={'batch_num': i // batch_size}
        )
    
    monitor_task.cancel()
```

## Error Handling Patterns

```python
# Comprehensive error handling
async def robust_variable_operations():
    try:
        # Attempt to get variable with retries
        for attempt in range(3):
            try:
                value = await session.get_variable('critical_config')
                break
            except grpc.RpcError as e:
                if e.code() == grpc.StatusCode.UNAVAILABLE and attempt < 2:
                    await asyncio.sleep(0.5 * (attempt + 1))  # Exponential backoff
                    continue
                raise
                
    except KeyError:
        # Variable doesn't exist, create with default
        await session.register_variable(
            'critical_config',
            'dict',
            {'default': True}
        )
        value = {'default': True}
    
    except ValueError as e:
        # Type validation failed
        logger.error(f"Variable type mismatch: {e}")
        # Attempt recovery by resetting to known good value
        await session.rollback_variable('critical_config', version=1)
    
    except PermissionError:
        # No access, request elevated permissions
        logger.warning("Insufficient permissions for critical_config")
        # Fallback to read-only mode
        value = await session.get_variable('critical_config_public')

# Handle optimization failures
async def safe_optimization():
    try:
        opt_id = await session.start_optimization(
            'hyperparameter',
            'bayesian'
        )
    except ValueError as e:
        if "already being optimized" in str(e):
            # Wait for current optimization to complete
            status = await session.get_optimization_status('hyperparameter')
            logger.info(f"Waiting for optimization {status['optimization_id']}")
            
            while status['is_optimizing']:
                await asyncio.sleep(1)
                status = await session.get_optimization_status('hyperparameter')
            
            # Retry
            opt_id = await session.start_optimization(
                'hyperparameter',
                'bayesian'
            )
```

## Thread Safety Guarantees

1. **SessionContext is thread-safe**: Can be shared across async tasks
2. **Cache operations are atomic**: Internal locking prevents races
3. **Watch operations are isolated**: Each watcher gets its own stream
4. **Batch operations maintain consistency**: Atomic flag ensures all-or-nothing
5. **Optimization coordination**: Server prevents concurrent optimization

## Performance Best Practices

1. **Use batch operations**: Reduce round trips for multiple variables
2. **Configure cache appropriately**: Balance freshness vs performance
3. **Filter watch events**: Reduce unnecessary updates
4. **Use throttling/debouncing**: Control update frequency
5. **Monitor cache hit rates**: Adjust TTL based on access patterns
6. **Prefer variable names over IDs**: Names are indexed server-side
7. **Clean up watchers**: Always cancel watch tasks when done

## Migration Guide

### From Basic to Advanced Variables

```python
# Before: Simple variable usage
temp = await session.get_variable('temperature')
await session.set_variable('temperature', 0.8)

# After: Full-featured variable usage
# Register with type and constraints
temp_id = await session.register_variable(
    'temperature',
    'float',
    0.7,
    constraints={'min': 0.0, 'max': 2.0},
    metadata={'description': 'LLM generation temperature'}
)

# Add dependencies
await session.add_dependency(
    'effective_temperature',
    'temperature',
    dependency_type='data'
)

# Start optimization
opt_id = await session.start_optimization(
    'temperature',
    'bayesian',
    callback=lambda i, v, m: print(f"Iteration {i}: {v}")
)

# Watch for changes
async for update in session.watch_variable(
    'temperature',
    filter_fn=lambda old, new: abs(new - old) > 0.05
):
    print(f"Temperature changed significantly: {update.value}")

# Export configuration
config = await session.export_variables(
    format='yaml',
    include_history=True
)
```

## Type Conversion Reference

| Elixir Type | Python Type | Notes |
|-------------|-------------|-------|
| `:float` | `float` | Automatic conversion |
| `:integer` | `int` | Preserves precision |
| `:string` | `str` | UTF-8 encoded |
| `:boolean` | `bool` | Direct mapping |
| `:choice` | `str` | Validated against choices |
| `:module` | `str` | Special handling for module references |
| `:list` | `list` | Recursive type conversion |
| `:map` | `dict` | Keys converted to strings |
| `:embedding` | `numpy.ndarray` | Efficient array transfer |
| `:tensor` | `torch.Tensor` or `tf.Tensor` | Framework-specific |