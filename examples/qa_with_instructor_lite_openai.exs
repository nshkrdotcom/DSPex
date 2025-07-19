#!/usr/bin/env elixir

# Question-Answer example using InstructorLite adapter with OpenAI

Mix.install([
  {:dspex, path: Path.expand("..", __DIR__)},
  {:instructor_lite, "~> 1.0"},
  {:ecto, "~> 3.10"},
  {:sinter, "~> 0.0.1"}
])

defmodule QAWithInstructorLiteOpenAI do
  @moduledoc """
  Example of using DSPex with InstructorLite adapter for structured question-answering
  using OpenAI's GPT models.
  
  This example shows InstructorLite's proper functionality with a compatible provider.
  """
  
  # Define a simple schema for Q&A responses
  defmodule Answer do
    use Ecto.Schema
    import Ecto.Changeset
    
    @primary_key false
    embedded_schema do
      field :answer, :string
      field :confidence, :string
      field :reasoning, :string
    end
    
    def changeset(answer, attrs) do
      answer
      |> cast(attrs, [:answer, :confidence, :reasoning])
      |> validate_required([:answer])
    end
  end

  def run do
    IO.puts("\n=== Structured Q&A Example with InstructorLite + OpenAI ===\n")
    
    # Check if OpenAI API key is available
    if System.get_env("OPENAI_API_KEY") do
      # Configure the LLM client with response model
      config = [
        adapter: :instructor_lite,
        provider: :openai,
        api_key: System.get_env("OPENAI_API_KEY"),
        model: "gpt-3.5-turbo",
        response_model: Answer
      ]
      
      case DSPex.LLM.Client.new(config) do
        {:ok, client} ->
          # Test various questions
          questions = [
            "What is the capital of Japan?",
            "What are the three primary colors?",
            "What is 15 multiplied by 4?"
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
                if response.content.reasoning do
                  IO.puts("   Reasoning: #{response.content.reasoning}")
                end
                
              {:error, reason} ->
                IO.puts("Error: #{inspect(reason)}")
            end
          end)
          
        {:error, reason} ->
          IO.puts("Failed to create client: #{inspect(reason)}")
      end
    else
      IO.puts("This example requires an OpenAI API key.")
      IO.puts("Please set OPENAI_API_KEY environment variable to run this example.")
      IO.puts("\nNote: InstructorLite currently has compatibility issues with Gemini's")
      IO.puts("JSON schema requirements. This example demonstrates proper functionality")
      IO.puts("with OpenAI, which fully supports the JSON schema format used by InstructorLite.")
    end
  end
end

# Run the example
QAWithInstructorLiteOpenAI.run()