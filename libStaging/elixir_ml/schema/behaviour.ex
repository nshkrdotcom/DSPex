defmodule ElixirML.Schema.Behaviour do
  @moduledoc """
  Behaviour definition for ElixirML schema modules.
  """

  @callback validate(data :: map()) ::
              {:ok, map()} | {:error, ElixirML.Schema.ValidationError.t()}
  @callback to_json_schema() :: map()
  @callback __fields__() :: list()
  @callback __variables__() :: list()
  @callback __metadata__() :: map()
end
