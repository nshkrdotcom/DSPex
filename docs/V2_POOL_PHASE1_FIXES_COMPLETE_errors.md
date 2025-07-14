
08:12:02.918 [debug] Initializing pool worker: worker_3282_1752516726354825

  1) test pool handles blocking operations correctly (PoolV2ConcurrentTest)
     test/pool_v2_concurrent_test.exs:93
     Expected truthy, got false
     code: assert is_list(programs)
     arguments:

         # 1
         %{
           "programs" => [
             %{
               "created_at" => 1752516722.9173944,
               "execution_count" => 0,
               "id" => "test_program_1_2962",
               "last_executed" => nil,
               "session_id" => "blocking_test_1",
               "signature" => %{"inputs" => [%{"name" => "input", "type" => "string"}], "outputs" => [%{"name" => "output", "type" => "string"}]}
             }
           ],
           "total_count" => 1
         }

     stacktrace:
       test/pool_v2_concurrent_test.exs:155: anonymous fn/2 in PoolV2ConcurrentTest."test pool handles blocking operations correctly"/1
       (elixir 1.18.3) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
       test/pool_v2_concurrent_test.exs:153: (test)
PoolFixedTest [test/pool_fixed_test.exs]
  * test pool works with lazy initialization (1000.9ms) [L#7]

  2) test pool works with lazy initialization (PoolFixedTest)
     test/pool_fixed_test.exs:7
     Assertion with != failed, both sides are exactly equal
     code: assert pool_supervisor != nil
     left: nil
     stacktrace:
       test/pool_fixed_test.exs:21: (test)


08:13:29.956 [info] Session pool started with 3 workers, 2 overflow
  3) test graceful shutdown shuts down pool gracefully (DSPex.PythonBridge.SessionPoolTest)
     test/dspex/python_bridge/session_pool_test.exs:106
     ** (EXIT from #PID<0.1102.0>) shutdown

  * test pool status and metrics tracks session metrics (0.09ms) [L#70]
  * test health check functionality performs health check [L#95]



  4) test test layer specific behavior layer_3 uses long timeouts and more retries (DSPex.Adapters.FactoryTest)
     test/dspex/adapters/factory_test.exs:330
     ** (MatchError) no match of right hand side value: {:error, %DSPex.Adapters.ErrorHandler{type: :unexpected, message: "Unexpected error: \"Python bridge not available\"", context: %{adapter: DSPex.Adapters.PythonPort, operation: :health_check, test_layer: :layer_3}, recoverable: false, retry_after: nil, test_layer: :layer_3}}
     code: {:ok, _} = Factory.execute_with_adapter(PythonPort, :health_check, [])
     stacktrace:
       test/dspex/adapters/factory_test.exs:334: (test)

  * test adapter lifecycle management execute_with_fallback provides fallback logic (0.1ms) [L#281]
  * test execute_with_adapter/4 uses test layer specific retry counts (0.1ms) [L#164]
  * test execute_with_signature_validation/4 validates inputs against signature (0.08ms) [L#175]
  * test execute_with_signature_validation/4 applies test layer specific validation (0.08ms) [L#225]
  * test create_adapter/2 checks adapter requirements (0.04ms) [L#88]
  * test execute_with_adapter/4 respects test layer specific timeouts (0.06ms) [L#131]
  * test create_adapter/2 returns error for invalid adapter (0.07ms) [L#93]
  * test adapter requirements checking bridge mock requirements checked for layer_2 (0.2ms) [L#372]
  * test signature validation integration validates field types (0.1ms) [L#407]
  * test create_adapter/2 creates bridge mock adapter for layer_2 (0.06ms) [L#64]
  * test signature validation integration converts inputs for different adapters (0.9ms) [L#424]
  * test test layer specific behavior layer_1 uses fast timeouts and no retries (0.1ms) [L#311]
  * test error handling integration provides retry logic for recoverable errors (0.2ms) [L#347]
  * test legacy create_adapter_legacy/1 starts required services (0.07ms) [L#260]
  * test adapter lifecycle management create_adapter_suite creates multiple adapters (0.04ms) [L#295]
  * test adapter lifecycle management handles adapter suite creation failures gracefully (0.1ms) [L#302]
  * test create_adapter/2 validates adapter compatibility with test layer (0.07ms) [L#80]
  * test legacy create_adapter_legacy/1 works with legacy options format (0.04ms) [L#247]
  * test create_adapter/2 creates python port adapter for layer_3 (0.04ms) [L#70]

  5) test create_adapter/2 creates python port adapter for layer_3 (DSPex.Adapters.FactoryTest)
     test/dspex/adapters/factory_test.exs:70
     ** (MatchError) no match of right hand side value: {:error, %DSPex.Adapters.ErrorHandler{type: :unknown, message: "Python bridge not running", context: %{adapter_type: nil, test_layer: :layer_3, resolved_adapter: DSPex.Adapters.PythonPort}, recoverable: false, retry_after: nil, test_layer: :layer_1}}
     code: {:ok, adapter} = Factory.create_adapter(nil, test_layer: :layer_3)
     stacktrace:
       test/dspex/adapters/factory_test.exs:71: (test)

  * test execute_with_adapter/4 applies retry logic for recoverable errors (0.08ms) [L#149]


08:13:53.832 [debug] Initializing pool worker: worker_4557_1752516835569260

  6) test V2 Adapter Integration health check works (PoolV2Test)
     test/pool_v2_test.exs:289
     match (=) failed
     code:  assert :ok = adapter.health_check.()
     left:  :ok
     right: {:error, {:shutdown, {NimblePool, :checkout, [:isolated_test_pool_1166_1230]}}}
     stacktrace:
       test/pool_v2_test.exs:291: (test)



  7) test V2 Adapter Integration adapter works with real LM configuration (PoolV2Test)
     test/pool_v2_test.exs:271
     match (=) failed
     code:  assert :ok = adapter.configure_lm.(config)
     left:  :ok
     right: {:error, {:shutdown, {NimblePool, :checkout, [:isolated_test_pool_4749_4813]}}}
     stacktrace:
       test/pool_v2_test.exs:282: (test)


08:15:11.406 [debug] Initializing pool worker: worker_2126_1752516911406556

  8) test V2 Pool Architecture session isolation works correctly (PoolV2Test)
     test/pool_v2_test.exs:139
     ** (MatchError) no match of right hand side value: {:error, "Checkout failed: {:shutdown, {NimblePool, :checkout, [:isolated_test_pool_5901_5965]}}"}
     code: {:ok, program1_id} =
     stacktrace:
       test/pool_v2_test.exs:149: (test)





==== START -- CLAUDE: ANALYZE THIS ONE SEPARATELY BC WHY ARE THERE NO TEST ERRORS? ====

08:15:20.699 [debug] Worker worker_2254_1752516917014366 checkin with type: :ok
No more messages, exiting
DSPy Bridge shutting down

08:15:20.699 [error] [worker_2254_1752516917014366] Failed to connect port to PID #PID<0.1436.0> (alive? true): :badarg
Command error: Unknown command: invalid_command
Traceback (most recent call last):
  File "/home/home/p/g/n/dspex/_build/test/lib/dspex/priv/python/dspy_bridge.py", line 1156, in main
    result = bridge.handle_command(command, args)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/home/p/g/n/dspex/_build/test/lib/dspex/priv/python/dspy_bridge.py", line 161, in handle_command
    raise ValueError(f"Unknown command: {command}")
ValueError: Unknown command: invalid_command

No more messages, exiting
DSPy Bridge shutting down

08:15:20.700 [error] GenServer :isolated_test_pool_1998_2062_pool terminating
** (RuntimeError) unexpected return from DSPex.PythonBridge.PoolWorkerV2.handle_checkout/4.

Expected: {:ok, client_state, server_state, pool_state} | {:remove, reason, pool_state} | {:skip, Exception.t(), pool_state}
Got: {:error, :badarg}

    (nimble_pool 1.1.0) lib/nimble_pool.ex:879: NimblePool.maybe_checkout/5
    (nimble_pool 1.1.0) lib/nimble_pool.ex:640: NimblePool.handle_info/2
    (stdlib 6.2.2) gen_server.erl:2345: :gen_server.try_handle_info/3
    (stdlib 6.2.2) gen_server.erl:2433: :gen_server.handle_msg/6
    (stdlib 6.2.2) proc_lib.erl:329: :proc_lib.init_p_do_apply/3
Last message: {NimblePool, :checkin, #Reference<0.310708657.4150263821.68806>, :ok}
State: %{async: %{}, monitors: %{#Reference<0.310708657.4150263820.72534> => #Reference<0.310708657.4150263821.68824>, #Reference<0.310708657.4150263820.72535> => #Reference<0.310708657.4150263821.68825>, #Reference<0.310708657.4150263820.72538> => #Reference<0.310708657.4150263821.68830>, #Reference<0.310708657.4150263821.68805> => #Reference<0.310708657.4150263821.68801>, #Reference<0.310708657.4150263821.68812> => #Reference<0.310708657.4150263821.68806>, #Reference<0.310708657.4150263821.68833> => #Reference<0.310708657.4150263821.68831>}, state: [], queue: {[{#PID<0.1439.0>, #Reference<0.310708657.4150263821.68831>}, {#PID<0.1437.0>, #Reference<0.310708657.4150263821.68830>}, {#PID<0.1438.0>, #Reference<0.310708657.4150263821.68825>}], [{#PID<0.1436.0>, #Reference<0.310708657.4150263821.68824>}]}, requests: %{#Reference<0.310708657.4150263821.68801> => {#PID<0.1434.0>, #Reference<0.310708657.4150263821.68805>, :state, %DSPex.PythonBridge.PoolWorkerV2{port: #Port<0.237>, python_path: "/home/home/.pyenv/shims/python3", script_path: "/home/home/p/g/n/dspex/_build/test/lib/dspex/priv/python/dspy_bridge.py", worker_id: "worker_2126_1752516911406556", current_session: "error_test_1", stats: %{uptime_ms: 0, last_activity: -576460428975, checkouts: 1, error_checkins: 0, successful_checkins: 0}, health_status: :healthy, started_at: -576460428975}}, #Reference<0.310708657.4150263821.68806> => {#PID<0.1435.0>, #Reference<0.310708657.4150263821.68812>, :state, %DSPex.PythonBridge.PoolWorkerV2{port: #Port<0.241>, python_path: "/home/home/.pyenv/shims/python3", script_path: "/home/home/p/g/n/dspex/_build/test/lib/dspex/priv/python/dspy_bridge.py", worker_id: "worker_2254_1752516917014366", current_session: "error_test_2", stats: %{uptime_ms: 0, last_activity: -576460423608, checkouts: 1, error_checkins: 0, successful_checkins: 0}, health_status: :healthy, started_at: -576460423608}}, #Reference<0.310708657.4150263821.68824> => {#PID<0.1436.0>, #Reference<0.310708657.4150263820.72534>, :command, {:session, "error_test_3"}, -576460416761339877}, #Reference<0.310708657.4150263821.68825> => {#PID<0.1438.0>, #Reference<0.310708657.4150263820.72535>, :command, {:session, "error_test_5"}, -576460416760878415}, #Reference<0.310708657.4150263821.68830> => {#PID<0.1437.0>, #Reference<0.310708657.4150263820.72538>, :command, {:session, "error_test_4"}, -576460416760808216}, #Reference<0.310708657.4150263821.68831> => {#PID<0.1439.0>, #Reference<0.310708657.4150263821.68833>, :command, {:session, "error_test_6"}, -576460416760690034}}, worker: DSPex.PythonBridge.PoolWorkerV2, lazy: nil, resources: {[], []}, worker_idle_timeout: nil, max_idle_pings: -1}

08:15:20.710 [error] Checkout failed: {{%RuntimeError{message: "unexpected return from DSPex.PythonBridge.PoolWorkerV2.handle_checkout/4.\n\nExpected: {:ok, client_state, server_state, pool_state} | {:remove, reason, pool_state} | {:skip, Exception.t(), pool_state}\nGot: {:error, :badarg}\n"}, [{NimblePool, :maybe_checkout, 5, [file: ~c"lib/nimble_pool.ex", line: 879, error_info: %{module: Exception}]}, {NimblePool, :handle_info, 2, [file: ~c"lib/nimble_pool.ex", line: 640]}, {:gen_server, :try_handle_info, 3, [file: ~c"gen_server.erl", line: 2345]}, {:gen_server, :handle_msg, 6, [file: ~c"gen_server.erl", line: 2433]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 329]}]}, {NimblePool, :checkout, [:isolated_test_pool_1998_2062_pool]}}
Task 1 failed as expected

08:15:20.710 [error] Checkout failed: {{%RuntimeError{message: "unexpected return from DSPex.PythonBridge.PoolWorkerV2.handle_checkout/4.\n\nExpected: {:ok, client_state, server_state, pool_state} | {:remove, reason, pool_state} | {:skip, Exception.t(), pool_state}\nGot: {:error, :badarg}\n"}, [{NimblePool, :maybe_checkout, 5, [file: ~c"lib/nimble_pool.ex", line: 879, error_info: %{module: Exception}]}, {NimblePool, :handle_info, 2, [file: ~c"lib/nimble_pool.ex", line: 640]}, {:gen_server, :try_handle_info, 3, [file: ~c"gen_server.erl", line: 2345]}, {:gen_server, :handle_msg, 6, [file: ~c"gen_server.erl", line: 2433]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 329]}]}, {NimblePool, :checkout, [:isolated_test_pool_1998_2062_pool]}}
Task 2 succeeded as expected

08:15:20.710 [error] Checkout failed: {{%RuntimeError{message: "unexpected return from DSPex.PythonBridge.PoolWorkerV2.handle_checkout/4.\n\nExpected: {:ok, client_state, server_state, pool_state} | {:remove, reason, pool_state} | {:skip, Exception.t(), pool_state}\nGot: {:error, :badarg}\n"}, [{NimblePool, :maybe_checkout, 5, [file: ~c"lib/nimble_pool.ex", line: 879, error_info: %{module: Exception}]}, {NimblePool, :handle_info, 2, [file: ~c"lib/nimble_pool.ex", line: 640]}, {:gen_server, :try_handle_info, 3, [file: ~c"gen_server.erl", line: 2345]}, {:gen_server, :handle_msg, 6, [file: ~c"gen_server.erl", line: 2433]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 329]}]}, {NimblePool, :checkout, [:isolated_test_pool_1998_2062_pool]}}
Task 3 failed as expected

08:15:20.710 [debug] Initializing pool worker: worker_2318_1752516922445242

08:15:20.710 [error] Checkout failed: {{%RuntimeError{message: "unexpected return from DSPex.PythonBridge.PoolWorkerV2.handle_checkout/4.\n\nExpected: {:ok, client_state, server_state, pool_state} | {:remove, reason, pool_state} | {:skip, Exception.t(), pool_state}\nGot: {:error, :badarg}\n"}, [{NimblePool, :maybe_checkout, 5, [file: ~c"lib/nimble_pool.ex", line: 879, error_info: %{module: Exception}]}, {NimblePool, :handle_info, 2, [file: ~c"lib/nimble_pool.ex", line: 640]}, {:gen_server, :try_handle_info, 3, [file: ~c"gen_server.erl", line: 2345]}, {:gen_server, :handle_msg, 6, [file: ~c"gen_server.erl", line: 2433]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 329]}]}, {NimblePool, :checkout, [:isolated_test_pool_1998_2062_pool]}}

08:15:22.615 [info] DSPy version detected: 2.6.27


==== END -- CLAUDE: ANALYZE THIS ONE SEPARATELY BC WHY ARE THERE NO TEST ERRORS? ====



  9) test V2 Pool Architecture error handling doesn't affect other operations (PoolV2Test)
     test/pool_v2_test.exs:178
     match (=) failed
     code:  assert {:ok, _} = result
     left:  {:ok, _}
     right: {
              :error,
              {:checkout_failed, {{%RuntimeError{message: "unexpected return from DSPex.PythonBridge.PoolWorkerV2.handle_checkout/4.\n\nExpected: {:ok, client_state, server_state, pool_state} | {:remove, reason, pool_state} | {:skip, Exception.t(), pool_state}\nGot: {:error, :badarg}\n"}, [{NimblePool, :maybe_checkout, 5, [file: ~c"lib/nimble_pool.ex", line: 879, error_info: %{module: Exception}]}, {NimblePool, :handle_info, 2, [file: ~c"lib/nimble_pool.ex", line: 640]}, {:gen_server, :try_handle_info, 3, [file: ~c"gen_server.erl", line: 2345]}, {:gen_server, :handle_msg, 6, [file: ~c"gen_server.erl", line: 2433]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 329]}]}, {NimblePool, :checkout, [:isolated_test_pool_1998_2062_pool]}}}
            }
     stacktrace:
       test/pool_v2_test.exs:214: anonymous fn/2 in PoolV2Test."test V2 Pool Architecture error handling doesn't affect other operations"/1
       (elixir 1.18.3) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
       test/pool_v2_test.exs:212: (test)


08:16:38.923 [info] Starting Python bridge supervisor with config: %{name: :test_supervisor_6989, max_restarts: 5, max_seconds: 60, bridge_restart: :permanent, monitor_restart: :permanent, bridge_name: :test_bridge_6989, monitor_name: :test_monitor_6989}

 10) test complete bridge system bridge system starts and reports healthy status (DSPex.PythonBridge.IntegrationTest)
     test/dspex/python_bridge/integration_test.exs:21
     Assertion with == failed
     code:  assert bridge_status.status == :running
     left:  :not_running
     right: :running
     stacktrace:
       test/dspex/python_bridge/integration_test.exs:36: (test)

08:16:47.930 [debug] Test mode full_integration maps to adapter python_port

08:16:47.930 [debug] Adapter resolution:
  Explicit: nil
  Test mode: :python_port
  Config: nil
  Resolved: :python_pool


 11) test get_adapter/1 respects TEST_MODE environment variable in test env (DSPex.Adapters.RegistryTest)
     test/dspex/adapters/registry_test.exs:54
     Assertion with == failed
     code:  assert Registry.get_adapter() == PythonPort
     left:  DSPex.Adapters.PythonPoolV2
     right: DSPex.Adapters.PythonPort
     stacktrace:
       test/dspex/adapters/registry_test.exs:65: (test)



08:16:47.947 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 12) test layer_3 adapter behavior compliance creates programs successfully (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:98
     ** (MatchError) no match of right hand side value: {:error, "Python bridge not available"}
     code: {:ok, program_id} = adapter.create_program(config)
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:105: (test)


08:16:47.947 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
  * test layer_1 adapter behavior compliance supports health check [L#175]
08:16:47.947 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
  * test layer_1 adapter behavior compliance supports health check (0.03ms) [L#175]

08:16:47.947 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
  * test layer_2 adapter behavior compliance handles complex signatures (0.03ms) [L#129]

08:16:47.947 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
  * test layer_1 adapter behavior compliance provides test capabilities [L#186]
08:16:47.947 [error] Python bridge not running - check supervision configuration
  * test layer_1 adapter behavior compliance provides test capabilities (0.02ms) [L#186]
  * test Error handling compliance formats errors with test context [L#296]
08:16:47.947 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
  * test Error handling compliance formats errors with test context (0.06ms) [L#296]
  * test layer_1 adapter behavior compliance executes programs with valid inputs (0.1ms) [L#110]
  * test Factory pattern compliance handles execution with retry logic [L#216]
08:16:47.947 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
  * test Factory pattern compliance handles execution with retry logic (0.1ms) [L#216]
  * test Type conversion compliance converts signatures to different formats (0.05ms) [L#263]

08:16:47.947 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
  * test layer_3 adapter behavior compliance lists programs correctly (0.05ms) [L#158]

08:16:47.947 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

08:16:47.947 [error] Python bridge not running - check supervision configuration

08:16:47.947 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}


08:16:47.947 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 13) test layer_3 adapter behavior compliance lists programs correctly (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:158
     ** (MatchError) no match of right hand side value: {:error, "Python bridge not available"}
     code: for i <- 1..3 do
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:167: anonymous fn/4 in DSPex.Adapters.BehaviorComplianceTest."test layer_3 adapter behavior compliance lists programs correctly"/1
       (elixir 1.18.3) lib/enum.ex:4507: Enum.reduce/3
       test/dspex/adapters/behavior_compliance_test.exs:160: (test)

  * test Factory pattern compliance creates correct adapters for test layers (0.03ms) [L#205]

08:16:47.948 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

08:16:47.948 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

08:16:47.948 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

08:16:47.948 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}


08:16:47.948 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 14) test Factory pattern compliance creates correct adapters for test layers (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:205
     ** (MatchError) no match of right hand side value: {:error, %DSPex.Adapters.ErrorHandler{type: :unknown, message: "Python bridge not running", context: %{adapter_type: nil, test_layer: :layer_3, resolved_adapter: DSPex.Adapters.PythonPort}, recoverable: false, retry_after: nil, test_layer: :layer_1}}
     code: for {layer, expected_adapter} <- @adapters_by_layer do
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:207: anonymous fn/2 in DSPex.Adapters.BehaviorComplianceTest."test Factory pattern compliance creates correct adapters for test layers"/1
       (stdlib 6.2.2) maps.erl:860: :maps.fold_1/4
       test/dspex/adapters/behavior_compliance_test.exs:206: (test)


08:16:47.948 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
  * test Factory pattern compliance validates adapter requirements [L#212]
08:16:47.948 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
  * test Factory pattern compliance validates adapter requirements (0.05ms) [L#212]
  * test layer_1 adapter behavior compliance lists programs correctly (0.08ms) [L#158]
  * test layer_3 adapter behavior compliance executes programs with valid inputs [L#110]
08:16:47.948 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
  * test layer_3 adapter behavior compliance executes programs with valid inputs (0.05ms) [L#110]


08:16:47.948 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 15) test layer_3 adapter behavior compliance executes programs with valid inputs (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:110
     ** (MatchError) no match of right hand side value: {:error, "Python bridge not available"}
     code: {:ok, _} = adapter.create_program(config)
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:118: (test)


08:16:47.948 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
  * test layer_1 adapter behavior compliance handles complex signatures [L#129]
08:16:47.948 [error] Python bridge not running - check supervision configuration
  * test layer_1 adapter behavior compliance handles complex signatures (0.06ms) [L#129]

08:16:47.948 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
  * test layer_2 adapter behavior compliance returns error for non-existent program [L#152]
08:16:47.948 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
  * test layer_2 adapter behavior compliance returns error for non-existent program (0.05ms) [L#152]

08:16:47.948 [error] Python bridge not running - check supervision configuration
  * test Error handling compliance provides test layer specific retry delays (0.05ms) [L#284]
  * test layer_2 adapter behavior compliance validates test layer support (0.02ms) [L#195]
  * test layer_3 adapter behavior compliance provides test capabilities (0.08ms) [L#186]
  * test layer_1 adapter behavior compliance returns error for non-existent program (0.03ms) [L#152]
  * test layer_1 adapter behavior compliance creates programs successfully (0.04ms) [L#98]
  * test Type conversion compliance converts basic types correctly (0.03ms) [L#233]
  * test Error handling compliance wraps errors with proper context (0.03ms) [L#275]
  * test layer_2 adapter behavior compliance executes programs with valid inputs (0.06ms) [L#110]
  * test layer_2 adapter behavior compliance provides test capabilities (0.03ms) [L#186]
  * test layer_3 adapter behavior compliance returns error for non-existent program (0.04ms) [L#152]
  * test layer_2 adapter behavior compliance creates programs successfully (0.05ms) [L#98]
  * test layer_3 adapter behavior compliance handles complex signatures (0.05ms) [L#129]

 16) test layer_3 adapter behavior compliance handles complex signatures (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:129
     ** (MatchError) no match of right hand side value: {:error, "Python bridge not available"}
     code: {:ok, program_id} = adapter.create_program(config)
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:136: (test)

Finished in 414.5 seconds (68.4s async, 346.0s sync)
45 doctests, 563 tests, 16 failures, 11 skipped





