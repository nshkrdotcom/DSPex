defmodule DSPEx.TypedSignature do
  @moduledoc """
  TDD Cycle 2B.1: Type-Safe Signatures Implementation

  Provides runtime type validation and constraint checking for DSPEx signatures.
  Extends the basic signature system with comprehensive type safety, coercion
  capabilities, and detailed error reporting using Sinter validation.

  Following the TDD Master Reference Phase 2 specifications.
  """

  @doc """
  Macro to add runtime type validation to a DSPEx signature.

  ## Options
  - `:coercion` - Enable automatic type coercion (default: false)
  - `:strict` - Disable coercion and require exact types (default: false)
  - `:error_messages` - Custom error message overrides

  ## Example
      defmodule MySignature do
        use DSPEx.Signature, "name:string[min_length=1] -> greeting:string[max_length=100]"
        use DSPEx.TypedSignature, coercion: true
      end
  """
  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      @typed_signature_opts opts

      @doc """
      Validates input data against the signature's input field types and constraints.

      Returns `{:ok, validated_data}` on success or `{:error, errors}` on failure.
      """
      def validate_input(data) when is_map(data) do
        DSPEx.Signature.Sinter.validate_with_sinter(__MODULE__, data,
          field_type: :inputs,
          strict: Keyword.get(@typed_signature_opts, :strict, false)
        )
      end

      @doc """
      Validates output data against the signature's output field types and constraints.

      Returns `{:ok, validated_data}` on success or `{:error, errors}` on failure.
      """
      def validate_output(data) when is_map(data) do
        DSPEx.Signature.Sinter.validate_with_sinter(__MODULE__, data,
          field_type: :outputs,
          strict: Keyword.get(@typed_signature_opts, :strict, false)
        )
      end

      @doc """
      Returns the typed signature configuration options.
      """
      def __typed_signature_opts__, do: @typed_signature_opts
    end
  end
end
