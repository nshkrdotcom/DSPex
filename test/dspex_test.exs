defmodule DSPexTest do
  use ExUnit.Case
  doctest DSPex

  describe "module structure" do
    test "DSPex module is loaded" do
      assert Code.ensure_loaded?(DSPex)
    end

    test "exports run/1" do
      assert function_exported?(DSPex, :run, 1)
    end

    test "exports lm/1 and lm/2" do
      assert function_exported?(DSPex, :lm, 1)
      assert function_exported?(DSPex, :lm, 2)
    end

    test "exports configure/0 and configure/1" do
      assert function_exported?(DSPex, :configure, 0)
      assert function_exported?(DSPex, :configure, 1)
    end

    test "exports predict/1 and predict/2" do
      assert function_exported?(DSPex, :predict, 1)
      assert function_exported?(DSPex, :predict, 2)
    end

    test "exports chain_of_thought/1 and chain_of_thought/2" do
      assert function_exported?(DSPex, :chain_of_thought, 1)
      assert function_exported?(DSPex, :chain_of_thought, 2)
    end

    test "exports call/2, call/3, call/4" do
      assert function_exported?(DSPex, :call, 2)
      assert function_exported?(DSPex, :call, 3)
      assert function_exported?(DSPex, :call, 4)
    end

    test "exports method/2, method/3, method/4" do
      assert function_exported?(DSPex, :method, 2)
      assert function_exported?(DSPex, :method, 3)
      assert function_exported?(DSPex, :method, 4)
    end

    test "exports attr/2" do
      assert function_exported?(DSPex, :attr, 2)
      assert function_exported?(DSPex, :attr, 3)
    end

    test "exports attr!/2 and attr!/3" do
      assert function_exported?(DSPex, :attr!, 2)
      assert function_exported?(DSPex, :attr!, 3)
    end

    test "exports set_attr/3 and set_attr/4" do
      assert function_exported?(DSPex, :set_attr, 3)
      assert function_exported?(DSPex, :set_attr, 4)
    end
  end

  describe "timeout helpers" do
    test "with_timeout/2 adds __runtime__ option" do
      opts = DSPex.with_timeout([], timeout: 5000)
      assert opts == [__runtime__: [timeout: 5000]]
    end

    test "with_timeout/2 merges with existing options" do
      opts = DSPex.with_timeout([question: "test"], timeout_profile: :batch_job)
      assert Keyword.get(opts, :question) == "test"
      assert Keyword.get(opts, :__runtime__) == [timeout_profile: :batch_job]
    end

    test "with_timeout/2 merges with existing __runtime__" do
      opts = DSPex.with_timeout([__runtime__: [foo: :bar]], timeout: 1000)
      assert opts == [__runtime__: [foo: :bar, timeout: 1000]]
    end

    test "timeout_profile/1 returns correct format" do
      assert DSPex.timeout_profile(:default) == [__runtime__: [timeout_profile: :default]]
      assert DSPex.timeout_profile(:streaming) == [__runtime__: [timeout_profile: :streaming]]

      assert DSPex.timeout_profile(:ml_inference) == [
               __runtime__: [timeout_profile: :ml_inference]
             ]

      assert DSPex.timeout_profile(:batch_job) == [__runtime__: [timeout_profile: :batch_job]]
    end

    test "timeout_ms/1 returns correct format" do
      assert DSPex.timeout_ms(5000) == [__runtime__: [timeout: 5000]]
      assert DSPex.timeout_ms(120_000) == [__runtime__: [timeout: 120_000]]
    end

    test "timeout_ms/1 requires positive integer" do
      assert_raise FunctionClauseError, fn ->
        DSPex.timeout_ms(0)
      end

      assert_raise FunctionClauseError, fn ->
        DSPex.timeout_ms(-100)
      end
    end

    test "timeout_profile/1 only accepts valid profiles" do
      assert_raise FunctionClauseError, fn ->
        DSPex.timeout_profile(:invalid)
      end
    end
  end
end
