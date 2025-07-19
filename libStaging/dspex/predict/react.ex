defmodule DSPEx.Predict.ReAct do
  @moduledoc """
  ReAct (Reason + Act) module for DSPEx.

  This module implements the ReAct pattern where the model alternates between
  reasoning (thought), taking action (action), observing results (observation),
  and then providing a final answer. It extends any signature by adding
  thought, action, and observation fields for interactive reasoning with tools.

  ## Usage

      tools = [WebSearchTool, CalculatorTool]
      signature = MySignature  # question -> answer
      react = ReAct.new(signature, tools: tools)
      {:ok, result} = DSPEx.Program.forward(react, %{question: "What is the population of Tokyo?"})

      # Result will have:
      # result.thought - reasoning about what to do
      # result.action - action taken with tool
      # result.observation - result from tool execution
      # result.answer - final answer

  ## How it works

  1. Takes any signature and extends it with thought, action, observation fields
  2. The ReAct fields are positioned before other output fields
  3. Uses tools to perform actions based on reasoning
  4. The underlying model generates reasoning, actions, and observations iteratively
  """

  alias DSPEx.Predict

  @doc """
  Create a new ReAct program.

  ## Parameters

  - `signature` - The base signature to extend with ReAct
  - `opts` - Options including tools and adapter options (model, temperature, etc.)
    - `:tools` - List of tool modules that can be called (required)

  ## Returns

  A Program struct configured for ReAct reasoning and acting.

  ## Raises

  ArgumentError if tools parameter is not provided or empty.
  """
  @spec new(module(), keyword()) :: map()
  def new(signature, opts \\ []) do
    tools = Keyword.get(opts, :tools)

    unless is_list(tools) and length(tools) > 0 do
      raise ArgumentError, "ReAct requires at least one tool in :tools option"
    end

    # Extract client from opts, default to :test for testing
    client = Keyword.get(opts, :client, :test)
    model = Keyword.get(opts, :model, client)

    # Create a special ReAct signature
    react_signature = create_react_signature(signature)

    # Create custom instruction that encourages ReAct reasoning
    instruction = build_react_instruction(signature, tools)
    opts_with_instruction = Keyword.put(opts, :instruction, instruction)

    # Create the Predict program with tools attached
    predict_program = Predict.new(react_signature, model, opts_with_instruction)

    # Add tools to the program struct for reference
    Map.put(predict_program, :tools, tools)
  end

  # Create a ReAct signature dynamically at runtime
  defp create_react_signature(base_signature) do
    # Get the base signature's fields
    input_fields = base_signature.input_fields()
    output_fields = base_signature.output_fields()
    instructions = base_signature.instructions()

    # Create a simple module that includes ReAct fields
    unique_id = :erlang.unique_integer([:positive]) |> Integer.to_string()
    defmodule_name = Module.concat([__MODULE__, "ReActSignature#{unique_id}"])

    # ReAct fields: thought, action, observation, then original outputs
    react_fields = [:thought, :action, :observation]
    extended_outputs = react_fields ++ output_fields

    contents =
      quote do
        @moduledoc unquote(instructions)
        use DSPEx.Signature,
            unquote(build_signature_string(input_fields, extended_outputs))
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

  # Build ReAct instruction with tool descriptions
  defp build_react_instruction(signature, tools) do
    base_instruction = signature.instructions()
    tool_descriptions = build_tool_descriptions(tools)

    """
    #{base_instruction}

    You have access to the following tools:
    #{tool_descriptions}

    Use the ReAct (Reasoning and Acting) approach:
    1. THOUGHT: Think about what you need to do
    2. ACTION: Choose and use an appropriate tool
    3. OBSERVATION: Observe the results from the tool
    4. ANSWER: Provide your final answer based on your reasoning and observations

    Format your response with clear sections for each field.
    """
  end

  # Build descriptions of available tools
  defp build_tool_descriptions(tools) do
    tools
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {tool, index} ->
      tool_name = tool |> Module.split() |> List.last()
      "#{index}. #{tool_name}: #{get_tool_description(tool)}"
    end)
  end

  # Get tool description (fallback to module name if no description)
  defp get_tool_description(tool) do
    case function_exported?(tool, :description, 0) do
      true -> tool.description()
      false -> "Tool for #{tool |> Module.split() |> List.last() |> String.downcase()}"
    end
  end
end
