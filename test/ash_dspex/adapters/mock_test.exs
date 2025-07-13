defmodule AshDSPex.Adapters.MockTest do
  use ExUnit.Case, async: true

  alias AshDSPex.Adapters.Mock

  setup do
    # Start the mock adapter for each test (handle already_started case)
    case Mock.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    on_exit(fn ->
      # Reset the mock state after each test
      try do
        Mock.reset()
      catch
        # Process might already be stopped
        :exit, _ -> :ok
      end
    end)

    :ok
  end

  test "ping returns successful response" do
    assert {:ok, result} = Mock.ping()
    assert %{status: "ok", adapter: "mock"} = result
    assert is_binary(result.timestamp)
  end

  test "create_program stores program with signature" do
    signature = %{
      "inputs" => [%{"name" => "question", "type" => "string"}],
      "outputs" => [%{"name" => "answer", "type" => "string"}]
    }

    program_config = %{id: "test_program", signature: signature}

    assert {:ok, program_id} = Mock.create_program(program_config)
    assert program_id == "test_program"

    # Verify program was stored
    programs = Mock.get_programs()
    assert Map.has_key?(programs, "test_program")
    assert programs["test_program"].signature == signature
  end

  test "execute_program generates deterministic mock responses" do
    signature = %{
      "inputs" => [%{"name" => "question", "type" => "string"}],
      "outputs" => [%{"name" => "answer", "type" => "string"}]
    }

    {:ok, _} = Mock.create_program(%{id: "qa_program", signature: signature})

    inputs = %{"question" => "What is the capital of France?"}

    # First execution
    assert {:ok, result1} = Mock.execute_program("qa_program", inputs)
    assert Map.has_key?(result1, "answer")
    assert is_binary(result1["answer"])

    # Second execution with same inputs should return same result
    assert {:ok, result2} = Mock.execute_program("qa_program", inputs)
    assert result1 == result2

    # Different inputs should return different result
    different_inputs = %{"question" => "What is 2+2?"}
    assert {:ok, result3} = Mock.execute_program("qa_program", different_inputs)
    assert result3 != result1
  end

  test "list_programs returns all created programs" do
    signature1 = %{"inputs" => [], "outputs" => [%{"name" => "result", "type" => "string"}]}

    signature2 = %{
      "inputs" => [%{"name" => "x", "type" => "int"}],
      "outputs" => [%{"name" => "y", "type" => "int"}]
    }

    {:ok, _} = Mock.create_program(%{id: "prog1", signature: signature1})
    {:ok, _} = Mock.create_program(%{id: "prog2", signature: signature2})

    assert {:ok, program_ids} = Mock.list_programs()
    assert length(program_ids) == 2
    assert "prog1" in program_ids
    assert "prog2" in program_ids
  end

  test "get_program_info returns program details" do
    signature = %{"inputs" => [], "outputs" => []}
    {:ok, _} = Mock.create_program(%{id: "info_test", signature: signature})

    assert {:ok, program_info} = Mock.get_program_info("info_test")
    assert program_info.id == "info_test"
    assert program_info.signature == signature
    assert program_info.executions == 0
  end

  test "delete_program removes program" do
    signature = %{"inputs" => [], "outputs" => []}
    {:ok, _} = Mock.create_program(%{id: "delete_test", signature: signature})

    # Verify program exists
    assert {:ok, _} = Mock.get_program_info("delete_test")

    # Delete program
    assert :ok = Mock.delete_program("delete_test")

    # Verify program is gone
    assert {:error, _} = Mock.get_program_info("delete_test")
  end

  test "statistics tracking works correctly" do
    {:ok, initial_stats} = Mock.get_stats()
    assert initial_stats.programs_created == 0
    assert initial_stats.executions_run == 0

    # Create a program
    signature = %{"inputs" => [], "outputs" => [%{"name" => "result", "type" => "string"}]}
    {:ok, _} = Mock.create_program(%{id: "stats_test", signature: signature})

    {:ok, stats_after_create} = Mock.get_stats()
    assert stats_after_create.programs_created == 1
    assert stats_after_create.active_programs == 1

    # Execute the program
    {:ok, _} = Mock.execute_program("stats_test", %{})

    {:ok, stats_after_execution} = Mock.get_stats()
    assert stats_after_execution.executions_run == 1
    assert stats_after_execution.total_executions == 1
  end

  test "concurrent operations work correctly" do
    signature = %{
      "inputs" => [%{"name" => "input", "type" => "string"}],
      "outputs" => [%{"name" => "output", "type" => "string"}]
    }

    {:ok, _} = Mock.create_program(%{id: "concurrent_test", signature: signature})

    # Run multiple concurrent executions
    tasks =
      Enum.map(1..10, fn i ->
        Task.async(fn ->
          inputs = %{"input" => "test_#{i}"}
          Mock.execute_program("concurrent_test", inputs)
        end)
      end)

    results = Task.await_many(tasks, 5000)

    # All should succeed
    assert Enum.all?(results, fn result -> match?({:ok, _}, result) end)

    # Should have unique results for different inputs
    outputs = Enum.map(results, fn {:ok, result} -> result["output"] end)
    assert length(Enum.uniq(outputs)) == 10
  end

  test "reset clears all state" do
    # Create some state
    signature = %{"inputs" => [], "outputs" => []}
    {:ok, _} = Mock.create_program(%{id: "reset_test", signature: signature})
    {:ok, _} = Mock.execute_program("reset_test", %{})

    # Verify state exists
    {:ok, stats} = Mock.get_stats()
    assert stats.programs_created > 0
    assert stats.executions_run > 0

    programs = Mock.get_programs()
    assert map_size(programs) > 0

    # Reset
    Mock.reset()

    # Verify state is cleared
    {:ok, new_stats} = Mock.get_stats()
    assert new_stats.programs_created == 0
    assert new_stats.executions_run == 0

    new_programs = Mock.get_programs()
    assert map_size(new_programs) == 0
  end
end
