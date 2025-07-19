defmodule PoolExampleTest do
  use ExUnit.Case
  doctest PoolExample

  test "pool example functions exist" do
    assert function_exported?(PoolExample, :run_session_affinity_test, 0)
    assert function_exported?(PoolExample, :run_anonymous_operations_test, 0)
    assert function_exported?(PoolExample, :run_concurrent_stress_test, 1)
    assert function_exported?(PoolExample, :run_error_recovery_test, 0)
    assert function_exported?(PoolExample, :run_all_tests, 0)
  end
end