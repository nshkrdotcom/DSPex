defmodule ElixirML.Schema.Definition do
  @moduledoc """
  Schema definition behavior for ElixirML schemas.
  Provides compile-time schema generation and validation.
  """

  defmacro __using__(_opts) do
    quote do
      import ElixirML.Schema.DSL

      # Module attributes for schema metadata
      Module.register_attribute(__MODULE__, :fields, accumulate: true)
      Module.register_attribute(__MODULE__, :validations, accumulate: true)
      Module.register_attribute(__MODULE__, :transforms, accumulate: true)
      Module.register_attribute(__MODULE__, :variables, accumulate: true)
      Module.register_attribute(__MODULE__, :metadata, accumulate: false)

      @behaviour ElixirML.Schema.Behaviour

      # Initialize metadata
      @metadata %{}
    end
  end

  @callback validate(data :: map()) ::
              {:ok, map()} | {:error, ElixirML.Schema.ValidationError.t()}
  @callback to_json_schema() :: map()
  @callback __fields__() :: list()
  @callback __variables__() :: list()
end
