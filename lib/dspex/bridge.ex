defmodule DSPex.Bridge do
  @moduledoc """
  Dynamic DSPy bridge with metaprogramming for automatic wrapper generation.

  This module provides a universal interface to DSPy through the schema bridge,
  eliminating the need for manual wrapper creation for every DSPy class.
  """

  alias DSPex.Utils.ID

  @doc false
  defmacro __using__(_opts) do
    quote do
      import DSPex.Bridge, only: [defdsyp: 2, defdsyp: 3]
    end
  end

  @doc """
  Macro to generate DSPy wrapper modules with automatic error handling, result transformation,
  and bidirectional tool calling support.

  ## Usage

      defmodule MyApp.CustomPredictor do
        use DSPex.Bridge
        
        defdsyp __MODULE__, "dspy.Predict", %{
          execute_method: "__call__",
          result_transform: &MyApp.ResultTransforms.prediction_result/1,
          elixir_tools: [
            "validate_reasoning",
            "process_template", 
            "transform_result"
          ],
          enhanced_mode: true  # Use bidirectional DSPy tools
        }
      end
  """
  defmacro defdsyp(module_name, class_path, config \\ %{}) do
    quote bind_quoted: [
            module_name: module_name,
            class_path: class_path,
            config: config
          ] do
      defmodule module_name do
        @class_path class_path
        @config config

        @doc """
        Create a new #{@class_path} instance with bidirectional tool support.

        Returns `{:ok, {session_id, instance_id}}` on success.
        """
        def create(args \\ %{}, opts \\ []) do
          session_id = opts[:session_id] || ID.generate("session")

          # Register Elixir tools if specified in config
          if @config[:elixir_tools] do
            DSPex.Bridge.Tools.register_standard_tools(session_id)
          end

          # Choose enhanced or standard execution based on config
          tool_name =
            if @config[:enhanced_mode] do
              case @class_path do
                "dspy.Predict" -> "enhanced_predict"
                "dspy.ChainOfThought" -> "enhanced_chain_of_thought"
                _ -> "call_dspy"
              end
            else
              "call_dspy"
            end

          call_result =
            if tool_name in ["enhanced_predict", "enhanced_chain_of_thought"] do
              # For enhanced tools, we handle them differently - they don't create instances
              # but execute directly. We'll handle this in the execute method.
              {:ok,
               %{
                 "success" => true,
                 "instance_id" => "enhanced_#{ID.generate("instance")}",
                 "enhanced" => true
               }}
            else
              metadata = %{
                module: @class_path,
                function: "__init__",
                args: args,
                session_id: session_id
              }
              
              :telemetry.span(
                [:dspex, :bridge, :call],
                metadata,
                fn ->
                  result = Snakepit.execute_in_session(session_id, "call_dspy", %{
                    "module_path" => @class_path,
                    "function_name" => "__init__",
                    "args" => [],
                    "kwargs" => args
                  })
                  
                  case result do
                    {:ok, %{"success" => true} = res} ->
                      {result, Map.put(metadata, :success, true)}
                    {:ok, %{"success" => false, "error" => error}} ->
                      {result, Map.merge(metadata, %{success: false, error: error})}
                    {:error, error} ->
                      {result, Map.merge(metadata, %{success: false, error: error})}
                  end
                end
              )
            end

          case call_result do
            {:ok, %{"success" => true, "instance_id" => instance_id}} ->
              {:ok, {session_id, instance_id}}

            {:ok, %{"success" => false, "error" => error, "traceback" => traceback}} ->
              {:error, "#{@class_path} creation failed: #{error}\n#{traceback}"}

            {:ok, %{"success" => false, "error" => error}} ->
              {:error, "#{@class_path} creation failed: #{error}"}

            {:error, error} ->
              {:error, error}
          end
        end

        @doc """
        Execute the primary method on the instance with bidirectional tool support.

        Uses the configured execute_method (defaults to "__call__") or enhanced tools
        when enhanced_mode is enabled.
        """
        def execute({session_id, instance_id}, args \\ %{}, opts \\ []) do
          # Check if this is an enhanced instance
          if String.starts_with?(instance_id, "enhanced_") and @config[:enhanced_mode] do
            # Use enhanced bidirectional tools
            tool_name =
              case @class_path do
                "dspy.Predict" -> "enhanced_predict"
                "dspy.ChainOfThought" -> "enhanced_chain_of_thought"
                # Fallback
                _ -> "call_dspy"
              end

            # Get signature from creation args (stored in opts) or extract from args
            signature = opts[:signature] || args["signature"] || "input -> output"
            enhanced_args = Map.put(args, "signature", signature)

            metadata = %{
              module: @class_path,
              function: tool_name,
              args: enhanced_args,
              session_id: session_id,
              enhanced_mode: true
            }
            
            call_result = :telemetry.span(
              [:dspex, :bridge, :call],
              metadata,
              fn ->
                result = Snakepit.execute_in_session(session_id, tool_name, enhanced_args)
                case result do
                  {:ok, %{"success" => true}} ->
                    {result, Map.put(metadata, :success, true)}
                  {:ok, %{"success" => false, "error" => error}} ->
                    {result, Map.merge(metadata, %{success: false, error: error})}
                  {:error, error} ->
                    {result, Map.merge(metadata, %{success: false, error: error})}
                end
              end
            )

            case call_result do
              {:ok, %{"success" => true} = result} ->
                transformed_result =
                  if @config[:result_transform] do
                    @config[:result_transform].(result)
                  else
                    result
                  end

                {:ok, transformed_result}

              {:ok, %{"success" => false, "error" => error}} ->
                {:error, "Enhanced #{@class_path} failed: #{error}"}

              {:error, error} ->
                {:error, error}
            end
          else
            # Standard execution path
            method_name = @config[:execute_method] || "__call__"

            metadata = %{
              module: "stored.#{instance_id}",
              function: method_name,
              args: args,
              session_id: session_id
            }
            
            call_result =
              :telemetry.span(
                [:dspex, :bridge, :call],
                metadata,
                fn ->
                  result = Snakepit.execute_in_session(session_id, "call_dspy", %{
                    "module_path" => "stored.#{instance_id}",
                    "function_name" => method_name,
                    "args" => [],
                    "kwargs" => args
                  })
                  
                  case result do
                    {:ok, %{"success" => true} = res} ->
                      {result, Map.put(metadata, :success, true)}
                    {:ok, %{"success" => false, "error" => error}} ->
                      {result, Map.merge(metadata, %{success: false, error: error})}
                    {:error, error} ->
                      {result, Map.merge(metadata, %{success: false, error: error})}
                  end
                end
              )

            case call_result do
              {:ok, %{"success" => true, "result" => result}} ->
                transformed_result =
                  if @config[:result_transform] do
                    @config[:result_transform].(result)
                  else
                    result
                  end

                {:ok, transformed_result}

              {:ok, %{"success" => false, "error" => error, "traceback" => traceback}} ->
                {:error, "#{@class_path}.#{method_name} failed: #{error}\n#{traceback}"}

              {:ok, %{"success" => false, "error" => error}} ->
                {:error, "#{@class_path}.#{method_name} failed: #{error}"}

              {:error, error} ->
                {:error, error}
            end
          end
        end

        # Generate additional methods based on config
        unquote(
          for {method_name, elixir_name} <- config[:methods] || %{} do
            quote do
              @doc """
              Call #{unquote(method_name)} method on the DSPy instance.
              """
              def unquote(String.to_atom(elixir_name))({session_id, instance_id}, args \\ %{}) do
                metadata = %{
                  module: "stored.#{instance_id}",
                  function: unquote(method_name),
                  args: args,
                  session_id: session_id
                }
                
                call_result =
                  :telemetry.span(
                    [:dspex, :bridge, :call],
                    metadata,
                    fn ->
                      result = Snakepit.execute_in_session(session_id, "call_dspy", %{
                        "module_path" => "stored.#{instance_id}",
                        "function_name" => unquote(method_name),
                        "args" => [],
                        "kwargs" => args
                      })
                      
                      case result do
                        {:ok, %{"success" => true} = res} ->
                          {result, Map.put(metadata, :success, true)}
                        {:ok, %{"success" => false, "error" => error}} ->
                          {result, Map.merge(metadata, %{success: false, error: error})}
                        {:error, error} ->
                          {result, Map.merge(metadata, %{success: false, error: error})}
                      end
                    end
                  )

                case call_result do
                  {:ok, %{"success" => true, "result" => result}} ->
                    {:ok, result}

                  {:ok, %{"success" => false, "error" => error, "traceback" => traceback}} ->
                    {:error,
                     "#{@class_path}.#{unquote(method_name)} failed: #{error}\n#{traceback}"}

                  {:ok, %{"success" => false, "error" => error}} ->
                    {:error, "#{@class_path}.#{unquote(method_name)} failed: #{error}"}

                  {:error, error} ->
                    {:error, error}
                end
              end
            end
          end
        )

        @doc """
        Create and execute in one call (stateless).
        """
        def call(args, inputs \\ %{}, opts \\ []) do
          session_id = opts[:session_id] || ID.generate("session")

          with {:ok, instance_ref} <- create(args, Keyword.put(opts, :session_id, session_id)),
               {:ok, result} <- execute(instance_ref, inputs, opts) do
            {:ok, result}
          end
        end
      end
    end
  end

  @doc """
  Call any DSPy function or method directly without creating a wrapper module.

  ## Examples

      # Static function call
      DSPex.Bridge.call_dspy("dspy.settings", "configure", %{"lm" => lm_instance})
      
      # Create instance and call method
      {:ok, instance_id} = DSPex.Bridge.create_instance("dspy.Predict", %{"signature" => "question -> answer"})
      {:ok, result} = DSPex.Bridge.call_method(instance_id, "__call__", %{"question" => "What is DSPy?"})
  """
  def call_dspy(module_path, function_name, args \\ %{}, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")
    
    metadata = %{
      module: module_path,
      function: function_name,
      args: args,
      session_id: session_id
    }
    
    :telemetry.span(
      [:dspex, :bridge, :call],
      metadata,
      fn ->
        call_result =
          Snakepit.execute_in_session(session_id, "call_dspy", %{
            "module_path" => module_path,
            "function_name" => function_name,
            "args" => [],
            "kwargs" => args
          })

        case call_result do
          {:ok, %{"success" => true} = result} -> 
            {{:ok, result}, Map.put(metadata, :success, true)}
          {:ok, %{"success" => false, "error" => error}} -> 
            {{:error, error}, Map.merge(metadata, %{success: false, error: error})}
          {:error, error} -> 
            {{:error, error}, Map.merge(metadata, %{success: false, error: error})}
        end
      end
    )
  end

  @doc """
  Create a DSPy instance and return the session and instance ID.
  """
  def create_instance(class_path, args \\ %{}, opts \\ []) do
    metadata = %{
      python_class: class_path,
      args: args,
      session_id: opts[:session_id] || ID.generate("session")
    }
    
    :telemetry.span(
      [:dspex, :bridge, :create_instance],
      metadata,
      fn ->
        case call_dspy(class_path, "__init__", args, opts) do
          {:ok, %{"instance_id" => instance_id, "type" => "constructor"}} ->
            session_id = metadata.session_id
            result = {:ok, {session_id, instance_id}}
            {result, Map.put(metadata, :success, true)}

          {:error, error} ->
            result = {:error, error}
            {result, Map.merge(metadata, %{success: false, error: error})}
        end
      end
    )
  end

  @doc """
  Call a method on a stored DSPy instance.
  """
  def call_method({session_id, instance_id}, method_name, args \\ %{}, opts \\ []) do
    metadata = %{
      instance_id: instance_id,
      method_name: method_name,
      args: args,
      session_id: session_id
    }
    
    :telemetry.span(
      [:dspex, :bridge, :call_method],
      metadata,
      fn ->
        result = call_dspy(
          "stored.#{instance_id}",
          method_name,
          args,
          Keyword.put(opts, :session_id, session_id)
        )
        
        success = match?({:ok, _}, result)
        {result, Map.put(metadata, :success, success)}
      end
    )
  end

  @doc """
  Discover the schema of a DSPy module or submodule.

  ## Examples

      {:ok, schema} = DSPex.Bridge.discover_schema("dspy")
      {:ok, optimizers} = DSPex.Bridge.discover_schema("dspy.teleprompt")
  """
  def discover_schema(module_path \\ "dspy", opts \\ []) do
    session_id = opts[:session_id] || ID.generate("discovery")
    
    metadata = %{
      module: module_path,
      function: "discover_dspy_schema",
      args: %{"module_path" => module_path},
      session_id: session_id
    }
    
    :telemetry.span(
      [:dspex, :bridge, :call],
      metadata,
      fn ->
        case Snakepit.execute_in_session(session_id, "discover_dspy_schema", %{
               "module_path" => module_path
             }) do
          {:ok, %{"success" => true, "schema" => schema}} -> 
            {{:ok, schema}, Map.put(metadata, :success, true)}
          {:ok, %{"success" => false, "error" => error}} -> 
            {{:error, error}, Map.merge(metadata, %{success: false, error: error})}
          {:error, error} -> 
            {{:error, error}, Map.merge(metadata, %{success: false, error: error})}
        end
      end
    )
  end

  @doc """
  Generate documentation for discovered DSPy classes and methods.
  """
  def generate_docs(module_path \\ "dspy", opts \\ []) do
    case discover_schema(module_path, opts) do
      {:ok, schema} ->
        docs =
          for {class_name, class_info} <- schema do
            methods_doc =
              for {method_name, method_info} <- class_info["methods"] do
                "    #{method_name}#{method_info["signature"]} - #{method_info["docstring"]}"
              end
              |> Enum.join("\n")

            """
            ## #{class_name} (#{class_info["type"]})
            #{class_info["docstring"]}

            ### Methods:
            #{methods_doc}
            """
          end
          |> Enum.join("\n\n")

        {:ok, docs}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Helper for transforming prediction results to DSPex standard format.
  """
  def transform_prediction_result(raw_result) do
    case raw_result do
      %{"completions" => completions} when is_list(completions) ->
        # Handle DSPy completion format
        %{"success" => true, "result" => %{"prediction_data" => List.first(completions)}}

      result when is_map(result) ->
        %{"success" => true, "result" => %{"prediction_data" => result}}

      _ ->
        %{
          "success" => true,
          "result" => %{"prediction_data" => %{"answer" => to_string(raw_result)}}
        }
    end
  end

  @doc """
  Helper for transforming chain of thought results.
  """
  def transform_cot_result(raw_result) do
    case raw_result do
      %{"reasoning" => reasoning, "answer" => answer} ->
        %{
          "success" => true,
          "result" => %{"prediction_data" => %{"reasoning" => reasoning, "answer" => answer}}
        }

      %{"rationale" => rationale, "answer" => answer} ->
        %{
          "success" => true,
          "result" => %{"prediction_data" => %{"reasoning" => rationale, "answer" => answer}}
        }

      result when is_map(result) ->
        %{"success" => true, "result" => %{"prediction_data" => result}}

      _ ->
        %{
          "success" => true,
          "result" => %{"prediction_data" => %{"answer" => to_string(raw_result)}}
        }
    end
  end

  @doc """
  Initialize a session with bidirectional tool support.

  This registers standard Elixir tools and prepares the session for
  Python ↔ Elixir communication.
  """
  def init_bidirectional_session(session_id) do
    with {:ok, _count} <- DSPex.Bridge.Tools.register_standard_tools(session_id) do
      {:ok, session_id}
    end
  end

  @doc """
  Create an enhanced DSPy wrapper that uses bidirectional tools.

  ## Examples

      # Create enhanced Chain of Thought with Elixir validation
      {:ok, enhanced_cot} = DSPex.Bridge.create_enhanced_wrapper(
        "dspy.ChainOfThought",
        session_id: "my_session",
        signature: "question -> reasoning, answer"
      )
      
      {:ok, result} = DSPex.Bridge.execute_enhanced(enhanced_cot, %{
        "question" => "What are the benefits of Elixir?",
        "domain" => "technical"
      })
  """
  def create_enhanced_wrapper(class_path, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("enhanced_session")
    signature = opts[:signature] || "input -> output"

    # Initialize session with bidirectional tools
    with {:ok, _} <- init_bidirectional_session(session_id) do
      enhanced_ref = {session_id, "enhanced_#{ID.generate("wrapper")}", class_path, signature}
      {:ok, enhanced_ref}
    end
  end

  @doc """
  Execute an enhanced wrapper created with create_enhanced_wrapper/2.
  """
  def execute_enhanced({session_id, _instance_id, class_path, signature}, inputs, opts \\ []) do
    case class_path do
      "dspy.Predict" ->
        execute_enhanced_tool(session_id, "enhanced_predict", signature, inputs, opts)

      "dspy.ChainOfThought" ->
        execute_enhanced_tool(session_id, "enhanced_chain_of_thought", signature, inputs, opts)

      _ ->
        {:error, "Enhanced mode not supported for #{class_path}"}
    end
  end

  defp execute_enhanced_tool(session_id, tool_name, signature, inputs, opts) do
    enhanced_inputs =
      inputs
      |> Map.put("signature", signature)
      |> Map.merge(opts[:additional_inputs] || %{})

    metadata = %{
      module: "enhanced_tools",
      function: tool_name,
      args: enhanced_inputs,
      session_id: session_id
    }
    
    :telemetry.span(
      [:dspex, :bridge, :call],
      metadata,
      fn ->
        case Snakepit.execute_in_session(session_id, tool_name, enhanced_inputs) do
          {:ok, %{"success" => true} = result} -> 
            {{:ok, result}, Map.put(metadata, :success, true)}
          {:ok, %{"success" => false, "error" => error}} -> 
            {{:error, error}, Map.merge(metadata, %{success: false, error: error})}
          {:error, error} -> 
            {{:error, error}, Map.merge(metadata, %{success: false, error: error})}
        end
      end
    )
  end

  @doc """
  Register custom Elixir tools for a session.

  ## Examples

      # Register domain-specific validation
      DSPex.Bridge.register_custom_tool(session_id, "validate_medical_reasoning", fn params ->
        # Custom medical validation logic
        %{valid: true, confidence: 0.9, domain: "medical"}
      end, %{
        description: "Validate medical reasoning chains",
        parameters: [%{name: "reasoning", type: "string", required: true}]
      })
  """
  def register_custom_tool(session_id, tool_name, function, metadata \\ %{}) do
    DSPex.Bridge.Tools.register_tool(session_id, tool_name, function, metadata)
  end

  @doc """
  Get list of available Elixir tools in a session.
  """
  def list_elixir_tools(session_id) do
    metadata = %{
      module: "tools",
      function: "list_stored_objects",
      args: %{},
      session_id: session_id
    }
    
    :telemetry.span(
      [:dspex, :bridge, :call],
      metadata,
      fn ->
        case Snakepit.execute_in_session(session_id, "list_stored_objects", %{}) do
          {:ok, %{"success" => true, "objects" => objects}} ->
            elixir_tools =
              objects
              |> Enum.filter(fn obj -> obj["name"] |> String.starts_with?("elixir_tool_") end)
              |> Enum.map(fn obj -> String.replace_prefix(obj["name"], "elixir_tool_", "") end)

            {{:ok, elixir_tools}, Map.put(metadata, :success, true)}

          {:error, error} ->
            {{:error, error}, Map.merge(metadata, %{success: false, error: error})}
        end
      end
    )
  end

  @doc """
  Register tools for bidirectional communication.
  
  This function is used by the WrapperOrchestrator to register
  Elixir functions that can be called from Python.
  
  ## Parameters
  
  - `ref` - The Python object reference (session_id, instance_id)
  - `tools` - List of {name, function} tuples
  
  ## Returns
  
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  def register_tools({session_id, instance_id}, tools) when is_list(tools) do
    Enum.each(tools, fn {name, function} when is_binary(name) and is_function(function, 1) ->
      # Register each tool with the session
      DSPex.Bridge.Tools.register_tool(session_id, name, function, %{
        instance_id: instance_id,
        registered_at: DateTime.utc_now()
      })
    end)
    
    :ok
  end
  
  def register_tools(_ref, _tools), do: {:error, :invalid_arguments}
end
