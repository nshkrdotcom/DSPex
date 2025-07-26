defmodule DSPex.ToolsTest do
  use ExUnit.Case, async: false
  
  alias DSPex.Bridge.Tools.{Registry, Executor}
  alias DSPex.Tools
  
  # Define test tools in a module
  defmodule TestHelpers do
    def uppercase(%{"text" => text}), do: String.upcase(text)
    def add(%{"a" => a, "b" => b}), do: a + b
    def validate_email(%{"email" => email}), do: String.contains?(email, "@")
    def failing_tool(_args), do: raise "This tool always fails!"
    def slow_tool(%{"delay" => delay}) do
      Process.sleep(delay)
      {:ok, delay}
    end
  end
  
  setup do
    # Clear registry before each test
    Registry.clear()
    
    on_exit(fn ->
      Registry.clear()
    end)
    
    :ok
  end
  
  describe "Tool Registration" do
    test "registers a tool successfully" do
      assert :ok = Registry.register("test_tool", {TestHelpers, :uppercase}, %{
        description: "Test tool"
      })
      
      assert Registry.exists?("test_tool")
    end
    
    test "lists registered tools" do
      Registry.register("tool1", {TestHelpers, :uppercase}, %{description: "Tool 1"})
      Registry.register("tool2", {TestHelpers, :add}, %{description: "Tool 2"})
      
      tools = Registry.list()
      assert length(tools) == 2
      assert {"tool1", %{description: "Tool 1"}} in tools
      assert {"tool2", %{description: "Tool 2"}} in tools
    end
    
    test "unregisters tools" do
      Registry.register("temp_tool", {TestHelpers, :uppercase}, %{})
      assert Registry.exists?("temp_tool")
      
      assert :ok = Registry.unregister("temp_tool")
      refute Registry.exists?("temp_tool")
    end
  end
  
  describe "Tool Execution" do
    test "executes a simple tool" do
      Registry.register("uppercase", {TestHelpers, :uppercase}, %{})
      
      assert {:ok, "HELLO"} = Executor.execute("uppercase", %{"text" => "hello"}, %{
        session_id: "test"
      })
    end
    
    test "executes tool with multiple parameters" do
      Registry.register("add", {TestHelpers, :add}, %{})
      
      assert {:ok, 7} = Executor.execute("add", %{"a" => 3, "b" => 4}, %{
        session_id: "test"
      })
    end
    
    test "handles tool not found" do
      assert {:error, :not_found} = Executor.execute("nonexistent", %{}, %{
        session_id: "test"
      })
    end
    
    test "handles tool execution failure" do
      Registry.register("failing", {TestHelpers, :failing_tool}, %{})
      
      # Trap exits to prevent the test process from crashing
      Process.flag(:trap_exit, true)
      
      result = Executor.execute("failing", %{}, %{session_id: "test"})
      
      # The error should be caught and returned
      assert {:error, {:exception, {%RuntimeError{message: "This tool always fails!"}, _stacktrace}}} = result
      
      # Clean up any exit messages
      receive do
        {:EXIT, _pid, _reason} -> :ok
      after
        100 -> :ok
      end
    end
    
    test "enforces timeout" do
      Registry.register("slow", {TestHelpers, :slow_tool}, %{})
      
      assert {:error, :timeout} = Executor.execute("slow", %{"delay" => 1000}, %{
        session_id: "test",
        timeout: 100
      })
    end
    
    test "async execution returns task" do
      Registry.register("add", {TestHelpers, :add}, %{})
      
      assert {:ok, task} = Executor.execute("add", %{"a" => 1, "b" => 2}, %{
        session_id: "test",
        async: true
      })
      
      assert %Task{} = task
      assert {:ok, 3} = Task.await(task)
    end
  end
  
  describe "High-level Tools API" do
    test "register and call through Tools module" do
      # Can't use anonymous functions with Tools.register
      # because it needs to extract module/function
      assert {:error, _} = Tools.register("test", fn _ -> :ok end)
    end
    
    test "lists tools with namespace" do
      Registry.register("validation.email", {TestHelpers, :validate_email}, %{})
      Registry.register("validation.phone", {TestHelpers, :validate_email}, %{})
      Registry.register("transform.uppercase", {TestHelpers, :uppercase}, %{})
      
      validation_tools = Registry.list_namespace("validation")
      assert length(validation_tools) == 2
      
      transform_tools = Registry.list_namespace("transform")
      assert length(transform_tools) == 1
    end
  end
  
  describe "Telemetry" do
    test "emits telemetry events" do
      :telemetry.attach(
        "test-handler",
        [:dspex, :tools, :execute, :start],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_start, event, measurements, metadata})
        end,
        nil
      )
      
      :telemetry.attach(
        "test-handler-stop",
        [:dspex, :tools, :execute, :stop],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_stop, event, measurements, metadata})
        end,
        nil
      )
      
      Registry.register("test", {TestHelpers, :uppercase}, %{})
      Executor.execute("test", %{"text" => "hello"}, %{session_id: "telemetry-test"})
      
      assert_receive {:telemetry_start, [:dspex, :tools, :execute, :start], %{system_time: _}, metadata}
      assert metadata.tool_name == "test"
      assert metadata.session_id == "telemetry-test"
      
      assert_receive {:telemetry_stop, [:dspex, :tools, :execute, :stop], measurements, metadata}
      assert measurements.duration > 0
      assert metadata.result_type == :string
      
      :telemetry.detach("test-handler")
      :telemetry.detach("test-handler-stop")
    end
  end
end