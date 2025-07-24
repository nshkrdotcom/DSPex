defmodule DSPexTest do
  use ExUnit.Case

  doctest DSPex

  describe "signature/1" do
    test "parses simple signatures" do
      assert {:ok, sig} = DSPex.signature("question -> answer")
      assert sig.inputs == [%{name: :question, type: :string, description: nil}]
      assert sig.outputs == [%{name: :answer, type: :string, description: nil}]
    end

    test "handles map-based signatures" do
      spec = %{
        inputs: [%{name: :text, type: :string}],
        outputs: [%{name: :summary, type: :string}]
      }

      assert {:ok, sig} = DSPex.signature(spec)
      assert length(sig.inputs) == 1
      assert length(sig.outputs) == 1
    end
  end

  describe "compile_signature/1" do
    test "compiles signatures for performance" do
      assert {:ok, compiled} = DSPex.compile_signature("input: str -> output: str")
      assert is_map(compiled)
      assert Map.has_key?(compiled, :validator)
    end
  end

  describe "validate/2" do
    test "validates data against signatures" do
      {:ok, sig} = DSPex.signature("name: str, age: int -> greeting: str")

      assert :ok = DSPex.validate(%{name: "Alice", age: 30}, sig)
      assert {:error, errors} = DSPex.validate(%{name: "Alice"}, sig)
      assert is_list(errors)
    end
  end

  describe "render_template/2" do
    test "renders templates with context" do
      template = "Hello <%= @name %>!"
      result = DSPex.render_template(template, %{name: "World"})
      assert result == "Hello World!"
    end
  end

  describe "pipeline/1" do
    test "creates pipeline structure" do
      steps = [
        {:native, DSPex.Native.Template, template: "test"}
      ]

      pipeline = DSPex.pipeline(steps)

      assert %DSPex.Pipeline{} = pipeline
      assert pipeline.steps == steps
    end
  end

  describe "health_check/0" do
    test "returns system status" do
      status = DSPex.health_check()

      assert status.status == :ok
      assert status.version == "0.1.0"
      assert is_map(status.snakepit_status)
      assert is_list(status.native_modules)
    end
  end
end
