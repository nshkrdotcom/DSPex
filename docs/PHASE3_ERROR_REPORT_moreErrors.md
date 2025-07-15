home@U2401:~/p/g/n/dspex$ mix test.integration
  1) test execute_program/2 executes program with wire protocol (DSPex.Adapters.BridgeMockTest)
     test/dspex/adapters/bridge_mock_test.exs:70
     ** (exit) exited in: GenServer.call(DSPex.Adapters.BridgeMock, :reset, 5000)
         ** (EXIT) no process: the process is not alive or there's no process currently associated with the given name, possibly because its application isn't started
     stacktrace:
       (elixir 1.18.3) lib/gen_server.ex:1128: GenServer.call/3
       test/dspex/adapters/bridge_mock_test.exs:10: DSPex.Adapters.BridgeMockTest.__ex_unit_setup_0/1
       test/dspex/adapters/bridge_mock_test.exs:1: DSPex.Adapters.BridgeMockTest.__ex_unit__/2


15:03:32.965 [debug] Session session_19 bound to worker worker_4
  2) test session expiration expired sessions are automatically removed (DSPex.PythonBridge.SessionAffinityTest)
     test/dspex/python_bridge/session_affinity_test.exs:117
     match (=) failed
     code:  assert {:error, :session_expired} = SessionAffinity.get_worker(session_id)
     left:  {:error, :session_expired}
     right: {:error, :no_affinity}
     stacktrace:
       test/dspex/python_bridge/session_affinity_test.exs:129: (test)


15:05:07.449 [debug] Initializing pool worker: worker_1740_1752541510209192
  3) test true concurrent execution with pre-warmed workers (PoolV2ConcurrentTest)
     test/pool_v2_concurrent_test.exs:11
     Assertion with < failed
     code:  assert d < 1000
     left:  5646
     right: 1000
     stacktrace:
       (elixir 1.18.3) lib/enum.ex:987: Enum."-each/2-lists^foreach/1-0-"/2
       test/pool_v2_concurrent_test.exs:87: (test)


15:05:39.713 [info] Session pool started with 1 workers, 2 overflow
  4) test pool handles blocking operations correctly (PoolV2ConcurrentTest)
     test/pool_v2_concurrent_test.exs:93
     Assertion with > failed, both sides are exactly equal
     code: assert length(programs) > 0
     left: 0
     stacktrace:
       test/pool_v2_concurrent_test.exs:161: anonymous fn/2 in PoolV2ConcurrentTest."test pool handles blocking operations correctly"/1
       (elixir 1.18.3) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
       test/pool_v2_concurrent_test.exs:153: (test)


  5) test graceful shutdown shuts down pool gracefully (DSPex.PythonBridge.SessionPoolTest)
     test/dspex/python_bridge/session_pool_test.exs:106
     ** (EXIT from #PID<0.1164.0>) shutdown


  6) test NimblePool return value compliance successful checkout returns proper tuple (PoolWorkerV2ReturnValuesTest)
     test/pool_worker_v2_return_values_test.exs:42
     ** (exit) exited in: GenServer.stop(#PID<0.1193.0>, :normal, :infinity)
         ** (EXIT) exited in: :sys.terminate(#PID<0.1193.0>, :normal, :infinity)
             ** (EXIT) shutdown
     stacktrace:
       (elixir 1.18.3) lib/gen_server.ex:1089: GenServer.stop/3
       (ex_unit 1.18.3) lib/ex_unit/on_exit_handler.ex:136: ExUnit.OnExitHandler.exec_callback/1
       (ex_unit 1.18.3) lib/ex_unit/on_exit_handler.ex:122: ExUnit.OnExitHandler.on_exit_runner_loop/0

No more messages, exiting
DSPy Bridge shutting down



  7) test NimblePool return value compliance connection failure returns remove tuple (PoolWorkerV2ReturnValuesTest)
     test/pool_worker_v2_return_values_test.exs:65
     ** (exit) exited in: GenServer.stop(#PID<0.1196.0>, :normal, :infinity)
         ** (EXIT) exited in: :sys.terminate(#PID<0.1196.0>, :normal, :infinity)
             ** (EXIT) shutdown
     stacktrace:
       (elixir 1.18.3) lib/gen_server.ex:1089: GenServer.stop/3
       (ex_unit 1.18.3) lib/ex_unit/on_exit_handler.ex:136: ExUnit.OnExitHandler.exec_callback/1
       (ex_unit 1.18.3) lib/ex_unit/on_exit_handler.ex:122: ExUnit.OnExitHandler.on_exit_runner_loop/0



  8) test NimblePool return value compliance invalid checkout type returns remove tuple (PoolWorkerV2ReturnValuesTest)
     test/pool_worker_v2_return_values_test.exs:79
     ** (exit) exited in: GenServer.stop(#PID<0.1200.0>, :normal, :infinity)
         ** (EXIT) exited in: :sys.terminate(#PID<0.1200.0>, :normal, :infinity)
             ** (EXIT) shutdown
     stacktrace:
       (elixir 1.18.3) lib/gen_server.ex:1089: GenServer.stop/3
       (ex_unit 1.18.3) lib/ex_unit/on_exit_handler.ex:136: ExUnit.OnExitHandler.exec_callback/1
       (ex_unit 1.18.3) lib/ex_unit/on_exit_handler.ex:122: ExUnit.OnExitHandler.on_exit_runner_loop/0


  9) test Error handling enhancement multiple catch clauses handle different error types (PoolWorkerV2ReturnValuesTest)
     test/pool_worker_v2_return_values_test.exs:103
     ** (exit) exited in: GenServer.stop(#PID<0.1203.0>, :normal, :infinity)
         ** (EXIT) exited in: :sys.terminate(#PID<0.1203.0>, :normal, :infinity)
             ** (EXIT) shutdown
     stacktrace:
       (elixir 1.18.3) lib/gen_server.ex:1089: GenServer.stop/3
       (ex_unit 1.18.3) lib/ex_unit/on_exit_handler.ex:136: ExUnit.OnExitHandler.exec_callback/1
       (ex_unit 1.18.3) lib/ex_unit/on_exit_handler.ex:122: ExUnit.OnExitHandler.on_exit_runner_loop/0



 10) test Port validation enhancement safe_port_connect validates before connecting (PoolWorkerV2ReturnValuesTest)
     test/pool_worker_v2_return_values_test.exs:96
     ** (exit) exited in: GenServer.stop(#PID<0.1206.0>, :normal, :infinity)
         ** (EXIT) exited in: :sys.terminate(#PID<0.1206.0>, :normal, :infinity)
             ** (EXIT) shutdown
     stacktrace:
       (elixir 1.18.3) lib/gen_server.ex:1089: GenServer.stop/3
       (ex_unit 1.18.3) lib/ex_unit/on_exit_handler.ex:136: ExUnit.OnExitHandler.exec_callback/1
       (ex_unit 1.18.3) lib/ex_unit/on_exit_handler.ex:122: ExUnit.OnExitHandler.on_exit_runner_loop/0



 11) test Port validation enhancement validate_port checks if port is open (PoolWorkerV2ReturnValuesTest)
     test/pool_worker_v2_return_values_test.exs:90
     ** (exit) exited in: GenServer.stop(#PID<0.1209.0>, :normal, :infinity)
         ** (EXIT) exited in: :sys.terminate(#PID<0.1209.0>, :normal, :infinity)
             ** (EXIT) shutdown
     stacktrace:
       (elixir 1.18.3) lib/gen_server.ex:1089: GenServer.stop/3
       (ex_unit 1.18.3) lib/ex_unit/on_exit_handler.ex:136: ExUnit.OnExitHandler.exec_callback/1
       (ex_unit 1.18.3) lib/ex_unit/on_exit_handler.ex:122: ExUnit.OnExitHandler.on_exit_runner_loop/0


 12) test get_adapter/1 respects TEST_MODE environment variable in test env (DSPex.Adapters.RegistryTest)
     test/dspex/adapters/registry_test.exs:54
     Assertion with == failed
     code:  assert Registry.get_adapter() == PythonPort
     left:  DSPex.Adapters.PythonPoolV2
     right: DSPex.Adapters.PythonPort
     stacktrace:
       test/dspex/adapters/registry_test.exs:65: (test)


 13) test V2 Adapter Integration health check works (PoolV2Test)
     test/pool_v2_test.exs:289
     ** (FunctionClauseError) no function clause matching in Keyword.get/3

     The following arguments were given to Keyword.get/3:

         # 1
         %{pool_name: :isolated_test_pool_1745_1809}

         # 2
         :max_retries

         # 3
         2

     Attempted function clauses (showing 1 out of 1):

         def get(keywords, key, default) when is_list(keywords) and is_atom(key)

     code: assert :ok = adapter.health_check.()
     stacktrace:
       (elixir 1.18.3) lib/keyword.ex:395: Keyword.get/3
       (dspex 0.1.0) lib/dspex/python_bridge/session_pool_v2.ex:97: DSPex.PythonBridge.SessionPoolV2.execute_anonymous/3
       (dspex 0.1.0) lib/dspex/adapters/python_pool_v2.ex:154: DSPex.Adapters.PythonPoolV2.health_check/1
       test/pool_v2_test.exs:291: (test)

No more messages, exiting
DSPy Bridge shutting down

15:06:51.209 [info] Terminating pool worker worker_1937_1752541605843100, reason: :shutdown





 14) test V2 Pool Architecture session isolation works correctly (PoolV2Test)
     test/pool_v2_test.exs:139
     ** (MatchError) no match of right hand side value: {:error, %{message: "Unexpected error: {:exit, {:noproc, {GenServer, :call, [DSPex.PythonBridge.ErrorRecoveryOrchestrator, {:handle_error, %{message: \"Unexpected error: {:system_error, {:shutdown, {NimblePool, :checkout, [:isolated_test_pool_3408_3472]}}}\", type: :unexpected, context: %{args: %{:session_id => \"session_isolation_test_1\", \"id\" => \"pool_3664_1752541634062369\", \"pool_name\" => :isolated_test_pool_3408_3472, \"signature\" => %{\"inputs\" => [%{\"name\" => \"input\", \"type\" => \"string\"}], \"outputs\" => [%{\"name\" => \"output\", \"type\" => \"string\"}]}}, command: :create_program, timestamp: 1752541633356, severity: :critical, session_id: \"session_isolation_test_1\", adapter: DSPex.PythonBridge.SessionPoolV2, operation: :execute_command, error_category: :system_error, recovery_strategy: :abandon}, __struct__: DSPex.PythonBridge.PoolErrorHandler, severity: :critical, test_layer: :layer_3, recoverable: false, retry_after: nil, error_category: :system_error, recovery_strategy: :abandon, pool_error: true}, %{args: %{:session_id => \"session_isolation_test_1\", \"id\" => \"pool_3664_1752541634062369\", \"pool_name\" => :isolated_test_pool_3408_3472, \"signature\" => %{\"inputs\" => [%{\"name\" => \"input\", \"type\" => \"string\"}], \"outputs\" => [%{\"name\" => \"output\", \"type\" => \"string\"}]}}, command: :create_program, session_id: \"session_isolation_test_1\", adapter: DSPex.PythonBridge.SessionPoolV2, operation: :execute_command}}, 30000]}}}", type: :unexpected, context: %{args: %{:session_id => "session_isolation_test_1", "id" => "pool_3664_1752541634062369", "pool_name" => :isolated_test_pool_3408_3472, "signature" => %{"inputs" => [%{"name" => "input", "type" => "string"}], "outputs" => [%{"name" => "output", "type" => "string"}]}}, command: :create_program, timestamp: 1752541633359, severity: :critical, session_id: "session_isolation_test_1", attempt: 1, adapter: DSPex.PythonBridge.SessionPoolV2, operation: :execute_command, error_category: :system_error, recovery_strategy: :abandon, retry_context: true}, __struct__: DSPex.PythonBridge.PoolErrorHandler, severity: :critical, test_layer: :layer_3, recoverable: false, retry_after: nil, error_category: :system_error, recovery_strategy: :abandon, pool_error: true}}
     code: {:ok, program1_id} =
     stacktrace:
       test/pool_v2_test.exs:149: (test)

No more messages, exiting
DSPy Bridge shutting down




 15) test V2 Adapter Integration adapter works with real LM configuration (PoolV2Test)
     test/pool_v2_test.exs:271
     ** (FunctionClauseError) no function clause matching in Keyword.get/3

     The following arguments were given to Keyword.get/3:

         # 1
         %{pool_name: :isolated_test_pool_4432_4496}

         # 2
         :max_retries

         # 3
         2

     Attempted function clauses (showing 1 out of 1):

         def get(keywords, key, default) when is_list(keywords) and is_atom(key)

     code: assert :ok = adapter.configure_lm.(config)
     stacktrace:
       (elixir 1.18.3) lib/keyword.ex:395: Keyword.get/3
       (dspex 0.1.0) lib/dspex/python_bridge/session_pool_v2.ex:97: DSPex.PythonBridge.SessionPoolV2.execute_anonymous/3
       (dspex 0.1.0) lib/dspex/adapters/python_pool_v2.ex:212: DSPex.Adapters.PythonPoolV2.configure_lm/2
       test/pool_v2_test.exs:282: (test)

No more messages, exiting
DSPy Bridge shutting down

15:07:46.952 [info] Terminating pool worker worker_4688_1752541661739366, reason: :shutdown



15:09:24.132 [debug] Worker transition recorded
 16) test Enhanced Worker Lifecycle Integration pool can be configured with different worker types (DSPex.PythonBridge.WorkerLifecycleIntegrationTest)
     test/dspex/python_bridge/worker_lifecycle_integration_test.exs:192
     Assertion with == failed
     code:  assert basic_status.session_affinity == %{}
     left:  %{expired_sessions: 0, total_sessions: 0, workers_with_sessions: 0}
     right: %{}
     stacktrace:
       test/dspex/python_bridge/worker_lifecycle_integration_test.exs:206: (test)



 17) test Enhanced Worker Lifecycle Integration handles concurrent operations correctly (DSPex.PythonBridge.WorkerLifecycleIntegrationTest)
     test/dspex/python_bridge/worker_lifecycle_integration_test.exs:229
     ** (exit) exited in: Task.await_many([%Task{mfa: {:erlang, :apply, 2}, owner: #PID<0.1524.0>, pid: #PID<0.1529.0>, ref: #Reference<0.0.195075.2993453447.3140812816.100387>}, %Task{mfa: {:erlang, :apply, 2}, owner: #PID<0.1524.0>, pid: #PID<0.1530.0>, ref: #Reference<0.0.195075.2993453447.3140812816.100388>}, %Task{mfa: {:erlang, :apply, 2}, owner: #PID<0.1524.0>, pid: #PID<0.1531.0>, ref: #Reference<0.0.195075.2993453447.3140812816.100389>}, %Task{mfa: {:erlang, :apply, 2}, owner: #PID<0.1524.0>, pid: #PID<0.1532.0>, ref: #Reference<0.0.195075.2993453447.3140812816.100390>}, %Task{mfa: {:erlang, :apply, 2}, owner: #PID<0.1524.0>, pid: #PID<0.1533.0>, ref: #Reference<0.0.195075.2993453447.3140812816.100391>}], 15000)
         ** (EXIT) time out
     code: results = Task.await_many(tasks, 15_000)
     stacktrace:
       (elixir 1.18.3) lib/task.ex:1011: Task.await_many/5
       (elixir 1.18.3) lib/task.ex:995: Task.await_many/2
       test/dspex/python_bridge/worker_lifecycle_integration_test.exs:247: (test)


15:09:50.478 [info] Python environment validation successful: %{script_path: "/home/home/p/g/n/dspex/_build/test/lib/dspex/priv/python/dspy_bridge.py", dspy_version: "2.6.27", packages: ["dspy-ai"], python_path: "/home/home/.pyenv/shims/python3", python_version: "3.12.10"}



15:10:11.155 [info] Worker state_test_worker transitioning initializing -> ready (reason: init_complete)
 18) test Enhanced Worker Lifecycle Integration worker state machine handles all transitions correctly (DSPex.PythonBridge.WorkerLifecycleIntegrationTest)
     test/dspex/python_bridge/worker_lifecycle_integration_test.exs:113
     Assertion with == failed
     code:  assert length(sm.transition_history) == 6
     left:  7
     right: 6
     stacktrace:
       test/dspex/python_bridge/worker_lifecycle_integration_test.exs:150: (test)



19) test pool works with lazy initialization (PoolFixedTest)
     test/pool_fixed_test.exs:24
     Assertion with != failed, both sides are exactly equal
     code: assert pool_supervisor != nil
     left: nil
     stacktrace:
       test/pool_fixed_test.exs:34: (test)



15:11:18.179 [warning] Received DOWN message for unknown task ref: #Reference<0.0.234499.2993453447.3140812813.98554>
 20) test capacity management rejects new recoveries when at capacity (DSPex.PythonBridge.ErrorRecoveryOrchestratorTest)
     test/dspex/python_bridge/error_recovery_orchestrator_test.exs:113
     Assertion with == failed
     code:  assert result == {:error, :recovery_capacity_exceeded}
     left:  {:error, :no_original_operation}
     right: {:error, :recovery_capacity_exceeded}
     stacktrace:
       test/dspex/python_bridge/error_recovery_orchestrator_test.exs:151: (test)



15:12:25.094 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

15:12:25.094 [error] Task #PID<0.2136.0> started from #PID<0.2134.0> terminating
** (ArgumentError) unknown registry: DSPex.Registry
    (elixir 1.18.3) lib/registry.ex:1457: Registry.key_info!/1
    (elixir 1.18.3) lib/registry.ex:590: Registry.lookup/2
    (dspex 0.1.0) lib/dspex/adapters/python_port.ex:455: DSPex.Adapters.PythonPort.detect_via_registry/0
    (dspex 0.1.0) lib/dspex/adapters/python_port.ex:440: DSPex.Adapters.PythonPort.ensure_bridge_started/0
    (dspex 0.1.0) lib/dspex/adapters/python_port.ex:261: DSPex.Adapters.PythonPort.health_check/0
    (elixir 1.18.3) lib/task/supervised.ex:101: Task.Supervised.invoke_mfa/2
    (elixir 1.18.3) lib/task/supervised.ex:36: Task.Supervised.reply/4
Function: #Function<0.70976609/0 in DSPex.Adapters.Factory.apply_with_timeout/4>
    Args: []



15:12:25.097 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 21) test test layer specific behavior layer_3 uses long timeouts and more retries (DSPex.Adapters.FactoryTest)
     test/dspex/adapters/factory_test.exs:330
     ** (EXIT from #PID<0.2134.0>) an exception was raised:
         ** (ArgumentError) unknown registry: DSPex.Registry
             (elixir 1.18.3) lib/registry.ex:1457: Registry.key_info!/1
             (elixir 1.18.3) lib/registry.ex:590: Registry.lookup/2
             (dspex 0.1.0) lib/dspex/adapters/python_port.ex:455: DSPex.Adapters.PythonPort.detect_via_registry/0
             (dspex 0.1.0) lib/dspex/adapters/python_port.ex:440: DSPex.Adapters.PythonPort.ensure_bridge_started/0
             (dspex 0.1.0) lib/dspex/adapters/python_port.ex:261: DSPex.Adapters.PythonPort.health_check/0
             (elixir 1.18.3) lib/task/supervised.ex:101: Task.Supervised.invoke_mfa/2
             (elixir 1.18.3) lib/task/supervised.ex:36: Task.Supervised.reply/4


15:12:25.097 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

15:12:25.097 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}



15:12:25.098 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 22) test create_adapter/2 creates python port adapter for layer_3 (DSPex.Adapters.FactoryTest)
     test/dspex/adapters/factory_test.exs:70
     ** (MatchError) no match of right hand side value: {:error, %DSPex.Adapters.ErrorHandler{type: :unknown, message: "Python bridge not running", context: %{adapter_type: nil, test_layer: :layer_3, resolved_adapter: DSPex.Adapters.PythonPort}, recoverable: false, retry_after: nil, test_layer: :layer_1}}
     code: {:ok, adapter} = Factory.create_adapter(nil, test_layer: :layer_3)
     stacktrace:
       test/dspex/adapters/factory_test.exs:71: (test)


15:12:25.098 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}



15:12:35.059 [debug] Bridge startup check failed: :bridge_not_running

15:12:35.113 [error] Python bridge process not running

15:12:35.113 [debug] Bridge startup check failed: :bridge_not_running


 23) test Gemini integration with Elixir signatures can ping bridge and verify Gemini availability (DSPex.GeminiIntegrationTest)
     test/dspex/gemini_integration_test.exs:27
     Bridge ping failed: :bridge_not_running
     code: flunk("Bridge ping failed: #{inspect(reason)}")
     stacktrace:
       test/dspex/gemini_integration_test.exs:36: (test)


15:12:35.166 [debug] Bridge startup check failed: :bridge_not_running

15:12:35.220 [debug] Bridge startup check failed: :bridge_not_running




15:12:45.082 [debug] Bridge startup check failed: :bridge_not_running

15:12:45.135 [error] Python bridge process not running

15:12:45.135 [debug] Bridge startup check failed: :bridge_not_running


 24) test Gemini integration with Elixir signatures can create and execute Gemini program with simple QA (DSPex.GeminiIntegrationTest)
     test/dspex/gemini_integration_test.exs:40
     Program creation failed: :bridge_not_running
     code: flunk("Program creation failed: #{inspect(reason)}")
     stacktrace:
       test/dspex/gemini_integration_test.exs:70: (test)


15:12:45.188 [debug] Bridge startup check failed: :bridge_not_running

15:12:45.241 [debug] Bridge startup check failed: :bridge_not_running




15:12:53.756 [debug] Bridge startup check failed: :bridge_not_running

15:12:53.809 [error] Python bridge process not running

15:12:53.809 [debug] Bridge startup check failed: :bridge_not_running


 25) test Gemini integration with Elixir signatures can handle complex multi-field signatures (DSPex.GeminiIntegrationTest)
     test/dspex/gemini_integration_test.exs:104
     ** (MatchError) no match of right hand side value: {:error, :bridge_not_running}
     code: {:ok, _result} =
     stacktrace:
       test/dspex/gemini_integration_test.exs:119: (test)


15:12:53.862 [debug] Bridge startup check failed: :bridge_not_ru



:13:03.804 [debug] Bridge startup check failed: :bridge_not_running

15:13:03.857 [error] Python bridge process not running

15:13:03.857 [debug] Bridge startup check failed: :bridge_not_running


 26) test Gemini integration with Elixir signatures handles errors gracefully (DSPex.GeminiIntegrationTest)
     test/dspex/gemini_integration_test.exs:246
     Expected truthy, got false
     code: assert is_binary(reason)
     arguments:

         # 1
         :bridge_not_running

     stacktrace:
       test/dspex/gemini_integration_test.exs:257: (test)


15:13:03.910 [debug] Bridge startup check failed: :bridge_not_running

15:13:03.963 [debug] Bridge startup check failed: :bridge_not_running


g] Bridge startup check failed: :bridge_not_running

15:13:13.820 [debug] Bridge startup check failed: :bridge_not_running

15:13:13.871 [error] Python bridge process not running

15:13:13.872 [debug] Bridge startup check failed: :bridge_not_running


 27) test Gemini integration with Elixir signatures can get bridge statistics (DSPex.GeminiIntegrationTest)
     test/dspex/gemini_integration_test.exs:222
     Get stats failed: :bridge_not_running
     code: flunk("Get stats failed: #{inspect(reason)}")
     stacktrace:
       test/dspex/gemini_integration_test.exs:242: (test)


15:13:13.925 [debug] Bridge startup check failed: :bridge_not_running

15:13:13.976 [debug] Bridge startup check failed: :bridge_not_running




15:13:22.462 [debug] Bridge startup check failed: :bridge_not_running

15:13:22.515 [error] Python bridge process not running


 28) test Gemini integration with Elixir signatures can list and manage multiple programs (DSPex.GeminiIntegrationTest)
     test/dspex/gemini_integration_test.exs:171
     ** (MatchError) no match of right hand side value: {:error, :bridge_not_running}
     code: for i <- 1..3 do
     stacktrace:
       test/dspex/gemini_integration_test.exs:177: anonymous fn/1 in DSPex.GeminiIntegrationTest."test Gemini integration with Elixir signatures can list and manage multiple programs"/1
       (elixir 1.18.3) lib/enum.ex:4484: Enum.map/2
       test/dspex/gemini_integration_test.exs:174: (test)

...............................
15:13:22.519 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
....
15:13:22.520 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
15:13:22.520 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

15:13:22.520 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

15:13:22.520 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}



15:13:22.520 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 29) test layer_3 adapter behavior compliance executes programs with valid inputs (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:110
     ** (ArgumentError) unknown registry: DSPex.Registry
     code: {:ok, _} = adapter.create_program(config)
     stacktrace:
       (elixir 1.18.3) lib/registry.ex:1457: Registry.key_info!/1
       (elixir 1.18.3) lib/registry.ex:590: Registry.lookup/2
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:455: DSPex.Adapters.PythonPort.detect_via_registry/0
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:440: DSPex.Adapters.PythonPort.ensure_bridge_started/0
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:51: DSPex.Adapters.PythonPort.create_program/1
       test/dspex/adapters/behavior_compliance_test.exs:118: (test)


15:13:22.520 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
....
15:13:22.521 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
15:13:22.521 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

15:13:22.521 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}



15:13:22.521 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 30) test layer_3 adapter behavior compliance returns error for non-existent program (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:152
     ** (ArgumentError) unknown registry: DSPex.Registry
     code: {:error, _reason} = adapter.execute_program("nonexistent", inputs)
     stacktrace:
       (elixir 1.18.3) lib/registry.ex:1457: Registry.key_info!/1
       (elixir 1.18.3) lib/registry.ex:590: Registry.lookup/2
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:455: DSPex.Adapters.PythonPort.detect_via_registry/0
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:440: DSPex.Adapters.PythonPort.ensure_bridge_started/0
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:86: DSPex.Adapters.PythonPort.execute_program/2
       test/dspex/adapters/behavior_compliance_test.exs:154: (test)


15:13:22.521 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
...
15:13:22.521 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
15:13:22.521 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
15:13:22.521 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

15:13:22.522 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}



15:13:22.522 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 31) test layer_3 adapter behavior compliance lists programs correctly (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:158
     ** (ArgumentError) unknown registry: DSPex.Registry
     code: for i <- 1..3 do
     stacktrace:
       (elixir 1.18.3) lib/registry.ex:1457: Registry.key_info!/1
       (elixir 1.18.3) lib/registry.ex:590: Registry.lookup/2
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:455: DSPex.Adapters.PythonPort.detect_via_registry/0
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:440: DSPex.Adapters.PythonPort.ensure_bridge_started/0
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:51: DSPex.Adapters.PythonPort.create_program/1
       test/dspex/adapters/behavior_compliance_test.exs:167: anonymous fn/4 in DSPex.Adapters.BehaviorComplianceTest."test layer_3 adapter behavior compliance lists programs correctly"/1
       (elixir 1.18.3) lib/enum.ex:4507: Enum.reduce/3
       test/dspex/adapters/behavior_compliance_test.exs:160: (test)


15:13:22.522 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

15:13:22.522 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

15:13:22.522 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

15:13:22.522 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}



15:13:22.522 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 32) test layer_3 adapter behavior compliance supports health check (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:175
     ** (ArgumentError) unknown registry: DSPex.Registry
     code: case adapter.health_check() do
     stacktrace:
       (elixir 1.18.3) lib/registry.ex:1457: Registry.key_info!/1
       (elixir 1.18.3) lib/registry.ex:590: Registry.lookup/2
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:455: DSPex.Adapters.PythonPort.detect_via_registry/0
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:440: DSPex.Adapters.PythonPort.ensure_bridge_started/0
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:261: DSPex.Adapters.PythonPort.health_check/0
       test/dspex/adapters/behavior_compliance_test.exs:177: (test)


15:13:22.522 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
15:13:22.522 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

15:13:22.522 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}

15:13:22.523 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}



15:13:22.523 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 33) test Factory pattern compliance creates correct adapters for test layers (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:205
     ** (MatchError) no match of right hand side value: {:error, %DSPex.Adapters.ErrorHandler{type: :unknown, message: "Python bridge not running", context: %{adapter_type: nil, test_layer: :layer_3, resolved_adapter: DSPex.Adapters.PythonPort}, recoverable: false, retry_after: nil, test_layer: :layer_1}}
     code: for {layer, expected_adapter} <- @adapters_by_layer do
     stacktrace:
       test/dspex/adapters/behavior_compliance_test.exs:207: anonymous fn/2 in DSPex.Adapters.BehaviorComplianceTest."test Factory pattern compliance creates correct adapters for test layers"/1
       (stdlib 6.2.2) maps.erl:860: :maps.fold_1/4
       test/dspex/adapters/behavior_compliance_test.exs:206: (test)

.
15:13:22.523 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
...
15:13:22.523 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}



15:13:22.525 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
 34) test layer_3 adapter behavior compliance creates programs successfully (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:98
     ** (ArgumentError) unknown registry: DSPex.Registry
     code: {:ok, program_id} = adapter.create_program(config)
     stacktrace:
       (elixir 1.18.3) lib/registry.ex:1457: Registry.key_info!/1
       (elixir 1.18.3) lib/registry.ex:590: Registry.lookup/2
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:455: DSPex.Adapters.PythonPort.detect_via_registry/0
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:440: DSPex.Adapters.PythonPort.ensure_bridge_started/0
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:51: DSPex.Adapters.PythonPort.create_program/1
       test/dspex/adapters/behavior_compliance_test.exs:105: (test)


15:13:22.525 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
15:13:22.525 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
.
15:13:22.525 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
....
15:13:22.525 [debug] Mock adapter started with config: %{deterministic: true, name: DSPex.Adapters.Mock, response_delay_ms: 0, error_rate: 0.0, mock_responses: %{}}
....

 35) test layer_3 adapter behavior compliance handles complex signatures (DSPex.Adapters.BehaviorComplianceTest)
     test/dspex/adapters/behavior_compliance_test.exs:129
     ** (ArgumentError) unknown registry: DSPex.Registry
     code: {:ok, program_id} = adapter.create_program(config)
     stacktrace:
       (elixir 1.18.3) lib/registry.ex:1457: Registry.key_info!/1
       (elixir 1.18.3) lib/registry.ex:590: Registry.lookup/2
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:455: DSPex.Adapters.PythonPort.detect_via_registry/0
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:440: DSPex.Adapters.PythonPort.ensure_bridge_started/0
       (dspex 0.1.0) lib/dspex/adapters/python_port.ex:51: DSPex.Adapters.PythonPort.create_program/1
       test/dspex/adapters/behavior_compliance_test.exs:136: (test)

.....................
Finished in 616.7 seconds (49.3s async, 567.4s sync)
45 doctests, 728 tests, 35 failures, 11 skipped
No more messages, exiting
No more messages, exiting
DSPy Bridge shutting down

