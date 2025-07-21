defmodule DSPex.Models do
  @moduledoc """
  Model configuration registry for DSPex.
  
  Defines available models and their provider prefixes for use with DSPy.
  """
  
  @models %{
    # Gemini models
    "gemini-2.0-flash-lite" => %{
      provider: "gemini",
      full_name: "gemini/gemini-2.0-flash-lite"
    },
    "gemini-1.5-pro" => %{
      provider: "gemini", 
      full_name: "gemini/gemini-1.5-pro"
    },
    "gemini-1.5-flash" => %{
      provider: "gemini",
      full_name: "gemini/gemini-1.5-flash"
    },
    
    # OpenAI models
    "gpt-4" => %{
      provider: "openai",
      full_name: "openai/gpt-4"
    },
    "gpt-4-turbo" => %{
      provider: "openai",
      full_name: "openai/gpt-4-turbo"
    },
    "gpt-3.5-turbo" => %{
      provider: "openai",
      full_name: "openai/gpt-3.5-turbo"
    },
    
    # Anthropic models
    "claude-3-opus" => %{
      provider: "anthropic",
      full_name: "anthropic/claude-3-opus"
    },
    "claude-3-sonnet" => %{
      provider: "anthropic",
      full_name: "anthropic/claude-3-sonnet"
    },
    
    # Mock models for testing
    "mock-gemini" => %{
      provider: "mock",
      full_name: "mock/gemini"
    }
  }
  
  @doc """
  Get the full model name with provider prefix for DSPy.
  
  ## Examples
  
      iex> DSPex.Models.get_full_name("gemini-2.0-flash-lite")
      "gemini/gemini-2.0-flash-lite"
      
      iex> DSPex.Models.get_full_name("gpt-4")
      "openai/gpt-4"
  """
  def get_full_name(model_name) do
    case @models[model_name] do
      %{full_name: full_name} -> full_name
      nil -> model_name  # Return as-is if not in registry
    end
  end
  
  @doc """
  Get the provider for a model.
  """
  def get_provider(model_name) do
    case @models[model_name] do
      %{provider: provider} -> provider
      nil -> nil
    end
  end
  
  @doc """
  Check if a model is registered.
  """
  def registered?(model_name) do
    Map.has_key?(@models, model_name)
  end
  
  @doc """
  List all registered models.
  """
  def list_models do
    Map.keys(@models)
  end
  
  @doc """
  List models by provider.
  """
  def list_models_by_provider(provider) do
    @models
    |> Enum.filter(fn {_, config} -> config.provider == provider end)
    |> Enum.map(fn {name, _} -> name end)
  end
end