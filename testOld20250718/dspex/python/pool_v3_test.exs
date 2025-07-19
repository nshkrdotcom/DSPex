defmodule DSPex.Python.PoolV3Test do
  use ExUnit.Case, async: false

  @moduletag :pool_v3

  setup do
    # Start V3 components
    start_supervised!(DSPex.Python.Registry)
    start_supervised!(DSPex.Python.WorkerSupervisor)
    start_supervised!({DSPex.Python.Pool, size: 2})

    :ok
  end

  test "pool starts with concurrent workers" do
    stats = DSPex.Python.Pool.get_stats()
    assert stats.workers == 2
    assert stats.available == 2
  end

  test "executes commands on workers" do
    assert {:ok, %{"pong" => true}} =
             DSPex.Python.Pool.execute(:ping, %{test: true})
  end

  test "handles concurrent requests" do
    tasks =
      for i <- 1..10 do
        Task.async(fn ->
          DSPex.Python.Pool.execute(:ping, %{id: i})
        end)
      end

    results = Task.await_many(tasks)
    assert length(results) == 10
    assert Enum.all?(results, &match?({:ok, _}, &1))
  end
end
