defmodule DSPex.LLM.Adapter do
  @moduledoc """
  Behaviour defining the LLM adapter interface.

  This allows DSPex to work with multiple LLM providers and libraries
  through a common interface, making it easy to switch implementations.
  """

  @type client :: map()
  @type prompt :: String.t() | list(map())
  @type options :: keyword()
  @type response :: map()

  @doc """
  Configure the adapter with a specific provider.

  ## Parameters

    * `provider` - The LLM provider (e.g., :openai, :anthropic, :gemini)
    * `config` - Provider-specific configuration
    
  ## Returns

    * `{:ok, client}` - Configured client for making requests
    * `{:error, reason}` - Configuration error
  """
  @callback configure(provider :: atom(), config :: map()) ::
              {:ok, client()} | {:error, term()}

  @doc """
  Generate a response from the LLM.

  ## Parameters

    * `client` - The configured client
    * `prompt` - The prompt (string or message list)
    * `options` - Generation options (temperature, max_tokens, etc.)
    
  ## Returns

    * `{:ok, response}` - The generated response
    * `{:error, reason}` - Generation error
  """
  @callback generate(client(), prompt(), options()) ::
              {:ok, response()} | {:error, term()}

  @doc """
  Stream a response from the LLM.

  This is optional - adapters that don't support streaming can return an error.

  ## Parameters

    * `client` - The configured client
    * `prompt` - The prompt (string or message list)
    * `options` - Generation options
    
  ## Returns

    * `{:ok, stream}` - An enumerable stream of response chunks
    * `{:error, reason}` - Streaming error or not supported
  """
  @callback stream(client(), prompt(), options()) ::
              {:ok, Enumerable.t()} | {:error, term()}

  @doc """
  Generate responses for multiple prompts in a batch.

  This is optional - adapters can fall back to sequential generation.

  ## Parameters

    * `client` - The configured client
    * `prompts` - List of prompts
    * `options` - Generation options
    
  ## Returns

    * `{:ok, responses}` - List of generated responses
    * `{:error, reason}` - Batch generation error
  """
  @callback batch(client(), prompts :: list(prompt()), options()) ::
              {:ok, list(response())} | {:error, term()}

  @optional_callbacks stream: 3, batch: 3
end
