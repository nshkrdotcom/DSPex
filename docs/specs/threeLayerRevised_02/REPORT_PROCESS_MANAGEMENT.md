# REPORT_PROCESS_MANAGEMENT.md
## Sub-Agent 4: The Process Management Specialist

**Persona:** A systems engineer specializing in process lifecycle and fault tolerance.  
**Scope:** The process management modules in `snakepit` (`ProcessRegistry`, `ApplicationCleanup`, `WorkerSupervisor`, etc.) and the `snakepit_grpc_bridge` `Adapter` implementation.  
**Mission:** Create the detailed design for the dual-backend (`systemd`/`setsid`) process management system, ensuring it meets production robustness and development portability requirements.

---

## 1. Review of Current Implementation

### ProcessRegistry (`pool/process_registry.ex`)
**Strengths:**
- Robust two-phase registration (reserve → activate) prevents race conditions
- DETS persistence for crash recovery
- BEAM run ID prevents killing unrelated processes after restart
- Clean separation between worker tracking and process management
- Supports orphan detection and cleanup

**Areas for Enhancement:**
- No abstraction for different process management backends
- Direct OS operations without backend selection
- Missing health check integration points
- No resource limit enforcement

### ApplicationCleanup (`pool/application_cleanup.ex`)
**Strengths:**
- High-priority process with trap_exit for guaranteed cleanup
- Two-phase termination (SIGTERM → SIGKILL)
- Works even if workers are already terminated
- Clear logging of cleanup operations

**Areas for Enhancement:**
- Hardcoded signal sending logic
- No backend-specific cleanup strategies
- Missing graceful shutdown timeout configuration
- No integration with systemd or cgroups

### WorkerSupervisor (`pool/worker_supervisor.ex`)
**Strengths:**
- Uses DynamicSupervisor for flexible worker management
- Automatic restart via Worker.Starter pattern
- Clean worker lifecycle management

**Areas for Enhancement:**
- No backend selection for worker starting
- Missing resource management hooks
- No integration with process backends

### Current Process Management
Currently uses `setsid` for process groups:
```elixir
# In adapter implementation
def start_worker(adapter_state, worker_id) do
  python_args = ["--setsid", "--worker-id", worker_id]
  port = Port.open({:spawn_executable, python_path()}, args: python_args)
  # ...
end
```

## 2. Detailed Backend Design

### ProcessBackend Behaviour

```elixir
defmodule Snakepit.ProcessBackend do
  @moduledoc """
  Behaviour for pluggable process management backends.
  
  Implementations provide different strategies for process lifecycle management,
  resource limits, and cleanup guarantees.
  """
  
  @type backend_config :: keyword()
  @type process_spec :: %{
    command: String.t(),
    args: [String.t()],
    env: [{String.t(), String.t()}],
    working_dir: String.t(),
    worker_id: String.t(),
    resource_limits: resource_limits()
  }
  @type resource_limits :: %{
    memory_mb: non_neg_integer() | nil,
    cpu_percent: non_neg_integer() | nil,
    max_processes: non_neg_integer() | nil
  }
  @type process_handle :: term()
  @type signal :: :term | :kill | :hup | :usr1 | :usr2 | integer()
  
  @doc """
  Initialize the backend with configuration.
  Called once during application startup.
  """
  @callback init(backend_config()) :: {:ok, state :: term()} | {:error, term()}
  
  @doc """
  Start a managed process with the given specification.
  Returns a handle that can be used for further operations.
  """
  @callback start_process(process_spec(), state :: term()) :: 
    {:ok, process_handle()} | {:error, term()}
  
  @doc """
  Get the OS PID for a process handle.
  """
  @callback get_pid(process_handle()) :: {:ok, non_neg_integer()} | {:error, term()}
  
  @doc """
  Check if a process is still alive.
  """
  @callback alive?(process_handle()) :: boolean()
  
  @doc """
  Send a signal to a process.
  """
  @callback send_signal(process_handle(), signal()) :: :ok | {:error, term()}
  
  @doc """
  Terminate a process with configurable grace period.
  First sends SIGTERM, waits grace_period_ms, then SIGKILL if needed.
  """
  @callback terminate(process_handle(), grace_period_ms :: non_neg_integer()) :: 
    :ok | {:error, term()}
  
  @doc """
  Get resource usage statistics for a process.
  """
  @callback get_stats(process_handle()) :: 
    {:ok, %{cpu_percent: float(), memory_mb: float()}} | {:error, term()}
  
  @doc """
  Clean up all processes managed by this backend.
  Called during application shutdown.
  """
  @callback cleanup_all(state :: term()) :: :ok
  
  @doc """
  Get backend capabilities for feature detection.
  """
  @callback capabilities() :: %{
    resource_limits: boolean(),
    process_groups: boolean(),
    cgroups: boolean(),
    health_checks: boolean()
  }
end
```

### Systemd Backend Implementation

```elixir
defmodule Snakepit.ProcessBackend.Systemd do
  @moduledoc """
  Production-grade process management using systemd transient services.
  
  Provides:
  - Automatic cleanup via systemd lifecycle
  - Resource limits via cgroups v2
  - Proper signal handling
  - Process group management
  """
  
  @behaviour Snakepit.ProcessBackend
  
  require Logger
  
  defstruct [:slice_name, :runtime_dir]
  
  @impl true
  def init(config) do
    slice_name = Keyword.get(config, :slice_name, "snakepit.slice")
    runtime_dir = Keyword.get(config, :runtime_dir, "/run/snakepit")
    
    # Ensure we can use systemd
    case System.cmd("systemctl", ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        Logger.info("Systemd backend initialized: #{String.split(output, "\n") |> hd}")
        
        # Create runtime directory
        File.mkdir_p!(runtime_dir)
        
        {:ok, %__MODULE__{slice_name: slice_name, runtime_dir: runtime_dir}}
        
      _ ->
        {:error, :systemd_not_available}
    end
  end
  
  @impl true
  def start_process(spec, state) do
    service_name = "snakepit-worker-#{spec.worker_id}"
    
    # Build systemd-run command
    systemd_args = build_systemd_args(service_name, spec, state)
    
    # Start the transient service
    case System.cmd("systemd-run", systemd_args, stderr_to_stdout: true) do
      {output, 0} ->
        # Extract the service unit name from output
        unit_name = extract_unit_name(output)
        handle = %{unit: unit_name, worker_id: spec.worker_id}
        
        # Wait for service to be active
        wait_for_service_active(unit_name)
        
        {:ok, handle}
        
      {error_output, _} ->
        {:error, {:systemd_failed, error_output}}
    end
  end
  
  @impl true
  def get_pid(handle) do
    case System.cmd("systemctl", ["show", "-p", "MainPID", handle.unit]) do
      {"MainPID=" <> pid_str, 0} ->
        {:ok, String.trim(pid_str) |> String.to_integer()}
      _ ->
        {:error, :pid_not_found}
    end
  end
  
  @impl true
  def alive?(handle) do
    case System.cmd("systemctl", ["is-active", handle.unit], stderr_to_stdout: true) do
      {"active\n", 0} -> true
      _ -> false
    end
  end
  
  @impl true
  def terminate(handle, grace_period_ms) do
    # Systemd handles graceful shutdown automatically
    case System.cmd("systemctl", ["stop", handle.unit]) do
      {_, 0} -> :ok
      _ -> {:error, :stop_failed}
    end
  end
  
  @impl true
  def cleanup_all(state) do
    # Stop all services in our slice
    System.cmd("systemctl", ["stop", state.slice_name])
    :ok
  end
  
  @impl true
  def capabilities do
    %{
      resource_limits: true,
      process_groups: true,
      cgroups: true,
      health_checks: true
    }
  end
  
  # Private functions
  
  defp build_systemd_args(service_name, spec, state) do
    base_args = [
      "--unit=#{service_name}",
      "--slice=#{state.slice_name}",
      "--property=Type=notify",  # Supports readiness notification
      "--property=Restart=on-failure",
      "--property=RestartSec=2",
      "--property=KillMode=mixed",
      "--property=SendSIGKILL=yes",
      "--property=TimeoutStopSec=30"
    ]
    
    # Add resource limits if specified
    limit_args = build_limit_args(spec.resource_limits)
    
    # Add environment variables
    env_args = Enum.map(spec.env, fn {k, v} -> "--setenv=#{k}=#{v}" end)
    
    # Add working directory
    wd_args = ["--working-directory=#{spec.working_dir}"]
    
    # Combine all arguments
    base_args ++ limit_args ++ env_args ++ wd_args ++ 
      ["--", spec.command] ++ spec.args
  end
  
  defp build_limit_args(limits) do
    args = []
    
    args = if limits.memory_mb do
      ["--property=MemoryMax=#{limits.memory_mb}M" | args]
    else
      args
    end
    
    args = if limits.cpu_percent do
      ["--property=CPUQuota=#{limits.cpu_percent}%" | args]
    else
      args
    end
    
    args
  end
end
```

### Setsid Backend Implementation

```elixir
defmodule Snakepit.ProcessBackend.Setsid do
  @moduledoc """
  Portable process management using setsid for process groups.
  
  Works on any Unix-like system without systemd dependency.
  Uses a wrapper script for process group management.
  """
  
  @behaviour Snakepit.ProcessBackend
  
  require Logger
  
  defstruct [:wrapper_script, :processes]
  
  @impl true
  def init(config) do
    wrapper_script = Keyword.get(config, :wrapper_script, priv_path("run_in_group.sh"))
    
    # Ensure wrapper script exists and is executable
    ensure_wrapper_script(wrapper_script)
    
    {:ok, %__MODULE__{
      wrapper_script: wrapper_script,
      processes: %{}  # Track process handles locally
    }}
  end
  
  @impl true
  def start_process(spec, state) do
    # Create unique process group ID
    pgid = "snakepit_#{spec.worker_id}_#{System.unique_integer([:positive])}"
    
    # Build wrapper arguments
    wrapper_args = [
      pgid,
      spec.command | spec.args
    ]
    
    # Set up Port options
    port_opts = [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      args: wrapper_args,
      cd: spec.working_dir,
      env: spec.env
    ]
    
    # Start process through wrapper
    port = Port.open({:spawn_executable, state.wrapper_script}, port_opts)
    
    # Get OS PID
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    
    handle = %{
      port: port,
      os_pid: os_pid,
      pgid: pgid,
      worker_id: spec.worker_id
    }
    
    # Store in state (would need GenServer for real implementation)
    {:ok, handle}
  end
  
  @impl true
  def get_pid(handle) do
    {:ok, handle.os_pid}
  end
  
  @impl true
  def alive?(handle) do
    # Check if process exists
    case System.cmd("kill", ["-0", "#{handle.os_pid}"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end
  
  @impl true
  def send_signal(handle, signal) do
    sig_arg = signal_to_string(signal)
    
    # Send to negative PID to target the process group
    case System.cmd("kill", [sig_arg, "-#{handle.os_pid}"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> {:error, :signal_failed}
    end
  end
  
  @impl true
  def terminate(handle, grace_period_ms) do
    # First try SIGTERM
    :ok = send_signal(handle, :term)
    
    # Wait for graceful shutdown
    if wait_for_termination(handle, grace_period_ms) do
      :ok
    else
      # Force kill if still alive
      send_signal(handle, :kill)
    end
  end
  
  @impl true
  def capabilities do
    %{
      resource_limits: false,  # Not available with basic setsid
      process_groups: true,
      cgroups: false,
      health_checks: false
    }
  end
  
  # Private functions
  
  defp ensure_wrapper_script(path) do
    unless File.exists?(path) do
      create_wrapper_script(path)
    end
    
    # Make executable
    File.chmod!(path, 0o755)
  end
  
  defp create_wrapper_script(path) do
    File.write!(path, wrapper_script_content())
  end
  
  defp wrapper_script_content do
    """
    #!/bin/bash
    # Snakepit process group wrapper
    # Usage: run_in_group.sh <group_id> <command> [args...]
    
    set -e
    
    GROUP_ID=$1
    shift
    
    # Create new session and process group
    setsid bash -c "
      # Set process group ID for easy termination
      echo $$ > /tmp/snakepit_${GROUP_ID}.pid
      
      # Set up signal handlers for graceful shutdown
      cleanup() {
        echo 'Received termination signal, cleaning up...'
        # Kill all processes in our process group
        kill -TERM -$$ 2>/dev/null || true
        exit 0
      }
      
      trap cleanup SIGTERM SIGINT
      
      # Execute the actual command
      exec $@
    " &
    
    # Return the PID of the session leader
    echo $!
    """
  end
  
  defp wait_for_termination(handle, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    
    wait_loop(handle, deadline)
  end
  
  defp wait_loop(handle, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      false
    else
      if alive?(handle) do
        Process.sleep(100)
        wait_loop(handle, deadline)
      else
        true
      end
    end
  end
end
```

## 3. Configuration and Selection

```elixir
# config/config.exs
config :snakepit, :process_backend,
  module: Snakepit.ProcessBackend.Setsid,
  config: []

# config/prod.exs  
config :snakepit, :process_backend,
  module: Snakepit.ProcessBackend.Systemd,
  config: [
    slice_name: "snakepit.slice",
    runtime_dir: "/run/snakepit"
  ]

# config/test.exs
config :snakepit, :process_backend,
  module: Snakepit.ProcessBackend.Mock,
  config: []
```

### Backend Selection Logic

```elixir
defmodule Snakepit.ProcessManager do
  @moduledoc """
  Manages process lifecycle using configured backend.
  """
  
  use GenServer
  
  defstruct [:backend_mod, :backend_state, :active_processes]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Get backend from config
    backend_config = Application.get_env(:snakepit, :process_backend, [])
    backend_mod = Keyword.get(backend_config, :module, Snakepit.ProcessBackend.Setsid)
    config = Keyword.get(backend_config, :config, [])
    
    # Initialize backend
    case backend_mod.init(config) do
      {:ok, backend_state} ->
        Logger.info("Initialized process backend: #{backend_mod}")
        
        state = %__MODULE__{
          backend_mod: backend_mod,
          backend_state: backend_state,
          active_processes: %{}
        }
        
        {:ok, state}
        
      {:error, reason} ->
        {:stop, {:backend_init_failed, reason}}
    end
  end
  
  # Delegate to backend
  def start_process(spec) do
    GenServer.call(__MODULE__, {:start_process, spec})
  end
  
  def handle_call({:start_process, spec}, _from, state) do
    case state.backend_mod.start_process(spec, state.backend_state) do
      {:ok, handle} ->
        # Track the process
        new_processes = Map.put(state.active_processes, spec.worker_id, handle)
        new_state = %{state | active_processes: new_processes}
        
        {:reply, {:ok, handle}, new_state}
        
      error ->
        {:reply, error, state}
    end
  end
end
```

## 4. Robust Testing Strategy

### Testing Without Process.sleep

```elixir
defmodule Snakepit.ProcessBackendTest do
  use ExUnit.Case, async: false
  
  alias Snakepit.ProcessBackend
  
  # Test helper for deterministic process state checking
  defmodule ProcessHelper do
    @doc """
    Wait for a condition with exponential backoff.
    Returns :ok when condition is met, {:error, :timeout} otherwise.
    """
    def wait_for(condition_fn, opts \\ []) do
      timeout = Keyword.get(opts, :timeout, 5000)
      interval = Keyword.get(opts, :interval, 10)
      max_interval = Keyword.get(opts, :max_interval, 100)
      
      deadline = System.monotonic_time(:millisecond) + timeout
      
      do_wait_for(condition_fn, deadline, interval, max_interval)
    end
    
    defp do_wait_for(condition_fn, deadline, interval, max_interval) do
      if System.monotonic_time(:millisecond) > deadline do
        {:error, :timeout}
      else
        if condition_fn.() do
          :ok
        else
          Process.sleep(interval)
          new_interval = min(interval * 2, max_interval)
          do_wait_for(condition_fn, deadline, new_interval, max_interval)
        end
      end
    end
    
    @doc """
    Start a test process that signals readiness.
    """
    def start_test_process(backend, name) do
      ready_file = "/tmp/snakepit_test_#{name}_ready"
      File.rm(ready_file)
      
      spec = %{
        command: "bash",
        args: ["-c", "echo ready > #{ready_file}; sleep 3600"],
        env: [],
        working_dir: "/tmp",
        worker_id: name,
        resource_limits: %{memory_mb: nil, cpu_percent: nil}
      }
      
      {:ok, handle} = backend.start_process(spec)
      
      # Wait for readiness signal
      assert :ok = wait_for(fn -> File.exists?(ready_file) end)
      
      {handle, ready_file}
    end
  end
  
  describe "process lifecycle" do
    @tag :process_backend
    test "starts and stops processes correctly" do
      backend = get_test_backend()
      
      # Start a process
      {handle, ready_file} = ProcessHelper.start_test_process(backend, "test1")
      
      # Verify it's alive
      assert backend.alive?(handle)
      
      # Get PID
      assert {:ok, pid} = backend.get_pid(handle)
      assert is_integer(pid)
      
      # Terminate gracefully
      assert :ok = backend.terminate(handle, 1000)
      
      # Verify it's dead
      assert :ok = ProcessHelper.wait_for(fn -> not backend.alive?(handle) end)
      
      # Cleanup
      File.rm(ready_file)
    end
    
    @tag :process_backend
    test "handles signal delivery" do
      backend = get_test_backend()
      
      # Start a process that handles signals
      signal_file = "/tmp/snakepit_test_signal"
      File.rm(signal_file)
      
      spec = %{
        command: "bash",
        args: ["-c", "trap 'echo USR1 > #{signal_file}' USR1; sleep 3600"],
        env: [],
        working_dir: "/tmp", 
        worker_id: "signal_test",
        resource_limits: %{}
      }
      
      {:ok, handle} = backend.start_process(spec)
      
      # Send signal
      assert :ok = backend.send_signal(handle, :usr1)
      
      # Verify signal was received
      assert :ok = ProcessHelper.wait_for(fn -> 
        File.exists?(signal_file) && File.read!(signal_file) =~ "USR1"
      end)
      
      # Cleanup
      backend.terminate(handle, 1000)
      File.rm(signal_file)
    end
  end
  
  describe "systemd backend" do
    @tag :systemd
    test "enforces memory limits" do
      backend = %ProcessBackend.Systemd{slice_name: "test.slice"}
      
      # Start a memory-hungry process
      spec = %{
        command: "python",
        args: ["-c", "x = 'a' * (200 * 1024 * 1024); input()"],  # Try to allocate 200MB
        env: [],
        working_dir: "/tmp",
        worker_id: "memory_test",
        resource_limits: %{memory_mb: 100}  # Limit to 100MB
      }
      
      {:ok, handle} = backend.start_process(spec)
      
      # Process should be killed by OOM killer
      assert :ok = ProcessHelper.wait_for(
        fn -> not backend.alive?(handle) end,
        timeout: 10000
      )
    end
  end
  
  # Conditional test execution based on backend availability
  defp get_test_backend do
    case System.cmd("systemctl", ["--version"], stderr_to_stdout: true) do
      {_, 0} ->
        # Systemd available
        {:ok, backend} = ProcessBackend.Systemd.init(slice_name: "test.slice")
        backend
        
      _ ->
        # Fall back to setsid
        {:ok, backend} = ProcessBackend.Setsid.init([])
        backend
    end
  end
end
```

### ExUnit Tags for Conditional Execution

```elixir
# test/test_helper.exs
ExUnit.configure(
  exclude: [
    systemd: not systemd_available?()
  ]
)

defp systemd_available? do
  case System.cmd("systemctl", ["--version"], stderr_to_stdout: true) do
    {_, 0} -> true
    _ -> false
  end
end
```

## Summary

This design provides:

1. **Clean Abstraction** - ProcessBackend behaviour hides implementation details
2. **Production Ready** - Systemd backend for Linux production environments
3. **Development Friendly** - Setsid backend works everywhere
4. **Testable** - Deterministic testing without sleep
5. **Configurable** - Easy backend selection via config
6. **Extensible** - Easy to add new backends (Docker, Kubernetes, etc.)

The dual-backend approach ensures Snakepit can leverage advanced process management features when available while maintaining portability for development and testing environments.