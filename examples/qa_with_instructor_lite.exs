#!/usr/bin/env elixir

# Question-Answer example using InstructorLite adapter with Gemini Flash 2.0

Mix.install([
  {:dspex, path: Path.expand("..", __DIR__)},
  {:instructor_lite, "~> 1.0"},
  {:ecto, "~> 3.10"},
  {:sinter, "~> 0.0.1"}
])

defmodule QAWithInstructorLite do
  @moduledoc """
  Example of using DSPex with InstructorLite adapter for structured question-answering
  using Google's Gemini Flash 2.0 model.
  
  This example shows how to use InstructorLite with Gemini by providing a custom
  json_schema that conforms to Gemini's specific requirements.
  """
  
  # Define a simple schema for Q&A responses
  defmodule Answer do
    use Ecto.Schema
    use InstructorLite.Instruction
    import Ecto.Changeset
    
    @primary_key false
    embedded_schema do
      field :answer, :string
      field :confidence, :string
      field :sources, {:array, :string}, default: []
    end
    
    def changeset(answer, attrs) do
      answer
      |> cast(attrs, [:answer, :confidence, :sources])
      |> validate_required([:answer])
    end
    
    # Override json_schema to provide Gemini-compatible schema
    def json_schema do
      %{
        type: "object",
        required: ["answer"],
        properties: %{
          answer: %{type: "string"},
          confidence: %{type: "string"},
          sources: %{
            type: "array",
            items: %{type: "string"}
          }
        }
      }
    end
  end

  def run do
    IO.puts("\n=== Structured Q&A Example with InstructorLite Adapter ===\n")
    
    # Configure the LLM client with response model
    config = [
      adapter: :instructor_lite,
      provider: :gemini,
      api_key: System.get_env("GEMINI_API_KEY"),
      model: "gemini/gemini-2.0-flash-exp",
      response_model: Answer
    ]
    
    case DSPex.LLM.Client.new(config) do
      {:ok, client} ->
        # Test various questions
        questions = [
          "What is the capital of Japan?",
          "What are the three primary colors?",
          "What is 15 multiplied by 4?",
          "Name the planets in our solar system",
          "What year did World War II end?"
        ]
        
        Enum.each(questions, fn question ->
          IO.puts("\nQ: #{question}")
          
          case DSPex.LLM.Client.generate(client, question) do
            {:ok, response} ->
              # response.content will be an Answer struct
              IO.puts("A: #{response.content.answer}")
              if response.content.confidence do
                IO.puts("   Confidence: #{response.content.confidence}")
              end
              if response.content.sources != [] do
                IO.puts("   Sources: #{Enum.join(response.content.sources, ", ")}")
              end
              
            {:error, reason} ->
              IO.puts("Error: #{inspect(reason)}")
          end
        end)
        
        # Example with a more complex schema
        IO.puts("\n\n--- More Complex Structured Output ---\n")
        demo_complex_schema()
        
      {:error, :missing_api_key} ->
        IO.puts("Error: Please set GEMINI_API_KEY environment variable")
        IO.puts("You can get an API key from: https://makersuite.google.com/app/apikey")
        
      {:error, reason} ->
        IO.puts("Failed to create client: #{inspect(reason)}")
    end
  end
  
  # More complex schema example
  defmodule CountryInfo do
    use Ecto.Schema
    use InstructorLite.Instruction
    import Ecto.Changeset
    
    @primary_key false
    embedded_schema do
      field :country, :string
      field :capital, :string
      field :population, :integer
      field :language, :string
      field :currency, :string
    end
    
    def changeset(info, attrs) do
      info
      |> cast(attrs, [:country, :capital, :population, :language, :currency])
      |> validate_required([:country, :capital])
    end
    
    # Override json_schema to provide Gemini-compatible schema
    def json_schema do
      %{
        type: "object",
        required: ["country", "capital"],
        properties: %{
          country: %{type: "string"},
          capital: %{type: "string"},
          population: %{type: "integer"},
          language: %{type: "string"},
          currency: %{type: "string"}
        }
      }
    end
  end
  
  defp demo_complex_schema do
    config = [
      adapter: :instructor_lite,
      provider: :gemini,
      api_key: System.get_env("GEMINI_API_KEY"),
      model: "gemini/gemini-2.0-flash-exp",
      response_model: CountryInfo
    ]
    
    case DSPex.LLM.Client.new(config) do
      {:ok, client} ->
        prompt = "Give me information about France"
        
        IO.puts("Q: #{prompt}")
        
        case DSPex.LLM.Client.generate(client, prompt) do
          {:ok, response} ->
            info = response.content
            IO.puts("A: Country: #{info.country}")
            IO.puts("   Capital: #{info.capital}")
            IO.puts("   Population: #{info.population || "N/A"}")
            IO.puts("   Language: #{info.language || "N/A"}")
            IO.puts("   Currency: #{info.currency || "N/A"}")
            
          {:error, reason} ->
            IO.puts("Error: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        IO.puts("Failed to create client for complex schema: #{inspect(reason)}")
    end
  end
end

# Run the example
QAWithInstructorLite.run()