    (ex_unit 1.18.3) lib/ex_unit/runner.ex:433: anonymous fn/6 in ExUnit.Runner.spawn_test_monitor/4


  1) test debug pool checkout and communication (PoolV2DebugTest)
     test/pool_v2_debug_test.exs:7
     ** (EXIT from #PID<0.901.0>) an exception was raised:
         ** (RuntimeError) unexpected return from DSPex.PythonBridge.PoolWorkerV2.handle_checkout/4.

     Expected: {:ok, client_state, server_state, pool_state} | {:remove, reason, pool_state} | {:skip, Exception.t(), pool_state}
     Got: {:error, {:invalid_checkout_type, :test}}

             (nimble_pool 1.1.0) lib/nimble_pool.ex:879: NimblePool.maybe_checkout/5
             (nimble_pool 1.1.0) lib/nimble_pool.ex:585: NimblePool.handle_call/3
             (stdlib 6.2.2) gen_server.erl:2381: :gen_server.try_handle_call/4
             (stdlib 6.2.2) gen_server.erl:2410: :gen_server.handle_msg/6
             (stdlib 6.2.2) proc_lib.erl:329: :proc_lib.init_p_do_apply/3


21:16:38.748 [info] DSPy version detected: 2.6.27
21:16:39.876 [info] Python environment validation successful: %{script_path: "/home/home/p/g/n/dspex/_build/test/lib/dspex/priv/python/dspy_bridge.py", dspy_version: "2.6.27", packages: ["dspy-ai"], python_path: "/home/home/.pyenv/shims/python3", python_version: "3.12.10"}

---

21:16:44.885 [error] Timeout! Port info: [name: ~c"/home/home/.pyenv/shims/python3", links: [#PID<0.904.0>], id: 680, connected: #PID<0.904.0>, input: 0, output: 120, os_pid: 1895604]
21:16:44.887 [info] Session pool V2 started with 2 workers, 0 overflow

  2) test direct port communication with Port.command/2 (PortCommunicationTest)
     test/port_communication_test.exs:7
     No response received within 5 seconds
     code: flunk("No response received within 5 seconds")
     stacktrace:
       test/port_communication_test.exs:71: (test)

Pre-warming 2 workers...
Warming worker 1/2...
21:16:44.988 [debug] Initializing pool worker: worker_9090_1752477405638365

---

21:16:55.759 [info] Terminating pool worker worker_9154_1752477411233587, reason: :shutdown
21:16:55.760 [info] Session pool V2 started with 3 workers, 0 overflow

  3) test true concurrent execution with pre-warmed workers (PoolV2ConcurrentTest)
     test/pool_v2_concurrent_test.exs:11
     Assertion with < failed
     code:  assert d < 1000
     left:  5173
     right: 1000
     stacktrace:
       (elixir 1.18.3) lib/enum.ex:987: Enum."-each/2-lists^foreach/1-0-"/2
       test/pool_v2_concurrent_test.exs:78: (test)

Pre-warming 3 workers...
Warming worker 1/3...
21:16:55.861 [debug] Initializing pool worker: worker_9282_1752477416511370

---

21:17:31.577 [debug] Test mode mock_adapter maps to adapter mock
  4) test pool handles blocking operations correctly (PoolV2ConcurrentTest)
     test/pool_v2_concurrent_test.exs:83
     match (=) failed
     code:  assert {:ok, programs} = result
     left:  {:ok, programs}
     right: {:error, "Program ID is required"}
     stacktrace:
       test/pool_v2_concurrent_test.exs:130: anonymous fn/2 in PoolV2ConcurrentTest."test pool handles blocking operations correctly"/1
       (elixir 1.18.3) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
       test/pool_v2_concurrent_test.exs:129: (test)


21:17:31.577 [debug] Adapter resolution:
  Explicit: nil
  Test mode: :mock

---

  Test mode: :mock
  Config: nil
  Resolved: :mock

  5) test single bridge mode health check works in single mode (DSPex.Adapters.ModeCompatibilityTest)
     test/dspex/adapters/mode_compatibility_test.exs:30
     Assertion with == failed
     code:  assert adapter == DSPex.Adapters.PythonPort
     left:  DSPex.Adapters.Mock
     right: DSPex.Adapters.PythonPort
     stacktrace:
       test/dspex/adapters/mode_compatibility_test.exs:25: DSPex.Adapters.ModeCompatibilityTest.__ex_unit_setup_0_0/1
       DSPex.Adapters.ModeCompatibilityTest.__ex_unit_describe_0/1


21:17:31.579 [debug] Test mode mock_adapter maps to adapter mock
21:17:31.579 [debug] Adapter resolution:

---

  Resolved: :mock

  6) test pool mode configuration adapter resolves to PythonPool when pooling enabled (DSPex.Adapters.ModeCompatibilityTest)
     test/dspex/adapters/mode_compatibility_test.exs:67
     Assertion with == failed
     code:  assert adapter == DSPex.Adapters.PythonPool
     left:  DSPex.Adapters.Mock
     right: DSPex.Adapters.PythonPool
     stacktrace:
       test/dspex/adapters/mode_compatibility_test.exs:74: (test)



  7) test adapter behavior consistency configuration determines adapter selection (DSPex.Adapters.ModeCompatibilityTest)

---

       test/dspex/adapters/mode_compatibility_test.exs:74: (test)


  7) test adapter behavior consistency configuration determines adapter selection (DSPex.Adapters.ModeCompatibilityTest)
     test/dspex/adapters/mode_compatibility_test.exs:98
     Assertion with == failed
     code:  assert DSPex.Adapters.Registry.get_adapter() == DSPex.Adapters.PythonPort
     left:  DSPex.Adapters.Mock
     right: DSPex.Adapters.PythonPort
     stacktrace:
       test/dspex/adapters/mode_compatibility_test.exs:101: (test)



  8) test single bridge mode adapter resolves to PythonPort when pooling disabled (DSPex.Adapters.ModeCompatibilityTest)

---

       test/dspex/adapters/mode_compatibility_test.exs:101: (test)


  8) test single bridge mode adapter resolves to PythonPort when pooling disabled (DSPex.Adapters.ModeCompatibilityTest)
     test/dspex/adapters/mode_compatibility_test.exs:41
     Assertion with == failed
     code:  assert adapter == DSPex.Adapters.PythonPort
     left:  DSPex.Adapters.Mock
     right: DSPex.Adapters.PythonPort
     stacktrace:
       test/dspex/adapters/mode_compatibility_test.exs:25: DSPex.Adapters.ModeCompatibilityTest.__ex_unit_setup_0_0/1
       DSPex.Adapters.ModeCompatibilityTest.__ex_unit_describe_0/1

.
21:17:31.585 [debug] Test mode mock_adapter maps to adapter mock
21:17:31.586 [debug] Adapter resolution:

---

  Config: nil
  Resolved: :mock

  9) test single bridge mode can configure LM in single mode (DSPex.Adapters.ModeCompatibilityTest)
     test/dspex/adapters/mode_compatibility_test.exs:46
     Assertion with == failed
     code:  assert adapter == DSPex.Adapters.PythonPort
     left:  DSPex.Adapters.Mock
     right: DSPex.Adapters.PythonPort
     stacktrace:
       test/dspex/adapters/mode_compatibility_test.exs:25: DSPex.Adapters.ModeCompatibilityTest.__ex_unit_setup_0_0/1
       DSPex.Adapters.ModeCompatibilityTest.__ex_unit_describe_0/1

.✅ Found 3 programs in bridge
.Command error: Program not found: nonexistent
Traceback (most recent call last):

---

21:17:36.824 [info] Session pool V2 started with 2 workers, 0 overflow
Pool started without pre-warming (lazy initialization)
21:17:36.935 [info] Session pool V2 started with 2 workers, 0 overflow

 10) test V2 Pool Architecture pool starts successfully with lazy workers (PoolV2Test)
     test/pool_v2_test.exs:45
     ** (FunctionClauseError) no function clause matching in PoolV2Test."test V2 Pool Architecture pool starts successfully with lazy workers"/1

     The following arguments were given to PoolV2Test."test V2 Pool Architecture pool starts successfully with lazy workers"/1:

         # 1
         %{async: false, line: 45, module: PoolV2Test, pid: #PID<0.949.0>, registered: %{}, file: "/home/home/p/g/n/dspex/test/pool_v2_test.exs", test: :"test V2 Pool Architecture pool starts successfully with lazy workers", pool_size: 2, layer_3: true, describe: "V2 Pool Architecture", test_type: :test, genserver_name: :test_pool_9666, pool_name: :test_pool_9666_pool, test_pid: #PID<0.947.0>, describe_line: 44, pool_v2: true}

     code: test "pool starts successfully with lazy workers", %{pool_pid: pool_pid, genserver_name: genserver_name} do
     stacktrace:
       test/pool_v2_test.exs:45: (test)

Pool started without pre-warming (lazy initialization)
21:17:37.043 [info] Session pool V2 started with 2 workers, 0 overflow

---

Pool started without pre-warming (lazy initialization)
21:17:37.043 [info] Session pool V2 started with 2 workers, 0 overflow
21:17:37.044 [info] Session pool V2 started with 2 workers, 0 overflow

 11) test V2 Adapter Integration adapter works with real LM configuration (PoolV2Test)
     test/pool_v2_test.exs:242
     match (=) failed
     code:  assert :ok = adapter.configure_lm.(config)
     left:  :ok
     right: {:error, {:shutdown, {NimblePool, :checkout, [:test_pool_9730]}}}
     stacktrace:
       test/pool_v2_test.exs:253: (test)

Pool started without pre-warming (lazy initialization)
21:17:37.146 [debug] Attempting to checkout from pool: :test_pool_9794_pool

---

21:17:42.149 [warning] Unexpected message during init: {NimblePool, :cancel, #Reference<0.1814790852.290455553.245249>, :timeout}, continuing to wait...
21:17:42.149 [warning] Unexpected message during init: {NimblePool, :cancel, #Reference<0.1814790852.290455569.239993>, :timeout}, continuing to wait...
21:17:42.149 [warning] Unexpected message during init: {:DOWN, #Reference<0.1814790852.290455553.245253>, :process, #PID<0.963.0>, :normal}, continuing to wait...

 12) test V2 Pool Architecture error handling doesn't affect other operations (PoolV2Test)
     test/pool_v2_test.exs:157
     match (=) failed
     code:  assert {:ok, _} = result
     left:  {:ok, _}
     right: {:error, {:pool_timeout, {:timeout, {NimblePool, :checkout, [:test_pool_9794_pool]}}}}
     stacktrace:
       test/pool_v2_test.exs:187: anonymous fn/2 in PoolV2Test."test V2 Pool Architecture error handling doesn't affect other operations"/1
       (elixir 1.18.3) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
       test/pool_v2_test.exs:185: (test)


21:17:42.149 [warning] Unexpected message during init: {NimblePool, :cancel, #Reference<0.1814790852.290455553.245268>, :timeout}, continuing to wait...
21:17:42.149 [warning] Unexpected message during init: {NimblePool, :cancel, #Reference<0.1814790852.290455553.245274>, :timeout}, continuing to wait...

---

Pool started without pre-warming (lazy initialization)
21:17:42.352 [info] Session pool V2 started with 2 workers, 0 overflow
21:17:42.353 [info] Session pool V2 started with 2 workers, 0 overflow

 13) test V2 Adapter Integration health check works (PoolV2Test)
     test/pool_v2_test.exs:260
     match (=) failed
     code:  assert :ok = adapter.health_check.()
     left:  :ok
     right: {:error, {:shutdown, {NimblePool, :checkout, [:test_pool_914]}}}
     stacktrace:
       test/pool_v2_test.exs:262: (test)

Gemini API configured successfully
DSPy Bridge started in pool-worker mode
Worker ID: worker_9858_1752477457146657

---

21:17:57.450 [warning] Unexpected message during init: {:DOWN, #Reference<0.1814790852.290455569.240554>, :process, #PID<0.992.0>, :shutdown}, continuing to wait...
21:17:57.450 [debug] Ignoring EXIT message during init, continuing to wait...
 14) test V2 Pool Architecture pool handles worker death gracefully (PoolV2Test)
     test/pool_v2_test.exs:196
     match (=) failed
     code:  assert {:ok, _} = SessionPoolV2.execute_in_session(session_id, :ping, %{}, pool_name: pool_name)
     left:  {:ok, _}
     right: {:error, {:pool_timeout, {:timeout, {NimblePool, :checkout, [:test_pool_1298_pool]}}}}
     stacktrace:
       test/pool_v2_test.exs:207: (test)


21:17:57.451 [info] Session pool V2 started with 2 workers, 0 overflow
Pool started without pre-warming (lazy initialization)

---

21:17:57.552 [debug] Attempting to checkout from pool: :test_pool_1426
21:17:57.552 [error] Checkout failed: {:shutdown, {NimblePool, :checkout, [:test_pool_1426]}}
21:17:57.552 [info] Session pool V2 started with 2 workers, 0 overflow

 15) test V2 Pool Architecture session isolation works correctly (PoolV2Test)
     test/pool_v2_test.exs:120
     ** (MatchError) no match of right hand side value: {:error, "Checkout failed: {:shutdown, {NimblePool, :checkout, [:test_pool_1426]}}"}
     code: {:ok, program1_id} = adapter1.create_program.(%{
     stacktrace:
       test/pool_v2_test.exs:130: (test)

.............Gemini API configured successfully
DSPy Bridge started in pool-worker mode
Worker ID: worker_1362_1752477473085521

---

21:17:58.563 [warning] Invalid integer value for health_check_interval: bad

 16) test pool works with lazy initialization (PoolFixedTest)
     test/pool_fixed_test.exs:7
     Assertion with != failed, both sides are exactly equal
     code: assert pool_supervisor != nil
     left: nil
     stacktrace:
       test/pool_fixed_test.exs:21: (test)


21:17:58.564 [warning] Invalid non-negative integer value for failure_threshold: xyz
.
21:17:58.564 [warning] Invalid integer value for health_check_interval: bad

---

21:17:58.572 [info] Shutting down session pool gracefully
..
21:17:58.572 [info] Session pool started with 1 workers, 2 overflow

 17) test graceful shutdown shuts down pool gracefully (DSPex.PythonBridge.SessionPoolTest)
     test/dspex/python_bridge/session_pool_test.exs:106
     ** (EXIT from #PID<0.1284.0>) shutdown

.
21:17:58.676 [info] Session pool started with 2 workers, 2 overflow
.
---

  Test mode: :python_port
  Config: nil
  Resolved: :python_pool

 18) test get_adapter/1 respects TEST_MODE environment variable in test env (DSPex.Adapters.RegistryTest)
     test/dspex/adapters/registry_test.exs:54
     Assertion with == failed
     code:  assert Registry.get_adapter() == PythonPort
     left:  DSPex.Adapters.PythonPool
     right: DSPex.Adapters.PythonPort
     stacktrace:
       test/dspex/adapters/registry_test.exs:65: (test)

...*....Command error: Program execution failed: No LM is loaded.
.Traceback (most recent call last):
  File "/home/home/p/g/n/dspex/_build/test/lib/dspex/priv/python/dspy_bridge.py", line 430, in execute_program

---

21:20:02.355 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 19) test layer_3 adapter behavior compliance handles complex signatures (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:129
     ** (MatchError) no match of right hand side value: {:error, "Python bridge not available"}
     code: {:ok, program_id} = adapter.create_program(config)
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:136: (test)


21:20:02.355 [error] Python bridge not running - check supervision configuration
.
21:20:02.355 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

---

21:20:02.355 [error] Python bridge not running - check supervision configuration
 20) test layer_3 adapter behavior compliance lists programs correctly (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:158
     ** (MatchError) no match of right hand side value: {:error, "Python bridge not available"}
     code: for i <- 1..3 do
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:167: anonymous fn/4 in DSPex.Adapters.BehaviorComplianceTest."test layer_3 adapter behavior compliance lists programs correctly"/1
       (elixir 1.18.3) lib/enum.ex:4507: Enum.reduce/3
       test/dspex/adapters/behavior_compliance_test.exs:160: (test)


21:20:02.355 [error] Python bridge not running - check supervision configuration
.
21:20:02.355 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

---

21:20:02.355 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 21) test layer_3 adapter behavior compliance executes programs with valid inputs (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:110
     ** (MatchError) no match of right hand side value: {:error, "Python bridge not available"}
     code: {:ok, _} = adapter.create_program(config)
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:118: (test)


21:20:02.356 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
21:20:02.356 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

---

.
21:20:02.357 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
 22) test Factory pattern compliance creates correct adapters for test layers (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:205
     ** (MatchError) no match of right hand side value: {:error, %DSPex.Adapters.ErrorHandler{type: :unknown, message: "Python bridge not running", context: %{adapter_type: nil, test_layer: :layer_3, resolved_adapter: DSPex.Adapters.PythonPort}, recoverable: false, retry_after: nil, test_layer: :layer_1}}
     code: for {layer, expected_adapter} <- @adapters_by_layer do
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:207: anonymous fn/2 in DSPex.Adapters.BehaviorComplianceTest."test Factory pattern compliance creates correct adapters for test layers"/1
       (stdlib 6.2.2) maps.erl:860: :maps.fold_1/4
       test/dspex/adapters/behavior_compliance_test.exs:206: (test)

.

 23) test layer_3 adapter behavior compliance creates programs successfully (DSPex.Adapters.BehaviorComplianceTest)

---

.

 23) test layer_3 adapter behavior compliance creates programs successfully (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:98
     ** (MatchError) no match of right hand side value: {:error, "Python bridge not available"}
     code: {:ok, program_id} = adapter.create_program(config)
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:105: (test)

..........................................................
Finished in 285.7 seconds (48.6s async, 237.1s sync)
45 doctests, 563 tests, 23 failures, 11 skipped
