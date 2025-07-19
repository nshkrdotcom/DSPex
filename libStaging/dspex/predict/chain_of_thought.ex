defmodule DSPEx.Predict.ChainOfThought do
  @moduledoc """
  Chain of Thought reasoning module for DSPEx.

  This module implements the Chain of Thought pattern where the model is prompted
  to think step by step before providing an answer. It extends any signature by
  adding a rationale field that captures the reasoning process.

  ## Usage

      signature = MySignature  # question -> answer
      cot = ChainOfThought.new(signature)
      {:ok, result} = DSPEx.Program.forward(cot, %{question: "What is 2+2?"})
      
      # Result will have both:
      # result.rationale - step by step reasoning
      # result.answer - final answer

  ## How it works

  1. Takes any signature and extends it with a rationale field
  2. The rationale field is positioned before other output fields
  3. Uses "Let's think step by step." as the rationale description
  4. The underlying model generates reasoning in the rationale field first
  """

  alias DSPEx.Predict

  @doc """
  Create a new Chain of Thought program.

  ## Parameters

  - `signature` - The base signature to extend with Chain of Thought
  - `opts` - Options passed to the underlying adapter (model, temperature, etc.)

  ## Returns

  A Program struct configured for Chain of Thought reasoning.
  """
  @spec new(module(), keyword()) :: Predict.t()
  def new(signature, opts \\ []) do
    # Extract client from opts, default to :test for testing
    client = Keyword.get(opts, :client, :test)
    model = Keyword.get(opts, :model, client)

    # Create a special Chain of Thought signature
    cot_signature = create_cot_signature(signature)

    # Create custom instruction that encourages step-by-step reasoning
    instruction = build_cot_instruction(signature)
    opts_with_instruction = Keyword.put(opts, :instruction, instruction)

    # Create the Predict program
    Predict.new(cot_signature, model, opts_with_instruction)
  end

  # Create a CoT signature dynamically at runtime
  defp create_cot_signature(base_signature) do
    # Get the base signature's fields
    input_fields = base_signature.input_fields()
    output_fields = base_signature.output_fields()
    instructions = base_signature.instructions()

    # Create a simple module that includes rationale
    unique_id = :erlang.unique_integer([:positive]) |> Integer.to_string()
    defmodule_name = Module.concat([__MODULE__, "CoTSignature#{unique_id}"])

    contents =
      quote do
        @moduledoc unquote(instructions)
        use DSPEx.Signature,
            unquote(build_signature_string(input_fields, [:rationale | output_fields]))
      end

    Module.create(defmodule_name, contents, Macro.Env.location(__ENV__))
    defmodule_name
  end

  # Build signature string from field lists
  defp build_signature_string(inputs, outputs) do
    input_string = inputs |> Enum.join(", ")
    output_string = outputs |> Enum.join(", ")
    "#{input_string} -> #{output_string}"
  end

  # Build Chain of Thought instruction
  defp build_cot_instruction(signature) do
    base_instruction = signature.instructions()

    """
    #{base_instruction}

    Let's think step by step. First, provide your reasoning in the rationale field, then give your final answer.
    """
  end
end
