defmodule ElixirML.Schema.Runtime do
  @moduledoc """
  Runtime schema creation and validation for dynamic schemas.
  Useful for cases where schemas need to be created at runtime.
  """

  alias ElixirML.Schema.Types

  @enforce_keys [:fields]
  defstruct [
    :name,
    :fields,
    :validations,
    :transforms,
    :metadata
  ]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          fields: list(),
          validations: list(),
          transforms: list(),
          metadata: map()
        }

  @doc """
  Validate data against a runtime schema.
  """
  @spec validate(t(), map()) :: {:ok, map()} | {:error, ElixirML.Schema.ValidationError.t()}
  def validate(%__MODULE__{} = schema, data) do
    with {:ok, validated} <- validate_fields(schema, data),
         {:ok, transformed} <- apply_transforms(schema, validated),
         {:ok, final} <- apply_validations(schema, transformed) do
      {:ok, final}
    else
      {:error, reason} ->
        {:error,
         %ElixirML.Schema.ValidationError{
           message: reason,
           schema: __MODULE__,
           data: data
         }}
    end
  end

  @doc """
  Extract variables from a runtime schema.
  """
  @spec extract_variables(t()) :: list()
  def extract_variables(%__MODULE__{fields: fields}) do
    Enum.filter(fields, fn {_name, _type, opts} ->
      Keyword.get(opts, :variable, false)
    end)
  end

  @doc """
  Convert runtime schema to JSON schema with optional provider optimization.
  """
  @spec to_json_schema(t(), keyword()) :: map()
  def to_json_schema(%__MODULE__{fields: fields, metadata: metadata}, opts \\ []) do
    provider = Keyword.get(opts, :provider, :generic)
    include_descriptions = Keyword.get(opts, :include_descriptions, true)

    properties =
      Enum.reduce(fields, %{}, fn {name, type, opts_field}, acc ->
        field_schema = %{
          "type" => json_type_for(type),
          "x-elixir-type" => type
        }

        # Add description if enabled
        field_schema =
          if include_descriptions do
            description = Keyword.get(opts_field, :description, "")
            Map.put(field_schema, "description", description)
          else
            field_schema
          end

        # Add type-specific constraints
        field_schema = add_type_constraints(field_schema, type, opts_field)

        Map.put(acc, to_string(name), field_schema)
      end)

    required_fields =
      fields
      |> Enum.filter(fn {_name, _type, opts} -> Keyword.get(opts, :required, false) end)
      |> Enum.map(fn {name, _type, _opts} -> to_string(name) end)

    base_schema = %{
      "type" => "object",
      "properties" => properties,
      "required" => required_fields,
      "additionalProperties" => false
    }

    # Add description if present in metadata
    base_schema =
      case metadata do
        %{description: desc} when is_binary(desc) and desc != "" ->
          Map.put(base_schema, "description", desc)

        _ ->
          base_schema
      end

    # Add metadata if present
    base_schema =
      if metadata && map_size(metadata) > 0 do
        Map.put(base_schema, "metadata", metadata)
      else
        base_schema
      end

    # Apply provider-specific optimizations
    apply_provider_optimizations(base_schema, provider)
  end

  # Private validation functions

  defp validate_fields(%__MODULE__{fields: fields}, data) do
    Enum.reduce_while(fields, {:ok, data}, fn {name, type, opts}, {:ok, acc_data} ->
      case validate_field(name, type, opts, acc_data) do
        {:ok, updated_data} -> {:cont, {:ok, updated_data}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_field(name, type, opts, data) do
    required = Keyword.get(opts, :required, false)
    default = Keyword.get(opts, :default)

    case Map.get(data, name) do
      nil when required ->
        {:error, "Field #{name} is required"}

      nil ->
        # Use default if provided
        case default do
          nil -> {:ok, data}
          default_value -> {:ok, Map.put(data, name, default_value)}
        end

      value ->
        case Types.validate_type(value, type) do
          {:ok, validated_value} ->
            {:ok, Map.put(data, name, validated_value)}

          {:error, reason} ->
            {:error, "Field #{name}: #{reason}"}
        end
    end
  end

  defp apply_transforms(%__MODULE__{transforms: transforms}, data) do
    Enum.reduce_while(transforms, {:ok, data}, fn {_name, transform_fn}, {:ok, acc_data} ->
      case apply_transform(transform_fn, acc_data) do
        {:ok, transformed} -> {:cont, {:ok, transformed}}
        {:error, reason} -> {:halt, {:error, reason}}
        # Assume success
        transformed -> {:cont, {:ok, transformed}}
      end
    end)
  end

  defp apply_transform(transform_fn, data) when is_function(transform_fn, 1) do
    transform_fn.(data)
  rescue
    e -> {:error, "Transform failed: #{Exception.message(e)}"}
  end

  defp apply_validations(%__MODULE__{validations: validations}, data) do
    Enum.reduce_while(validations, {:ok, data}, fn {_name, validation_fn}, {:ok, acc_data} ->
      case apply_validation(validation_fn, acc_data) do
        {:ok, _} -> {:cont, {:ok, acc_data}}
        {:error, reason} -> {:halt, {:error, reason}}
        true -> {:cont, {:ok, acc_data}}
        false -> {:halt, {:error, "Validation failed"}}
        # Assume success
        _ -> {:cont, {:ok, acc_data}}
      end
    end)
  end

  defp apply_validation(validation_fn, data) when is_function(validation_fn, 1) do
    validation_fn.(data)
  rescue
    e -> {:error, "Validation failed: #{Exception.message(e)}"}
  end

  # Helper functions

  defp add_type_constraints(field_schema, :embedding, opts) do
    dimension = Keyword.get(opts, :dimension, 768)

    Map.merge(field_schema, %{
      "type" => "array",
      "items" => %{"type" => "number"},
      "minItems" => dimension,
      "maxItems" => dimension,
      "x-constraints" => %{"dimension" => dimension}
    })
  end

  defp add_type_constraints(field_schema, :probability, _opts) do
    Map.merge(field_schema, %{
      "type" => "number",
      "minimum" => 0.0,
      "maximum" => 1.0
    })
  end

  defp add_type_constraints(field_schema, :confidence_score, _opts) do
    Map.merge(field_schema, %{
      "type" => "number",
      "minimum" => 0.0
    })
  end

  defp add_type_constraints(field_schema, :token_list, opts) do
    base_constraints = %{
      "type" => "array",
      "items" => %{
        "oneOf" => [
          %{"type" => "string"},
          %{"type" => "integer"}
        ]
      }
    }

    case Keyword.get(opts, :max_length) do
      nil -> Map.merge(field_schema, base_constraints)
      max_len -> Map.merge(field_schema, Map.put(base_constraints, "maxItems", max_len))
    end
  end

  defp add_type_constraints(field_schema, :reasoning_chain, _opts) do
    Map.merge(field_schema, %{
      "type" => "array",
      "items" => %{
        "type" => "object",
        "properties" => %{
          "step" => %{"type" => "string"},
          "reasoning" => %{"type" => "string"}
        },
        "required" => ["step", "reasoning"]
      }
    })
  end

  defp add_type_constraints(field_schema, :tensor, _opts) do
    Map.merge(field_schema, %{
      "type" => "array",
      "items" => %{"type" => ["number", "array"]}
    })
  end

  defp add_type_constraints(field_schema, _type, _opts), do: field_schema

  defp apply_provider_optimizations(schema, :openai) do
    schema
    |> Map.put("additionalProperties", false)
    |> ensure_required_array()
    |> remove_unsupported_formats([:date, :time, :email])
    |> Map.put("x-openai-optimized", true)
  end

  defp apply_provider_optimizations(schema, :anthropic) do
    schema
    |> Map.put("additionalProperties", false)
    |> ensure_required_array()
    |> remove_unsupported_formats([:uri, :uuid])
    |> ensure_object_properties()
    |> Map.put("x-anthropic-optimized", true)
  end

  defp apply_provider_optimizations(schema, :groq) do
    schema
    |> Map.put("additionalProperties", false)
    |> ensure_required_array()
    |> Map.put("x-groq-optimized", true)
  end

  defp apply_provider_optimizations(schema, _), do: schema

  defp ensure_required_array(schema) do
    case Map.get(schema, "required") do
      nil -> Map.put(schema, "required", [])
      list when is_list(list) -> schema
      _ -> Map.put(schema, "required", [])
    end
  end

  defp remove_unsupported_formats(schema, unsupported_formats) do
    case Map.get(schema, "properties") do
      nil ->
        schema

      properties ->
        updated_properties =
          properties
          |> Enum.map(fn {key, prop} ->
            case Map.get(prop, "format") do
              format when is_atom(format) ->
                if format in unsupported_formats do
                  {key, Map.delete(prop, "format")}
                else
                  {key, prop}
                end

              _ ->
                {key, prop}
            end
          end)
          |> Map.new()

        Map.put(schema, "properties", updated_properties)
    end
  end

  defp ensure_object_properties(schema) do
    case Map.get(schema, "type") do
      "object" ->
        case Map.get(schema, "properties") do
          nil -> Map.put(schema, "properties", %{})
          _ -> schema
        end

      _ ->
        schema
    end
  end

  defp json_type_for(:embedding), do: "array"
  defp json_type_for(:tensor), do: "array"
  defp json_type_for(:token_list), do: "array"
  defp json_type_for(:probability), do: "number"
  defp json_type_for(:confidence_score), do: "number"
  defp json_type_for(:model_response), do: "object"
  defp json_type_for(:variable_config), do: "object"
  defp json_type_for(:reasoning_chain), do: "array"
  defp json_type_for(:attention_weights), do: "array"
  defp json_type_for(:string), do: "string"
  defp json_type_for(:integer), do: "integer"
  defp json_type_for(:float), do: "number"
  defp json_type_for(:boolean), do: "boolean"
  defp json_type_for(:map), do: "object"
  defp json_type_for(:list), do: "array"
  defp json_type_for(_), do: "string"
end
