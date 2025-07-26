defmodule DSPex.Bridge.ObservableTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Bridge.Behaviours
  
  describe "Observable behavior" do
    defmodule TestObservable do
      use DSPex.Bridge.SimpleWrapper
      use DSPex.Bridge.Observable
      
      wrap_dspy "test.Observable"
      
      @impl Behaviours.Observable
      def telemetry_metadata(:create, args) do
        %{test_meta: true, args: args}
      end
      
      @impl Behaviours.Observable
      def before_execute(:create, %{fail: true}) do
        {:error, :test_failure}
      end
      def before_execute(_op, _args), do: :ok
      
      @impl Behaviours.Observable
      def after_execute(:create, _args, result) do
        send(self(), {:after_execute, result})
        :ok
      end
    end
    
    test "implements Observable behaviour" do
      assert TestObservable.__info__(:attributes)[:behaviour] 
             |> Enum.member?(Behaviours.Observable)
    end
    
    test "tracks observable behavior" do
      behaviors = TestObservable.__dspex_behaviors__()
      assert :observable in behaviors
    end
    
    test "provides telemetry metadata" do
      metadata = TestObservable.telemetry_metadata(:create, %{test: true})
      assert metadata.test_meta == true
      assert metadata.args == %{test: true}
    end
    
    test "before_execute can prevent execution" do
      assert {:error, :test_failure} = TestObservable.before_execute(:create, %{fail: true})
      assert :ok = TestObservable.before_execute(:create, %{})
    end
    
    test "after_execute receives results" do
      TestObservable.after_execute(:create, %{}, {:ok, :test})
      assert_received {:after_execute, {:ok, :test}}
    end
  end
  
  describe "telemetry integration" do
    defmodule TelemetryTestWrapper do
      use DSPex.Bridge.SimpleWrapper
      use DSPex.Bridge.Observable
      
      wrap_dspy "test.TelemetryComponent"
      
      @impl Behaviours.Observable
      def telemetry_metadata(op, args) do
        %{operation: op, test_args: args}
      end
    end
    
    test "telemetry metadata is customizable" do
      meta = TelemetryTestWrapper.telemetry_metadata(:call, %{method: "test"})
      assert meta.operation == :call
      assert meta.test_args == %{method: "test"}
    end
  end
end