defmodule ElixirML.Resource.DSL do
  @moduledoc """
  DSL macros for defining ElixirML resources.

  Provides a declarative interface for defining attributes, relationships,
  actions, and calculations on resources.
  """

  @doc """
  Defines the attributes section of a resource.
  """
  defmacro attributes(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Defines a simple attribute on the resource.

  ## Options
  - `:allow_nil?` - Whether the attribute can be nil (default: true)
  - `:default` - Default value for the attribute
  - `:constraints` - List of constraints to validate
  - `:variable` - Whether this attribute should be treated as a variable (default: false)
  """
  defmacro attribute(name, type, opts \\ []) do
    quote do
      @attributes {unquote(name), unquote(type), unquote(opts)}
    end
  end

  @doc """
  Defines a schema-based attribute that uses ElixirML.Schema for validation.

  ## Parameters
  - `name`: Attribute name
  - `schema_module`: ElixirML.Schema module to use for validation
  - `opts`: Additional options
  """
  defmacro schema_attribute(name, schema_module, opts \\ []) do
    quote do
      @schema_attributes {unquote(name), unquote(schema_module), unquote(opts)}
      @attributes {unquote(name), :schema,
                   [{:schema_module, unquote(schema_module)} | unquote(opts)]}
    end
  end

  @doc """
  Defines the relationships section of a resource.
  """
  defmacro relationships(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Defines a belongs_to relationship.
  """
  defmacro belongs_to(name, resource_module, opts \\ []) do
    quote do
      @relationships {:belongs_to, unquote(name), unquote(resource_module), unquote(opts)}
    end
  end

  @doc """
  Defines a has_many relationship.
  """
  defmacro has_many(name, resource_module, opts \\ []) do
    quote do
      @relationships {:has_many, unquote(name), unquote(resource_module), unquote(opts)}
    end
  end

  @doc """
  Defines a has_one relationship.
  """
  defmacro has_one(name, resource_module, opts \\ []) do
    quote do
      @relationships {:has_one, unquote(name), unquote(resource_module), unquote(opts)}
    end
  end

  @doc """
  Defines the actions section of a resource.
  """
  defmacro actions(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Defines a resource action.

  ## Parameters
  - `name`: Action name
  - `opts`: Action options
  - `block`: Action definition block
  """
  defmacro action(name, opts \\ [], do: block) do
    quote do
      @actions {unquote(name), unquote(opts), unquote(Macro.escape(block))}
    end
  end

  @doc """
  Defines an action argument.
  """
  defmacro argument(name, type, opts \\ []) do
    quote do
      # Action arguments are stored in the action context
      {unquote(name), unquote(type), unquote(opts)}
    end
  end

  @doc """
  Specifies the module to run for an action.
  """
  defmacro run(module) do
    quote do
      unquote(module)
    end
  end

  @doc """
  Defines the calculations section of a resource.
  """
  defmacro calculations(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Defines a resource calculation.
  """
  defmacro calculate(name, return_type, calculation_module, opts \\ []) do
    quote do
      @calculations {unquote(name), unquote(return_type), unquote(calculation_module),
                     unquote(opts)}
    end
  end

  @doc """
  Defines the validations section of a resource.
  """
  defmacro validations(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Defines a resource validation.
  """
  defmacro validation(name, opts \\ [], do: block) do
    quote do
      @validations {unquote(name), unquote(opts), unquote(Macro.escape(block))}
    end
  end
end
