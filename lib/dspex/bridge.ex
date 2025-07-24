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
  Macro to generate DSPy wrapper modules with automatic error handling and result transformation.

  ## Usage

      defmodule MyApp.CustomPredictor do
        use DSPex.Bridge
        
        defdsyp __MODULE__, "dspy.Predict", %{
          execute_method: "__call__",
          result_transform: &MyApp.ResultTransforms.prediction_result/1
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
        Create a new #{@class_path} instance.

        Returns `{:ok, {session_id, instance_id}}` on success.
        """
        def create(args \\ %{}, opts \\ []) do
          session_id = opts[:session_id] || ID.generate("session")

          call_result =
            Snakepit.execute_in_session(session_id, "call_dspy", %{
              "module_path" => @class_path,
              "function_name" => "__init__",
              "args" => [],
              "kwargs" => args
            })

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
        Execute the primary method on the instance.

        Uses the configured execute_method (defaults to "__call__").
        """
        def execute({session_id, instance_id}, args \\ %{}, opts \\ []) do
          method_name = @config[:execute_method] || "__call__"

          call_result =
            Snakepit.execute_in_session(session_id, "call_dspy", %{
              "module_path" => "stored.#{instance_id}",
              "function_name" => method_name,
              "args" => [],
              "kwargs" => args
            })

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

        # Generate additional methods based on config
        unquote(
          for {method_name, elixir_name} <- config[:methods] || %{} do
            quote do
              @doc """
              Call #{unquote(method_name)} method on the DSPy instance.
              """
              def unquote(String.to_atom(elixir_name))({session_id, instance_id}, args \\ %{}) do
                call_result =
                  Snakepit.execute_in_session(session_id, "call_dspy", %{
                    "module_path" => "stored.#{instance_id}",
                    "function_name" => unquote(method_name),
                    "args" => [],
                    "kwargs" => args
                  })

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

    call_result =
      Snakepit.execute_in_session(session_id, "call_dspy", %{
        "module_path" => module_path,
        "function_name" => function_name,
        "args" => [],
        "kwargs" => args
      })

    case call_result do
      {:ok, %{"success" => true} = result} -> {:ok, result}
      {:ok, %{"success" => false, "error" => error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Create a DSPy instance and return the session and instance ID.
  """
  def create_instance(class_path, args \\ %{}, opts \\ []) do
    case call_dspy(class_path, "__init__", args, opts) do
      {:ok, %{"instance_id" => instance_id, "type" => "constructor"}} ->
        session_id = opts[:session_id] || ID.generate("session")
        {:ok, {session_id, instance_id}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Call a method on a stored DSPy instance.
  """
  def call_method({session_id, instance_id}, method_name, args \\ %{}, opts \\ []) do
    call_dspy(
      "stored.#{instance_id}",
      method_name,
      args,
      Keyword.put(opts, :session_id, session_id)
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

    case Snakepit.execute_in_session(session_id, "discover_dspy_schema", %{
           "module_path" => module_path
         }) do
      {:ok, %{"success" => true, "schema" => schema}} -> {:ok, schema}
      {:ok, %{"success" => false, "error" => error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
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
end
