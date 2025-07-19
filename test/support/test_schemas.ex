defmodule DSPex.TestSchemas do
  @moduledoc """
  Test schemas for InstructorLite integration
  """

  defmodule SimpleResponse do
    use Ecto.Schema
    use InstructorLite.Instruction

    @doc """
    A simple response with a message and sentiment
    """
    @primary_key false
    embedded_schema do
      field(:message, :string)
      field(:sentiment, Ecto.Enum, values: [:positive, :negative, :neutral])
    end
  end

  defmodule MathProblem do
    use Ecto.Schema
    use InstructorLite.Instruction

    @doc """
    A math problem solution with steps
    """
    @primary_key false
    embedded_schema do
      field(:problem, :string)
      field(:solution, :float)
      field(:steps, {:array, :string})
      field(:explanation, :string)
    end
  end

  defmodule CodeExample do
    use Ecto.Schema
    use InstructorLite.Instruction

    @doc """
    A code example with explanation
    """
    @primary_key false
    embedded_schema do
      field(:language, :string)
      field(:code, :string)
      field(:explanation, :string)
      field(:complexity, Ecto.Enum, values: [:beginner, :intermediate, :advanced])
    end
  end
end
