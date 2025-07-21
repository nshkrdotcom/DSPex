defmodule ElixirML.Resources.Schemas do
  @moduledoc """
  Schema definitions for ElixirML resources.

  This module contains schema definitions used by the resource framework
  to validate and structure data.
  """

  # Basic schemas for common data structures
  defmodule ProgramSignatureConfig do
    @moduledoc "Schema for program signature configuration"

    @spec validate(term()) :: {:ok, map()} | {:error, String.t()}
    def validate(data) when is_map(data) do
      {:ok, data}
    end

    def validate(_), do: {:error, "must be a map"}
  end

  defmodule ProgramConfig do
    @moduledoc "Schema for program configuration"

    @spec validate(term()) :: {:ok, map()} | {:error, String.t()}
    def validate(data) when is_map(data) do
      {:ok, data}
    end

    def validate(_), do: {:error, "must be a map"}
  end

  defmodule PerformanceMetrics do
    @moduledoc "Schema for performance metrics"

    @spec validate(term()) :: {:ok, map()} | {:error, String.t()}
    def validate(data) when is_map(data) do
      {:ok, data}
    end

    def validate(_), do: {:error, "must be a map"}
  end

  # Variable-related schemas
  defmodule VariableDefinitions do
    @moduledoc "Schema for variable definitions"

    @spec validate(term()) :: {:ok, list()} | {:error, String.t()}
    def validate(data) when is_list(data) do
      {:ok, data}
    end

    def validate(_), do: {:error, "must be a list"}
  end

  defmodule VariableConstraints do
    @moduledoc "Schema for variable constraints"

    @spec validate(term()) :: {:ok, map()} | {:error, String.t()}
    def validate(data) when is_map(data) do
      {:ok, data}
    end

    def validate(_), do: {:error, "must be a map"}
  end

  defmodule OptimizationHints do
    @moduledoc "Schema for optimization hints"

    @spec validate(term()) :: {:ok, map()} | {:error, String.t()}
    def validate(data) when is_map(data) do
      {:ok, data}
    end

    def validate(_), do: {:error, "must be a map"}
  end

  defmodule VariableValues do
    @moduledoc "Schema for variable values"

    @spec validate(term()) :: {:ok, map()} | {:error, String.t()}
    def validate(data) when is_map(data) do
      {:ok, data}
    end

    def validate(_), do: {:error, "must be a map"}
  end

  defmodule ConfigurationMetadata do
    @moduledoc "Schema for configuration metadata"

    @spec validate(term()) :: {:ok, map()} | {:error, String.t()}
    def validate(data) when is_map(data) do
      {:ok, data}
    end

    def validate(_), do: {:error, "must be a map"}
  end

  # Optimization-related schemas
  defmodule OptimizationConfig do
    @moduledoc "Schema for optimization configuration"

    @spec validate(term()) :: {:ok, map()} | {:error, String.t()}
    def validate(data) when is_map(data) do
      {:ok, data}
    end

    def validate(_), do: {:error, "must be a map"}
  end

  defmodule OptimizationResults do
    @moduledoc "Schema for optimization results"

    @spec validate(term()) :: {:ok, map()} | {:error, String.t()}
    def validate(data) when is_map(data) do
      {:ok, data}
    end

    def validate(_), do: {:error, "must be a map"}
  end

  # Execution-related schemas
  defmodule ExecutionInputs do
    @moduledoc "Schema for execution inputs"

    @spec validate(term()) :: {:ok, map()} | {:error, String.t()}
    def validate(data) when is_map(data) do
      {:ok, data}
    end

    def validate(_), do: {:error, "must be a map"}
  end

  defmodule ExecutionOutputs do
    @moduledoc "Schema for execution outputs"

    @spec validate(term()) :: {:ok, map()} | {:error, String.t()}
    def validate(data) when is_map(data) do
      {:ok, data}
    end

    def validate(_), do: {:error, "must be a map"}
  end

  defmodule ExecutionMetrics do
    @moduledoc "Schema for execution metrics"

    @spec validate(term()) :: {:ok, map()} | {:error, String.t()}
    def validate(data) when is_map(data) do
      {:ok, data}
    end

    def validate(_), do: {:error, "must be a map"}
  end

  # Helper functions
  @spec valid_field_definitions?(term()) :: boolean()
  def valid_field_definitions?(fields) when is_list(fields) do
    Enum.all?(fields, fn field ->
      Map.has_key?(field, "name") and Map.has_key?(field, "type")
    end)
  end

  def valid_field_definitions?(_), do: false
end
