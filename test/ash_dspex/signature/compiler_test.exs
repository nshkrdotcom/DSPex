defmodule AshDSPex.Signature.CompilerTest do
  use ExUnit.Case
  doctest AshDSPex.Signature.Compiler

  alias AshDSPex.Signature.Compiler

  describe "AST parsing" do
    test "parses simple signature AST" do
      # Manually construct the AST since arrow syntax is problematic in quote
      ast = {:->, [], [[{:question, :string}], [{:answer, :string}]]}

      {:ok, {inputs, outputs}} = Compiler.parse_signature_ast(ast)

      assert inputs == [{:question, :string, []}]
      assert outputs == [{:answer, :string, []}]
    end

    test "parses multi-field signature AST" do
      # Manually construct multi-field AST
      ast =
        {:->, [],
         [
           [{:query, :string}, {:context, :string}],
           [{:answer, :string}, {:confidence, :float}]
         ]}

      {:ok, {inputs, outputs}} = Compiler.parse_signature_ast(ast)

      assert inputs == [
               {:query, :string, []},
               {:context, :string, []}
             ]

      assert outputs == [
               {:answer, :string, []},
               {:confidence, :float, []}
             ]
    end

    test "parses complex types" do
      ast =
        {:->, [],
         [
           [{:items, {:list, :string}}],
           [{:results, {:dict, :string, :integer}}]
         ]}

      {:ok, {inputs, outputs}} = Compiler.parse_signature_ast(ast)

      assert inputs == [{:items, {:list, :string}, []}]
      assert outputs == [{:results, {:dict, :string, :integer}, []}]
    end

    test "rejects invalid AST structure" do
      invalid_ast = quote do: invalid_syntax

      {:error, reason} = Compiler.parse_signature_ast(invalid_ast)
      assert reason =~ "Invalid signature syntax"
    end

    test "rejects invalid field definitions" do
      # Field name is not an atom - use manually constructed AST
      ast =
        {:->, [],
         [
           [{"invalid_name", :string}],
           [{:answer, :string}]
         ]}

      {:error, reason} = Compiler.parse_signature_ast(ast)
      assert reason =~ "Invalid field definition"
    end

    test "rejects unsupported types" do
      ast =
        {:->, [],
         [
           [{:question, :unsupported_type}],
           [{:answer, :string}]
         ]}

      {:error, reason} = Compiler.parse_signature_ast(ast)
      assert reason =~ "Invalid type for field question"
    end
  end

  describe "signature compilation" do
    test "compiles valid signature successfully" do
      ast = {:->, [], [[{:question, :string}], [{:answer, :string}]]}

      {:ok, quoted_code} = Compiler.compile_signature(ast, TestModule)

      # Should return quoted code that can be evaluated
      assert is_tuple(quoted_code)
      assert elem(quoted_code, 0) == :__block__
    end

    test "fails compilation for invalid types" do
      ast = {:->, [], [[{:question, :invalid_type}], [{:answer, :string}]]}

      {:error, reason} = Compiler.compile_signature(ast, TestModule)
      assert reason =~ "Invalid type"
    end

    test "fails compilation for malformed AST" do
      ast = :invalid_ast

      {:error, reason} = Compiler.compile_signature(ast, TestModule)
      assert reason =~ "Invalid signature syntax"
    end
  end

  describe "generated code structure" do
    # We can't easily test the exact generated code without complex AST manipulation,
    # but we can test that the compilation process works through integration tests
    # in the main signature test file. Here we focus on the compilation logic itself.

    test "compilation produces expected metadata structure" do
      ast =
        {:->, [],
         [
           [{:question, :string}, {:context, {:list, :string}}],
           [{:answer, :string}, {:confidence, :float}]
         ]}

      {:ok, _quoted_code} = Compiler.compile_signature(ast, TestModule)

      # The actual metadata testing is done in signature_test.exs through
      # modules that actually use the compiled code
    end
  end

  describe "field parsing edge cases" do
    test "handles single input single output" do
      ast = {:->, [], [[{:input, :string}], [{:output, :string}]]}

      {:ok, {inputs, outputs}} = Compiler.parse_signature_ast(ast)

      assert length(inputs) == 1
      assert length(outputs) == 1
    end

    test "handles multiple inputs single output" do
      ast =
        {:->, [],
         [
           [{:a, :string}, {:b, :integer}],
           [{:result, :float}]
         ]}

      {:ok, {inputs, outputs}} = Compiler.parse_signature_ast(ast)

      assert length(inputs) == 2
      assert length(outputs) == 1
    end

    test "handles single input multiple outputs" do
      ast =
        {:->, [],
         [
           [{:input, :string}],
           [{:a, :string}, {:b, :integer}, {:c, :float}]
         ]}

      {:ok, {inputs, outputs}} = Compiler.parse_signature_ast(ast)

      assert length(inputs) == 1
      assert length(outputs) == 3
    end

    test "preserves field order" do
      ast =
        {:->, [],
         [
           [{:first, :string}, {:second, :integer}, {:third, :float}],
           [{:alpha, :string}, {:beta, :integer}]
         ]}

      {:ok, {inputs, outputs}} = Compiler.parse_signature_ast(ast)

      assert elem(Enum.at(inputs, 0), 0) == :first
      assert elem(Enum.at(inputs, 1), 0) == :second
      assert elem(Enum.at(inputs, 2), 0) == :third

      assert elem(Enum.at(outputs, 0), 0) == :alpha
      assert elem(Enum.at(outputs, 1), 0) == :beta
    end
  end

  describe "type validation during compilation" do
    test "accepts all basic types" do
      basic_types = [:string, :integer, :float, :boolean, :atom, :any, :map]

      for type <- basic_types do
        ast = {:->, [], [[{:input, type}], [{:output, :string}]]}
        assert {:ok, _} = Compiler.parse_signature_ast(ast)
      end
    end

    test "accepts all ML types" do
      ml_types = [:embedding, :probability, :confidence_score, :reasoning_chain]

      for type <- ml_types do
        ast = {:->, [], [[{:input, type}], [{:output, :string}]]}
        assert {:ok, _} = Compiler.parse_signature_ast(ast)
      end
    end

    test "accepts composite types" do
      composite_types = [
        {:list, :string},
        {:dict, :string, :integer},
        {:union, [:string, :integer]}
      ]

      for type <- composite_types do
        ast = {:->, [], [[{:input, type}], [{:output, :string}]]}
        assert {:ok, _} = Compiler.parse_signature_ast(ast)
      end
    end

    test "rejects nested invalid types" do
      ast = {:->, [], [[{:input, {:list, :invalid_type}}], [{:output, :string}]]}

      {:error, reason} = Compiler.parse_signature_ast(ast)
      assert reason =~ "Invalid type"
    end
  end

  describe "error message quality" do
    test "provides helpful error for invalid AST" do
      ast = :not_a_proper_ast

      {:error, reason} = Compiler.parse_signature_ast(ast)
      assert reason =~ "Invalid signature syntax"
      assert reason =~ "Expected:"
    end

    test "provides helpful error for invalid field name" do
      # We can't easily test this with quote since 123: would be invalid syntax
      # Instead we test with a manually constructed AST
      ast = {:->, [], [[{123, :string}], [{:output, :string}]]}

      {:error, reason} = Compiler.parse_signature_ast(ast)
      assert reason =~ "Invalid field definition"
    end

    test "provides helpful error for invalid type" do
      ast = {:->, [], [[{:input, :non_existent_type}], [{:output, :string}]]}

      {:error, reason} = Compiler.parse_signature_ast(ast)
      assert reason =~ "Invalid type for field input"
      assert reason =~ "Unsupported type"
    end
  end
end
