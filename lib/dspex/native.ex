defmodule DSPex.Native do
  @moduledoc """
  Namespace for native Elixir implementations that can be called
  from Python DSPy code through the bidirectional tool bridge.
  """

  # Re-export commonly used modules
  defdelegate parse(signature), to: DSPex.Native.Signature
  defdelegate validate(signature), to: DSPex.Native.Signature
  defdelegate render(template, context), to: DSPex.Native.Template
  defdelegate compile(template), to: DSPex.Native.Template

  @doc """
  Convenience function for signature validation tool.
  """
  def validate_signature(params) when is_map(params) do
    signature = Map.get(params, "signature", "")

    case DSPex.Native.Signature.validate(signature) do
      {:ok, analysis} -> analysis
      {:error, errors} -> %{valid: false, errors: errors}
    end
  end

  @doc """
  Convenience function for template processing tool.
  """
  def process_template(params) when is_map(params) do
    template = Map.get(params, "template", "")
    variables = Map.get(params, "variables", %{})

    try do
      result = DSPex.Native.Template.render(template, variables)
      %{success: true, processed_template: result}
    rescue
      error -> %{success: false, error: "Template processing failed: #{inspect(error)}"}
    end
  end
end
