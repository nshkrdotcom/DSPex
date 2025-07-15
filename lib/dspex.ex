defmodule DSPex do
  @moduledoc """
  Main interface for DSPex - Elixir interface to DSPy.

  Provides high-level functions for configuring language models,
  creating programs, and executing them.
  """

  alias DSPex.Adapters.Registry

  @supported_models %{
    "gemini-1.5-flash" => %{
      provider: :google,
      display_name: "Gemini 1.5 Flash",
      default_temperature: 0.7
    },
    "gemini-1.5-pro" => %{
      provider: :google,
      display_name: "Gemini 1.5 Pro",
      default_temperature: 0.7
    },
    "gemini-2.0-flash-exp" => %{
      provider: :google,
      display_name: "Gemini 2.0 Flash (Experimental)",
      default_temperature: 0.7
    }
  }

  ## Language Model Configuration

  @doc """
  Sets the default language model for all operations.

  ## Parameters

  - `model_name` - One of the supported model names
  - `opts` - Keyword list of options:
    - `:api_key` - API key for the model provider
    - `:temperature` - Temperature setting (0.0 to 1.0)

  ## Examples
      
      DSPex.set_lm("gemini-1.5-pro", api_key: System.get_env("GEMINI_API_KEY"))
      
      DSPex.set_lm("gemini-1.5-flash", 
        api_key: System.get_env("GEMINI_API_KEY"),
        temperature: 0.9
      )
  """
  @spec set_lm(String.t(), keyword()) :: :ok | {:error, String.t()}
  def set_lm(model_name, opts \\ []) when is_binary(model_name) do
    unless Map.has_key?(@supported_models, model_name) do
      raise ArgumentError, """
      Unsupported model: #{model_name}
      Supported models: #{Map.keys(@supported_models) |> Enum.join(", ")}
      """
    end

    config = %{
      model: model_name,
      provider: @supported_models[model_name].provider,
      api_key: Keyword.get(opts, :api_key, get_default_api_key()),
      temperature:
        Keyword.get(opts, :temperature, @supported_models[model_name].default_temperature)
    }

    # Store in application env
    Application.put_env(:dspex, :current_lm, config)

    # Configure in adapter
    with {:ok, adapter} <- get_adapter() do
      adapter.configure_lm(config)
    end
  end

  @doc """
  Gets the currently configured language model.

  ## Returns

  A map with the current LM configuration or raises if none configured.
  """
  @spec get_lm() :: map() | no_return()
  def get_lm do
    Application.get_env(:dspex, :current_lm) ||
      Application.get_env(:dspex, :default_lm) ||
      raise "No language model configured. Call DSPex.set_lm/2 first."
  end

  @doc """
  Lists all supported language models.
  """
  @spec list_supported_models() :: [String.t()]
  def list_supported_models do
    Map.keys(@supported_models)
  end

  ## Program Management

  @doc """
  Creates a new DSPy program with the given configuration.

  ## Parameters

  - `config` - Program configuration map with:
    - `:signature` - The signature definition
    - `:id` - Optional program ID

  ## Examples

      {:ok, program_id} = DSPex.create_program(%{
        signature: %{
          name: "QuestionAnswer",
          inputs: [%{name: "question", type: "string"}],
          outputs: [%{name: "answer", type: "string"}]
        }
      })
  """
  @spec create_program(map()) :: {:ok, String.t()} | {:error, term()}
  def create_program(config) do
    # Ensure LM is configured
    _ = get_lm()

    with {:ok, adapter} <- get_adapter() do
      adapter.create_program(config)
    end
  end

  @doc """
  Executes a program with the given inputs.

  ## Parameters

  - `program_id` - The program ID
  - `inputs` - Map of input values
  - `opts` - Optional execution options:
    - `:lm` - Override the language model for this execution
    - `:temperature` - Override temperature for this execution

  ## Examples

      {:ok, result} = DSPex.execute_program(program_id, %{
        question: "What is the capital of France?"
      })
      
      # With LM override
      {:ok, result} = DSPex.execute_program(program_id, 
        %{question: "What is 2+2?"}, 
        lm: "gemini-1.5-flash"
      )
  """
  @spec execute_program(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute_program(program_id, inputs, opts \\ []) do
    # Ensure LM is configured
    _ = get_lm()

    # Handle LM override
    if lm_override = opts[:lm] do
      # Temporarily set the LM for this execution
      current_lm = Application.get_env(:dspex, :current_lm)

      try do
        _result = set_lm(lm_override, api_key: current_lm[:api_key])

        with {:ok, adapter} <- get_adapter() do
          adapter.execute_program(program_id, inputs, opts)
        end
      after
        # Restore previous LM
        Application.put_env(:dspex, :current_lm, current_lm)
      end
    else
      with {:ok, adapter} <- get_adapter() do
        adapter.execute_program(program_id, inputs, opts)
      end
    end
  end

  @doc """
  Lists all programs.
  """
  @spec list_programs() :: {:ok, [String.t()]} | {:error, term()}
  def list_programs do
    with {:ok, adapter} <- get_adapter() do
      adapter.list_programs()
    end
  end

  @doc """
  Deletes a program.
  """
  @spec delete_program(String.t()) :: :ok | {:error, term()}
  def delete_program(program_id) do
    with {:ok, adapter} <- get_adapter() do
      adapter.delete_program(program_id)
    end
  end

  @doc """
  Gets information about a program.
  """
  @spec get_program_info(String.t()) :: {:ok, map()} | {:error, term()}
  def get_program_info(program_id) do
    with {:ok, adapter} <- get_adapter() do
      adapter.get_program_info(program_id)
    end
  end

  ## Private Functions

  defp get_adapter do
    case Registry.get_adapter() do
      nil -> {:error, "No adapter available"}
      adapter -> {:ok, adapter}
    end
  end

  defp get_default_api_key do
    System.get_env("GEMINI_API_KEY") ||
      Application.get_env(:dspex, :gemini_api_key) ||
      raise "No API key found. Set GEMINI_API_KEY environment variable."
  end
end
