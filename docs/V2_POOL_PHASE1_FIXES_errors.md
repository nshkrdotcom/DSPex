

21:38:35.109 [debug] Starting BridgeMock adapter
  1) test test capabilities provides correct test capabilities (DSPex.Adapters.BridgeMockTest)
     test/dspex/adapters/bridge_mock_test.exs:154
     ** (exit) exited in: GenServer.call(DSPex.Adapters.BridgeMock, :reset, 5000)
         ** (EXIT) no process: the process is not alive or there's no process currently associated with the given name, possibly because its application isn't started
     stacktrace:
       (elixir 1.18.3) lib/gen_server.ex:1128: GenServer.call/3




  2) test direct port communication with Port.command/2 (PortCommunicationTest)
     test/port_communication_test.exs:7
     No response received within 5 seconds
     code: flunk("No response received within 5 seconds")
     stacktrace:
       test/port_communication_test.exs:72: (test)




















  1) test graceful shutdown shuts down pool gracefully (DSPex.PythonBridge.SessionPoolTest)
     test/dspex/python_bridge/session_pool_test.exs:106
     ** (EXIT from #PID<0.918.0>) shutdown

.......✅ Gemini answered: 4
.✅ Found 3 programs in bridge
.Command error: Program not found: nonexistent
Traceback (most recent call last):
  File "/home/home/p/g/n/dspex/_build/test/lib/dspex/priv/python/dspy_bridge.py", line 1017, in main
    result = bridge.handle_command(command, args)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/home/p/g/n/dspex/_build/test/lib/dspex/priv/python/dspy_bridge.py", line 152, in handle_command
    result = handlers[command](args)
             ^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/home/p/g/n/dspex/_build/test/lib/dspex/priv/python/dspy_bridge.py", line 805, in execute_gemini_program
    raise ValueError(f"Program not found: {program_id}")
ValueError: Program not found: nonexistent



  2) test V2 Adapter Integration health check works (PoolV2Test)
     test/pool_v2_test.exs:289
     match (=) failed
     code:  assert :ok = adapter.health_check.()
     left:  :ok
     right: {:error, {:shutdown, {NimblePool, :checkout, [:test_pool_8706]}}}
     stacktrace:
       test/pool_v2_test.exs:291: (test)

Pool started without pre-warming (lazy initialization)

21:38:57.339 [debug] Attempting to checkout from pool: :test_pool_8770_pool

21:38:57.339 [debug] Initializing pool worker: worker_8834_1752478738618361

21:38:57.340 [debug] Attempting to checkout from pool: :test_pool_8770_pool

21:38:57.340 [debug] Attempting to checkout from pool: :test_pool_8770_pool

21:38:57.340 [debug] Attempting to checkout from pool: :test_pool_8770_pool

21:38:57.340 [debug] Attempting to checkout from pool: :test_pool_8770_pool

21:38:57.340 [debug] Attempting to checkout from pool: :test_pool_8770_pool

21:38:59.341 [info] DSPy version detected: 2.6.27

21:39:01.248 [info] Python environment validation successful: %{script_path: "/home/home/p/g/n/dspex/_build/test/lib/dspex/priv/python/dspy_bridge.py", dspy_version: "2.6.27", packages: ["dspy-ai"], python_path: "/home/home/.pyenv/shims/python3", python_version: "3.12.10"}

21:39:01.248 [debug] Starting Python process for worker worker_8834_1752478738618361

21:39:01.248 [info] About to send initialization ping for worker worker_8834_1752478738618361

21:39:01.248 [info] Sending init ping request: "{\"args\":{\"worker_id\":\"worker_8834_1752478738618361\",\"initialization\":true},\"command\":\"ping\",\"id\":0,\"timestamp\":\"2025-07-14T07:39:01.248505Z\"}"

21:39:01.248 [info] Request byte size: 141

21:39:01.248 [info] To port: #Port<0.96>

21:39:01.248 [info] Port.command result: true

21:39:01.248 [warning] Unexpected message during init: {:"$gen_call", {#PID<0.995.0>, #Reference<0.574118277.1636302849.221044>}, {:checkout, {:session, "error_test_2"}, -576460638828718986}}, continuing to wait...

21:39:01.248 [warning] Unexpected message during init: {:"$gen_call", {#PID<0.996.0>, #Reference<0.574118277.1636302849.221050>}, {:checkout, {:session, "error_test_3"}, -576460638828661504}}, continuing to wait...

21:39:01.248 [warning] Unexpected message during init: {:"$gen_call", {#PID<0.997.0>, #Reference<0.574118277.1636302849.221057>}, {:checkout, {:session, "error_test_4"}, -576460638828624842}}, continuing to wait...

21:39:01.248 [warning] Unexpected message during init: {:"$gen_call", {#PID<0.998.0>, #Reference<0.574118277.1636302849.221059>}, {:checkout, {:session, "error_test_5"}, -576460638828609259}}, continuing to wait...

21:39:01.248 [warning] Unexpected message during init: {:"$gen_call", {#PID<0.999.0>, #Reference<0.574118277.1636302849.221061>}, {:checkout, {:session, "error_test_6"}, -576460638828597931}}, continuing to wait...

21:39:01.248 [debug] Ignoring EXIT message during init, continuing to wait...

21:39:01.248 [debug] Ignoring EXIT message during init, continuing to wait...

21:39:01.248 [debug] Ignoring EXIT message during init, continuing to wait...

21:39:02.341 [warning] Unexpected message during init: {NimblePool, :cancel, #Reference<0.574118277.1636302849.221025>, :timeout}, continuing to wait...
Task 1 failed as expected

21:39:02.341 [warning] Unexpected message during init: {:DOWN, #Reference<0.574118277.1636302849.221030>, :process, #PID<0.994.0>, :normal}, continuing to wait...

21:39:02.341 [warning] Unexpected message during init: {NimblePool, :cancel, #Reference<0.574118277.1636302849.221044>, :timeout}, continuing to wait...

21:39:02.341 [warning] Unexpected message during init: {NimblePool, :cancel, #Reference<0.574118277.1636302849.221050>, :timeout}, continuing to wait...



21:39:02.341 [warning] Unexpected message during init: {NimblePool, :cancel, #Reference<0.574118277.1636302849.221057>, :timeout}, continuing to wait...
  3) test V2 Pool Architecture error handling doesn't affect other operations (PoolV2Test)
     test/pool_v2_test.exs:178
     match (=) failed
     code:  assert {:ok, _} = result
     left:  {:ok, _}
     right: {:error, {:pool_timeout, {:timeout, {NimblePool, :checkout, [:test_pool_8770_pool]}}}}
     stacktrace:
       test/pool_v2_test.exs:214: anonymous fn/2 in PoolV2Test."test V2 Pool Architecture error handling doesn't affect other operations"/1
       (elixir 1.18.3) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
       test/pool_v2_test.exs:212: (test)


21:39:02.341 [warning] Unexpected message during init: {NimblePool, :cancel, #Reference<0.574118277.1636302849.221059>, :timeout}, continuing to wait...

21:39:02.341 [warning] Unexpected message during init: {NimblePool, :cancel, #Reference<0.574118277.1636302849.221061>, :timeout}, continuing to wait...

21:39:02.341 [debug] Ignoring EXIT message during init, continuing to wait...

21:39:02.341 [info] Session pool V2 started with 2 workers, 0 overflow
Pool started without pre-warming (lazy initialization)
Session tracking working correctly
.
21:39:02.443 [info] Session pool V2 started with 2 workers, 0 overflow
Pool started without pre-warming (lazy initialization)

21:39:02.545 [debug] Attempting to checkout from pool: :test_pool_8962

21:39:02.545 [error] Checkout failed: {:shutdown, {NimblePool, :checkout, [:test_pool_8962]}}

21:39:02.545 [info] Session pool V2 started with 2 workers, 0 overflow

21:39:02.547 [info] Session pool V2 started with 2 workers, 0 overflow


  4) test V2 Pool Architecture session isolation works correctly (PoolV2Test)
     test/pool_v2_test.exs:139
     ** (MatchError) no match of right hand side value: {:error, "Checkout failed: {:shutdown, {NimblePool, :checkout, [:test_pool_8962]}}"}
     code: {:ok, program1_id} =
     stacktrace:
       test/pool_v2_test.exs:149: (test)

Pool started without pre-warming (lazy initialization)

21:39:02.651 [info] Session pool V2 started with 2 workers, 0 overflow

21:39:02.651 [info] Session pool V2 started with 2 workers, 0 overflow


  5) test V2 Adapter Integration adapter works with real LM configuration (PoolV2Test)
     test/pool_v2_test.exs:271
     match (=) failed
     code:  assert :ok = adapter.configure_lm.(config)
     left:  :ok
     right: {:error, {:shutdown, {NimblePool, :checkout, [:test_pool_9090]}}}
     stacktrace:
       test/pool_v2_test.exs:282: (test)

Pool started without pre-warming (lazy initialization)

21:39:02.755 [info] Session pool V2 started with 2 workers, 0 overflow


  6) test V2 Pool Architecture pool starts successfully with lazy workers (PoolV2Test)
     test/pool_v2_test.exs:50
     ** (FunctionClauseError) no function clause matching in PoolV2Test."test V2 Pool Architecture pool starts successfully with lazy workers"/1

     The following arguments were given to PoolV2Test."test V2 Pool Architecture pool starts successfully with lazy workers"/1:

         # 1
         %{async: false, line: 50, module: PoolV2Test, pid: #PID<0.1019.0>, registered: %{}, file: "/home/home/p/g/n/dspex/test/pool_v2_test.exs", test: :"test V2 Pool Architecture pool starts successfully with lazy workers", pool_size: 2, layer_3: true, describe: "V2 Pool Architecture", test_type: :test, genserver_name: :test_pool_9154, pool_name: :test_pool_9154_pool, test_pid: #PID<0.1017.0>, describe_line: 49, pool_v2: true}

     code: test "pool starts successfully with lazy workers", %{
     stacktrace:
       test/pool_v2_test.exs:50: (test)

Pool started without pre-warming (lazy initialization)



  7) test V2 Pool Architecture pool handles worker death gracefully (PoolV2Test)
     test/pool_v2_test.exs:223
     match (=) failed
     code:  assert {:ok, _} = SessionPoolV2.execute_in_session(session_id, :ping, %{}, pool_name: pool_name)
     left:  {:ok, _}
     right: {:error, {:pool_timeout, {:timeout, {NimblePool, :checkout, [:test_pool_9218_pool]}}}}
     stacktrace:
       test/pool_v2_test.exs:235: (test)

Pool started without pre-warming (lazy initialization)



  8) test pool works with lazy initialization (PoolFixedTest)
     test/pool_fixed_test.exs:7
     Assertion with != failed, both sides are exactly equal
     code: assert pool_supervisor != nil
     left: nil
     stacktrace:
       test/pool_fixed_test.exs:21: (test)


21:39:10.938 [info] DSPy version detected: 2.6.27

21:39:12.820 [info] Python environment validation successful: %{script_path: "/home/home/p/g/n/dspex/_build/test/lib/dspex/priv/python/dspy_bridge.py", dspy_version: "2.6.27", packages: ["dspy-ai"], python_path: "/home/home/.pyenv/shims/python3", python_version: "3.12.10"}

21:39:12.820 [info] Starting Python process...

21:39:12.820 [info] Port opened: #Port<0.104>

21:39:12.821 [info] Request JSON: {"args":{"initialization":true,"worker_id":"test123"},"command":"ping","id":0,"timestamp":"2025-07-14T07:39:12.820996Z"}

21:39:12.821 [info] Request byte size: 120

21:39:12.821 [info] Port.command/2 result: true

21:39:17.839 [error] Timeout! Port info: [name: ~c"/home/home/.pyenv/shims/python3", links: [#PID<0.1254.0>], id: 832, connected: #PID<0.1254.0>, input: 0, output: 120, os_pid: 1925679]

21:39:17.841 [info] Session pool V2 started with 3 workers, 0 overflow


  9) test direct port communication with Port.command/2 (PortCommunicationTest)
     test/port_communication_test.exs:7
     No response received within 5 seconds
     code: flunk("No response received within 5 seconds")
     stacktrace:
       test/port_communication_test.exs:72: (test)

Pre-warming 3 workers...
Warming worker 1/3...



 10) test pool handles blocking operations correctly (PoolV2ConcurrentTest)
     test/pool_v2_concurrent_test.exs:93
     match (=) failed
     code:  assert {:ok, programs} = result
     left:  {:ok, programs}
     right: {:error, "Program ID is required"}
     stacktrace:
       test/pool_v2_concurrent_test.exs:154: anonymous fn/2 in PoolV2ConcurrentTest."test pool handles blocking operations correctly"/1
       (elixir 1.18.3) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
       test/pool_v2_concurrent_test.exs:153: (test)




 11) test true concurrent execution with pre-warmed workers (PoolV2ConcurrentTest)
     test/pool_v2_concurrent_test.exs:11
     Assertion with < failed
     code:  assert d < 1000
     left:  5339
     right: 1000
     stacktrace:
       (elixir 1.18.3) lib/enum.ex:987: Enum."-each/2-lists^foreach/1-0-"/2
       test/pool_v2_concurrent_test.exs:87: (test)




 12) test get_adapter/1 respects TEST_MODE environment variable in test env (DSPex.Adapters.RegistryTest)
     test/dspex/adapters/registry_test.exs:54
     Assertion with == failed
     code:  assert Registry.get_adapter() == PythonPort
     left:  DSPex.Adapters.PythonPool
     right: DSPex.Adapters.PythonPort
     stacktrace:
       test/dspex/adapters/registry_test.exs:65: (test)

...



 13) test layer_3 adapter behavior compliance executes programs with valid inputs (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:110
     ** (MatchError) no match of right hand side value: {:error, "Python bridge not available"}
     code: {:ok, _} = adapter.create_program(config)
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:118: (test)


21:42:05.605 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
...
21:42:05.605 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
21:42:05.605 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
21:42:05.605 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

21:42:05.605 [error] Python bridge not running - check supervision configuration

21:42:05.605 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}



21:42:05.606 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 14) test layer_3 adapter behavior compliance creates programs successfully (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:98
     ** (MatchError) no match of right hand side value: {:error, "Python bridge not available"}
     code: {:ok, program_id} = adapter.create_program(config)
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:105: (test)


21:42:05.606 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
...
21:42:05.606 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
21:42:05.606 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
21:42:05.606 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
21:42:05.607 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

21:42:05.607 [error] Python bridge not running - check supervision configuration

21:42:05.607 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

21:42:05.607 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}



21:42:05.607 [error] Python bridge not running - check supervision configuration
 15) test layer_3 adapter behavior compliance handles complex signatures (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:129
     ** (MatchError) no match of right hand side value: {:error, "Python bridge not available"}
     code: {:ok, program_id} = adapter.create_program(config)
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:136: (test)


21:42:05.607 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
21:42:05.607 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

21:42:05.607 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

21:42:05.607 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}


 16) test layer_3 adapter behavior compliance lists programs correctly (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:158
     ** (MatchError) no match of right hand side value: {:error, "Python bridge not available"}
     code: for i <- 1..3 do
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:167: anonymous fn/4 in DSPex.Adapters.BehaviorComplianceTest."test layer_3 adapter behavior compliance lists programs correctly"/1
       (elixir 1.18.3) lib/enum.ex:4507: Enum.reduce/3
       test/dspex/adapters/behavior_compliance_test.exs:160: (test)

...
21:42:05.607 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
..
21:42:05.608 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
21:42:05.608 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
21:42:05.608 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
21:42:05.608 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
21:42:05.608 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
21:42:05.608 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

21:42:05.608 [error] Python bridge not running - check supervision configuration
.
21:42:05.608 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

21:42:05.608 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

21:42:05.608 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}



21:42:05.608 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 17) test Factory pattern compliance creates correct adapters for test layers (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:205
     ** (MatchError) no match of right hand side value: {:error, %DSPex.Adapters.ErrorHandler{type: :unknown, message: "Python bridge not running", context: %{adapter_type: nil, test_layer: :layer_3, resolved_adapter: DSPex.Adapters.PythonPort}, recoverable: false, retry_after: nil, test_layer: :layer_1}}
     code: for {layer, expected_adapter} <- @adapters_by_layer do
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:207: anonymous fn/2 in DSPex.Adapters.BehaviorComplianceTest."test Factory pattern compliance creates correct adapters for test layers"/1
       (stdlib 6.2.2) maps.erl:860: :maps.fold_1/4
       test/dspex/adapters/behavior_compliance_test.exs:206: (test)


21:42:05.608 [error] Python bridge not running - check supervision configuration
...
Finished in 290.8 seconds (48.8s async, 241.9s sync)
45 doctests, 563 tests, 17 failures, 11 skipped
home@U2401:~/p/g/n/dspex$



