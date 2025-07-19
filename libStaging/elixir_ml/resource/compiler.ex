defmodule ElixirML.Resource.Compiler do
  @moduledoc """
  Compile-time code generation for ElixirML resources.

  Generates struct definitions, validation functions, and other
  boilerplate code based on resource definitions.
  """

  defmacro __before_compile__(env) do
    # Get accumulated metadata
    metadata = extract_metadata(env)

    # Generate the resource struct
    struct_fields = generate_struct_fields(metadata.attributes, metadata.relationships)

    # Generate all function groups
    functions = generate_all_functions(metadata)

    quote do
      # Define the resource struct
      defstruct unquote(Macro.escape(struct_fields))

      # Core behaviour implementations
      unquote_splicing(generate_behaviour_implementations())

      # Generated validation functions
      unquote_splicing(functions.validation_functions)

      # Generated action functions
      unquote_splicing(functions.action_functions)

      # Generated calculation functions
      unquote_splicing(functions.calculation_functions)

      # Generated relationship functions
      unquote_splicing(functions.relationship_functions)

      # Helper functions
      unquote_splicing(generate_helper_functions())

      # Metadata accessors
      unquote_splicing(generate_metadata_accessors(metadata))
    end
  end

  # Extract metadata from environment
  defp extract_metadata(env) do
    %{
      attributes: Module.get_attribute(env.module, :attributes) || [],
      relationships: Module.get_attribute(env.module, :relationships) || [],
      actions: Module.get_attribute(env.module, :actions) || [],
      calculations: Module.get_attribute(env.module, :calculations) || [],
      validations: Module.get_attribute(env.module, :validations) || [],
      schema_attributes: Module.get_attribute(env.module, :schema_attributes) || []
    }
  end

  # Generate all function groups
  defp generate_all_functions(metadata) do
    %{
      validation_functions:
        generate_validation_functions(
          metadata.attributes,
          metadata.schema_attributes,
          metadata.validations
        ),
      action_functions: generate_action_functions(metadata.actions),
      calculation_functions: generate_calculation_functions(metadata.calculations),
      relationship_functions: generate_relationship_functions(metadata.relationships)
    }
  end

  # Generate core behaviour implementations
  defp generate_behaviour_implementations do
    [
      generate_create_function(),
      generate_get_function(),
      generate_update_function(),
      generate_delete_function(),
      generate_validate_function(),
      generate_execute_action_function(),
      generate_calculate_function(),
      generate_partial_validation_function()
    ]
  end

  defp generate_create_function do
    quote do
      @impl ElixirML.Resource.Behaviour
      def create(attributes) when is_map(attributes) do
        # Apply defaults first, then validate
        attrs_with_defaults = apply_defaults_to_attrs(attributes)

        with {:ok, validated_attrs} <- validate_attributes(attrs_with_defaults) do
          build_resource(validated_attrs)
        end
      end
    end
  end

  defp generate_get_function do
    quote do
      @impl ElixirML.Resource.Behaviour
      def get(id) do
        # Simple in-memory storage for now
        # In a real implementation, this would query a database
        {:error, :not_found}
      end
    end
  end

  defp generate_update_function do
    quote do
      @impl ElixirML.Resource.Behaviour
      def update(resource, attributes) when is_struct(resource) and is_map(attributes) do
        # For updates, we only validate the attributes being changed, not the entire resource
        with {:ok, validated_attrs} <- validate_partial_attributes(attributes) do
          apply_updates(resource, validated_attrs)
        end
      end
    end
  end

  defp generate_delete_function do
    quote do
      @impl ElixirML.Resource.Behaviour
      def delete(_resource) do
        # Simple implementation - in reality would delete from storage
        :ok
      end
    end
  end

  defp generate_validate_function do
    quote do
      @impl ElixirML.Resource.Behaviour
      def validate(resource) when is_struct(resource) do
        # Convert struct to map for validation
        attributes = Map.from_struct(resource)

        case validate_attributes(attributes) do
          {:ok, _} -> {:ok, resource}
          error -> error
        end
      end
    end
  end

  defp generate_execute_action_function do
    quote do
      @impl ElixirML.Resource.Behaviour
      def execute_action(resource, action_name, arguments) do
        case find_action(action_name) do
          {:ok, action_def} -> execute_action_impl(resource, action_def, arguments)
          {:error, _} = error -> error
        end
      end
    end
  end

  defp generate_calculate_function do
    quote do
      @impl ElixirML.Resource.Behaviour
      def calculate(resource, calculation_name, arguments) do
        case find_calculation(calculation_name) do
          {:ok, calc_def} -> execute_calculation_impl(resource, calc_def, arguments)
          {:error, _} = error -> error
        end
      end
    end
  end

  defp generate_partial_validation_function do
    quote do
      # Partial validation for updates (only validate provided attributes)
      defp validate_partial_attributes(attributes) do
        Enum.each(attributes, &validate_single_attribute/1)
        {:ok, attributes}
      catch
        {:validation_error, field, reason} ->
          {:error, {:validation_error, field, reason}}
      end

      defp validate_single_attribute({name, value}) do
        case find_attribute_definition(name) do
          {_, type, opts} ->
            validate_attribute_or_throw(name, type, value, opts)

          nil ->
            # Ignore attributes not defined for this resource
            :ok
        end
      end

      defp validate_attribute_or_throw(name, type, value, opts) do
        case validate_attribute(name, type, value, opts) do
          :ok -> :ok
          {:error, reason} -> throw({:validation_error, name, reason})
        end
      end

      defp find_attribute_definition(name) do
        Enum.find(__resource_attributes__(), fn {attr_name, _, _} ->
          attr_name == name
        end)
      end
    end
  end

  # Generate helper functions
  defp generate_helper_functions do
    [
      quote do
        defp build_resource(attributes) do
          # Apply default values for missing attributes
          attrs_with_defaults = apply_defaults_to_attrs(attributes)
          resource = struct(__MODULE__, attrs_with_defaults)
          {:ok, resource}
        end
      end,
      quote do
        defp apply_defaults_to_attrs(attributes) do
          # Get all attribute definitions with defaults
          attr_defaults = extract_attribute_defaults()
          # Merge defaults with provided attributes (attributes take precedence)
          Map.merge(attr_defaults, attributes)
        end
      end,
      quote do
        defp extract_attribute_defaults do
          __resource_attributes__()
          |> Enum.filter(fn {_name, _type, opts} -> Keyword.has_key?(opts, :default) end)
          |> Enum.map(fn {name, _type, opts} -> {name, Keyword.get(opts, :default)} end)
          |> Map.new()
        end
      end,
      quote do
        defp apply_updates(resource, attributes) do
          updated_resource = struct(resource, attributes)
          {:ok, updated_resource}
        end
      end
    ]
  end

  # Generate metadata accessors
  defp generate_metadata_accessors(metadata) do
    [
      quote do
        def __resource_attributes__, do: unquote(Macro.escape(metadata.attributes))
      end,
      quote do
        def __resource_relationships__, do: unquote(Macro.escape(metadata.relationships))
      end,
      quote do
        def __resource_actions__, do: unquote(Macro.escape(metadata.actions))
      end,
      quote do
        def __resource_calculations__, do: unquote(Macro.escape(metadata.calculations))
      end,
      quote do
        def __resource_schema_attributes__, do: unquote(Macro.escape(metadata.schema_attributes))
      end
    ]
  end

  defp generate_struct_fields(attributes, relationships) do
    # Generate struct fields from attributes
    attr_fields =
      Enum.map(attributes, fn {name, _type, opts} ->
        default = Keyword.get(opts, :default)
        {name, default}
      end)

    # Generate struct fields from relationships
    rel_fields =
      Enum.map(relationships, fn
        {:belongs_to, name, _module, _opts} -> {:"#{name}_id", nil}
        {:has_many, name, _module, _opts} -> {name, []}
        {:has_one, name, _module, _opts} -> {name, nil}
      end)

    # Always include :id field
    [{:id, nil} | attr_fields ++ rel_fields]
  end

  defp generate_validation_functions(attributes, schema_attributes, validations) do
    # Generate main validation function
    validate_attributes_fn =
      quote do
        defp validate_attributes(attributes) when is_map(attributes) do
          with {:ok, attrs} <- validate_basic_attributes(attributes),
               {:ok, attrs} <- validate_schema_attributes(attrs) do
            validate_custom_validations(attrs)
          end
        end
      end

    # Generate basic attribute validation
    validate_basic_fn = generate_basic_validation(attributes)

    # Generate schema attribute validation
    validate_schema_fn = generate_schema_validation(schema_attributes)

    # Generate custom validations
    validate_custom_fn = generate_custom_validations(validations)

    [validate_attributes_fn, validate_basic_fn, validate_schema_fn, validate_custom_fn]
  end

  defp generate_basic_validation(attributes) do
    validations = generate_attribute_validations(attributes)

    quote do
      defp validate_basic_attributes(attrs) do
        unquote_splicing(validations)
        {:ok, attrs}
      catch
        {:validation_error, field, reason} ->
          {:error, {:validation_error, field, reason}}
      end

      unquote_splicing(generate_validation_helpers())
    end
  end

  defp generate_attribute_validations(attributes) do
    Enum.map(attributes, fn {name, type, opts} ->
      quote do
        case validate_attribute(
               unquote(name),
               unquote(type),
               Map.get(attrs, unquote(name)),
               unquote(Macro.escape(opts))
             ) do
          :ok -> :ok
          {:error, reason} -> throw({:validation_error, unquote(name), reason})
        end
      end
    end)
  end

  defp generate_validation_helpers do
    [
      generate_validate_attribute_function(),
      generate_type_validators(),
      generate_constraint_validators()
    ]
  end

  defp generate_validate_attribute_function do
    quote do
      defp validate_attribute(name, type, value, opts) do
        cond do
          is_nil(value) and not Keyword.get(opts, :allow_nil?, true) ->
            {:error, "#{name} cannot be nil"}

          not is_nil(value) and not valid_type?(value, type) ->
            {:error, "#{name} must be of type #{type}"}

          true ->
            validate_constraints(name, value, Keyword.get(opts, :constraints, []))
        end
      end
    end
  end

  defp generate_type_validators do
    basic_types = generate_basic_type_validators()
    special_cases = generate_special_type_validators()

    quote do
      unquote_splicing(basic_types)
      unquote_splicing(special_cases)
    end
  end

  defp generate_basic_type_validators do
    [
      quote(
        do:
          defp valid_type?(value, :string) do
            is_binary(value)
          end
      ),
      quote(
        do:
          defp valid_type?(value, :integer) do
            is_integer(value)
          end
      ),
      quote(
        do:
          defp valid_type?(value, :float) do
            is_float(value)
          end
      ),
      quote(
        do:
          defp valid_type?(value, :boolean) do
            is_boolean(value)
          end
      ),
      quote(
        do:
          defp valid_type?(value, :atom) do
            is_atom(value)
          end
      ),
      quote(
        do:
          defp valid_type?(value, :map) do
            is_map(value)
          end
      ),
      quote(
        do:
          defp valid_type?(value, :list) do
            is_list(value)
          end
      )
    ]
  end

  defp generate_special_type_validators do
    [
      # Schema validation handled separately
      quote(
        do:
          defp valid_type?(_value, :schema) do
            true
          end
      ),
      # Unknown types pass through
      quote(
        do:
          defp valid_type?(_value, _type) do
            true
          end
      )
    ]
  end

  defp generate_constraint_validators do
    quote do
      defp validate_constraints(_name, _value, []), do: :ok

      defp validate_constraints(name, value, [{:one_of, allowed_values} | rest]) do
        if value in allowed_values do
          validate_constraints(name, value, rest)
        else
          {:error, "#{name} must be one of #{inspect(allowed_values)}"}
        end
      end

      defp validate_constraints(name, value, [_constraint | rest]) do
        # Skip unknown constraints for now
        validate_constraints(name, value, rest)
      end
    end
  end

  defp generate_schema_validation(schema_attributes) do
    validations = Enum.map(schema_attributes, &generate_schema_attribute_validation/1)

    quote do
      defp validate_schema_attributes(attrs) do
        unquote_splicing(validations)
        {:ok, attrs}
      catch
        {:schema_validation_error, field, reason} ->
          {:error, {:schema_validation_error, field, reason}}
      end

      unquote(generate_schema_validation_helper())
    end
  end

  defp generate_schema_attribute_validation({name, schema_module, _opts}) do
    quote do
      case Map.get(attrs, unquote(name)) do
        nil ->
          :ok

        value ->
          validate_schema_value(unquote(name), unquote(schema_module), value)
      end
    end
  end

  defp generate_schema_validation_helper do
    quote do
      defp validate_schema_value(name, schema_module, value) do
        case schema_module.validate(value) do
          {:ok, _} -> :ok
          {:error, reason} -> throw({:schema_validation_error, name, reason})
        end
      end
    end
  end

  defp generate_custom_validations(validations) do
    validation_calls =
      Enum.map(validations, fn {name, _opts, block} ->
        quote do
          case unquote(block) do
            :ok -> :ok
            {:ok, _} -> :ok
            {:error, reason} -> throw({:custom_validation_error, unquote(name), reason})
            _ -> throw({:custom_validation_error, unquote(name), "Custom validation failed"})
          end
        end
      end)

    quote do
      defp validate_custom_validations(attrs) do
        unquote_splicing(validation_calls)
        {:ok, attrs}
      catch
        {:custom_validation_error, validation_name, reason} ->
          {:error, {:custom_validation_error, validation_name, reason}}
      end
    end
  end

  defp generate_action_functions(actions) do
    action_finder = generate_action_finder(actions)
    action_executor = generate_action_executor()

    [action_finder, action_executor]
  end

  defp generate_action_finder(actions) do
    action_clauses =
      Enum.map(actions, fn {name, opts, _block} ->
        quote do
          def find_action(unquote(name)) do
            {:ok, {unquote(name), unquote(Macro.escape(opts))}}
          end
        end
      end)

    fallback_clause =
      quote do
        def find_action(_name), do: {:error, :action_not_found}
      end

    [action_clauses, fallback_clause]
  end

  defp generate_action_executor do
    quote do
      defp execute_action_impl(_resource, {action_name, _opts}, _arguments) do
        # Simple implementation - in reality would execute the action
        {:ok, %{action: action_name, status: :executed}}
      end
    end
  end

  defp generate_calculation_functions(calculations) do
    calc_finder = generate_calculation_finder(calculations)
    calc_executor = generate_calculation_executor()

    [calc_finder, calc_executor]
  end

  defp generate_calculation_finder(calculations) do
    calc_clauses =
      Enum.map(calculations, fn {name, return_type, calc_module, opts} ->
        quote do
          def find_calculation(unquote(name)) do
            {:ok,
             {unquote(name), unquote(return_type), unquote(calc_module),
              unquote(Macro.escape(opts))}}
          end
        end
      end)

    fallback_clause =
      quote do
        def find_calculation(_name), do: {:error, :calculation_not_found}
      end

    [calc_clauses, fallback_clause]
  end

  defp generate_calculation_executor do
    quote do
      defp execute_calculation_impl(
             resource,
             {_calc_name, _return_type, calc_module, _opts},
             arguments
           ) do
        # Execute the actual calculation module
        case calc_module.calculate(resource, arguments) do
          {:ok, result} -> {:ok, result}
          {:error, _} = error -> error
          # Handle direct returns
          result -> {:ok, result}
        end
      end
    end
  end

  defp generate_relationship_functions(relationships) do
    # Generate relationship accessor functions
    Enum.map(relationships, fn
      {:belongs_to, name, module, _opts} ->
        quote do
          def unquote(:"get_#{name}")(resource) do
            case Map.get(resource, unquote(:"#{name}_id")) do
              nil -> {:ok, nil}
              id -> unquote(module).get(id)
            end
          end
        end

      {:has_many, name, _module, _opts} ->
        quote do
          def unquote(:"get_#{name}")(resource) do
            {:ok, Map.get(resource, unquote(name), [])}
          end
        end

      {:has_one, name, module, _opts} ->
        quote do
          def unquote(:"get_#{name}")(resource) do
            case Map.get(resource, unquote(:"#{name}_id")) do
              nil -> {:ok, nil}
              id -> unquote(module).get(id)
            end
          end
        end
    end)
  end
end
