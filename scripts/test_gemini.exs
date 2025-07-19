# Simple script to test Gemini integration
# Run with: mix run scripts/test_gemini.exs

require Logger

alias DSPex.LLM.Client

# Check if API key is set
unless System.get_env("GEMINI_API_KEY") do
  Logger.error("Please set GEMINI_API_KEY environment variable")
  System.halt(1)
end

Logger.info("Creating Gemini client with default configuration...")

case Client.new() do
  {:ok, client} ->
    Logger.info("Client created successfully!")
    Logger.info("Adapter: #{client.adapter_type}")
    Logger.info("Provider: #{client.provider}")
    Logger.info("Model: #{client.config.model}")
    
    Logger.info("\nNote: InstructorLite requires a response_model for structured output")
    Logger.info("For simple text generation, use the HTTP adapter instead")
    
    # Test with HTTP adapter for simple text
    Logger.info("\nTesting simple text generation with HTTP adapter...")
    {:ok, http_client} = Client.new(
      adapter: :http, 
      provider: :gemini,
      api_key: System.get_env("GEMINI_API_KEY")
    )
    
    case Client.generate(http_client, "Write a haiku about Elixir programming") do
      {:ok, response} ->
        Logger.info("Response received!")
        Logger.info("Content: #{inspect(response.content)}")
        Logger.info("Provider: #{response.provider}")
        
      {:error, reason} ->
        Logger.error("Generation failed: #{inspect(reason)}")
    end
    
  {:error, reason} ->
    Logger.error("Failed to create client: #{inspect(reason)}")
end

# Test with structured output if we have the schemas compiled
if Code.ensure_loaded?(DSPex.TestSchemas.SimpleResponse) do
  Logger.info("\nTesting structured output...")
  
  {:ok, client} = Client.new(response_model: DSPex.TestSchemas.SimpleResponse)
  
  case Client.generate(client, "Analyze: 'Elixir makes concurrent programming enjoyable!'") do
    {:ok, response} ->
      Logger.info("Structured response: #{inspect(response.content)}")
      
    {:error, reason} ->
      Logger.error("Structured generation failed: #{inspect(reason)}")
  end
end