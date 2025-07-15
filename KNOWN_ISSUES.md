# DSPex Known Issues

## Critical Issues

### 1. "Session not found: anonymous" Bug 🐛

**Status**: Active Bug  
**Severity**: High  
**First Reported**: 2025-07-15  
**Affects**: All V2 pool operations using anonymous sessions

#### Problem Description

The DSPex V2 pool implementation has a **session affinity routing bug** that causes intermittent failures with the error message:

```
Session not found: anonymous
```

#### Root Cause Analysis

The bug occurs due to incorrect session management in the pool worker architecture:

1. **create_program** is called with no explicit session_id
2. It defaults to `"anonymous"` session (hardcoded in `python_pool_v2.ex:22`)
3. `create_program` gets routed to **Worker A** via session affinity
4. **Worker A** creates the session in its local `session_programs` dictionary
5. Session affinity system binds `"anonymous"` to **Worker A**
6. **execute_program** is called immediately after with the same `"anonymous"` session
7. Due to pool load balancing, `execute_program` gets routed to **Worker B** (different worker!)
8. **Worker B** doesn't have the `"anonymous"` session in its local dictionary
9. **ERROR: "Session not found: anonymous"**

#### Why This is a Real Bug

This is **not** "automatically handled" behavior as might be assumed:

- **Performance Impact**: First requests fail unnecessarily, causing latency
- **User Experience**: Creates confusing error messages in logs
- **Resource Waste**: Retry attempts consume CPU and network resources  
- **Reliability Issues**: Intermittent failures make the system appear unreliable
- **Debugging Confusion**: Makes it hard to distinguish real errors from routing issues

#### Affected Code Locations

1. **Default session assignment**: `/lib/dspex/adapters/python_pool_v2.ex:22`
   ```elixir
   @default_session "anonymous"
   ```

2. **Session creation in Python**: `/priv/python/dspy_bridge.py:343-344`
   ```python
   if session_id not in self.session_programs:
       self.session_programs[session_id] = {}
   ```

3. **Session lookup failure**: `/priv/python/dspy_bridge.py:488-489`
   ```python
   if session_id not in self.session_programs:
       raise ValueError(f"Session not found: {session_id}")
   ```

4. **Session affinity binding**: `/lib/dspex/python_bridge/session_pool_v2.ex:406`
   ```elixir
   SessionAffinity.bind_session(session_id, worker.worker_id)
   ```

#### Current "Workaround" (Masking the Bug)

The retry mechanism currently masks this issue:
- First attempt fails because it hits the wrong worker
- Retry may succeed by chance if routed back to the original worker
- This creates intermittent failures and poor user experience

#### Reproduction Steps

1. Create a program using V2 pool (triggers anonymous session)
2. Execute the program immediately after creation
3. Observe "Session not found: anonymous" error on first attempt
4. Retry succeeds, masking the underlying routing issue

#### Example Error Log

```
Command error: Session not found: anonymous
Traceback (most recent call last):
  File ".../dspy_bridge.py", line 1320, in main
    result = bridge.handle_command(command, args)
  File ".../dspy_bridge.py", line 168, in handle_command
    result = handlers[command](args)
  File ".../dspy_bridge.py", line 489, in execute_program
    raise ValueError(f"Session not found: {session_id}")
ValueError: Session not found: anonymous

[warning] Retry attempt 1/3 failed, retrying in 988ms
[info] Retry succeeded on attempt 2/3
```

#### Proposed Solutions

1. **Fix Session Routing (Recommended)**
   - Anonymous operations should bypass session affinity entirely
   - Or pre-create anonymous sessions on all workers

2. **Eliminate Anonymous Sessions**
   - Generate unique session IDs for all operations
   - Remove the concept of "anonymous" sessions

3. **Improve Session Management**
   - Share session state across workers
   - Or implement proper session-to-worker binding

#### Workaround for Users

For now, users can avoid this issue by:
1. Creating explicit session IDs instead of relying on anonymous sessions
2. Using the simple DSPy example instead of the V2 pool
3. Expecting and handling the retry behavior

#### Impact Assessment

- **Signature Examples**: ✅ Works but with retry noise
- **Concurrent Examples**: ✅ Works but with retry noise  
- **Production Usage**: ⚠️ May cause performance degradation
- **User Experience**: ❌ Confusing error messages

#### Fix Priority

**HIGH** - This should be fixed before any production deployment as it:
- Reduces system reliability
- Creates poor user experience
- Wastes computational resources
- Makes error diagnosis difficult

---

## Other Known Issues

### 2. Logger Deprecation Warnings

**Status**: Minor  
**Severity**: Low  
**Fix**: Replace `Logger.warn` with `Logger.warning`

### 3. Python Bridge Startup Latency

**Status**: Performance Issue  
**Severity**: Medium  
**Description**: Python workers take 2-3 seconds to initialize

---

## Reporting New Issues

Please report issues at: https://github.com/anthropics/dspex/issues

Include:
- Error messages and stack traces
- Reproduction steps
- Environment information
- Expected vs actual behavior