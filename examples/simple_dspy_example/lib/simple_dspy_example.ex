defmodule SimpleDspyExample do
  @moduledoc """
  A simple end-to-end demonstration of the DSPex library.
  
  This example shows how to:
  1. Configure a language model
  2. Create a program with a Question & Answer signature
  3. Execute the program with sample inputs
  
  ## Usage
  
  Make sure you have a valid GEMINI_API_KEY environment variable set:
  
      export GEMINI_API_KEY="your-api-key-here"
  
  Then run the example:
  
      SimpleDspyExample.run()
  
  """

  require Logger

  @doc """
  Runs the complete DSPex workflow demonstration.
  
  This function performs the following steps:
  1. Sets up the language model (Gemini 1.5 Flash)
  2. Creates a QuestionAnswer program
  3. Executes the program with a sample question
  4. Returns the result
  
  ## Returns
  
  - `{:ok, result}` - Success with the answer from the language model
  - `{:error, reason}` - Error during execution
  
  ## Examples
  
      iex> SimpleDspyExample.run()
      {:ok, %{answer: "Paris"}}
  
  """
  @spec run() :: {:ok, map()} | {:error, term()}
  def run do
    Logger.info("Starting DSPex simple example...")

    with :ok <- setup_language_model(),
         {:ok, program_id} <- create_question_answer_program(),
         {:ok, result} <- execute_sample_question(program_id) do
      Logger.info("Example completed successfully!")
      Logger.info("Result: #{inspect(result)}")
      {:ok, result}
    else
      error ->
        Logger.error("Example failed: #{inspect(error)}")
        error
    end
  end

  @doc """
  Sets up the language model configuration.
  
  Uses Gemini 1.5 Flash with the API key from environment variables.
  """
  @spec setup_language_model() :: :ok | {:error, term()}
  def setup_language_model do
    Logger.info("Setting up language model: gemini-1.5-flash")
    
    try do
      api_key = System.get_env("GEMINI_API_KEY")
      
      unless api_key do
        raise "GEMINI_API_KEY environment variable not set"
      end
      
      DSPex.set_lm("gemini-1.5-flash", api_key: api_key)
      Logger.info("Language model configured successfully")
      :ok
    rescue
      error ->
        Logger.error("Failed to configure language model: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Creates a program with a QuestionAnswer signature.
  
  The signature defines:
  - Input: question (string)
  - Output: answer (string)
  
  ## Returns
  
  - `{:ok, program_id}` - Success with the program ID
  - `{:error, reason}` - Error during program creation
  """
  @spec create_question_answer_program() :: {:ok, String.t()} | {:error, term()}
  def create_question_answer_program do
    Logger.info("Creating QuestionAnswer program...")
    
    signature = %{
      name: "QuestionAnswer",
      inputs: [%{name: "question", type: "string"}],
      outputs: [%{name: "answer", type: "string"}]
    }
    
    program_config = %{
      signature: signature,
      id: "simple_qa_example"
    }
    
    case DSPex.create_program(program_config) do
      {:ok, program_id} ->
        Logger.info("Program created with ID: #{program_id}")
        {:ok, program_id}
      
      error ->
        Logger.error("Failed to create program: #{inspect(error)}")
        error
    end
  end

  @doc """
  Executes the program with a sample question.
  
  ## Parameters
  
  - `program_id` - The ID of the program to execute
  
  ## Returns
  
  - `{:ok, result}` - Success with the execution result
  - `{:error, reason}` - Error during execution
  """
  @spec execute_sample_question(String.t()) :: {:ok, map()} | {:error, term()}
  def execute_sample_question(program_id) do
    question = "What is the capital of France?"
    Logger.info("Executing program with question: #{question}")
    
    inputs = %{question: question}
    
    case DSPex.execute_program(program_id, inputs) do
      {:ok, result} ->
        Logger.info("Execution successful!")
        {:ok, result}
      
      error ->
        Logger.error("Failed to execute program: #{inspect(error)}")
        error
    end
  end

  @doc """
  Demonstrates error handling by attempting to execute with invalid inputs.
  
  This shows how the DSPex library handles validation errors.
  """
  @spec demonstrate_error_handling() :: {:error, term()}
  def demonstrate_error_handling do
    Logger.info("Demonstrating error handling...")
    
    # Try to execute without setting up the LM first
    case DSPex.execute_program("nonexistent_program", %{invalid: "input"}) do
      {:ok, _result} ->
        Logger.warning("Unexpected success in error demonstration")
        :ok
      
      error ->
        Logger.info("Expected error occurred: #{inspect(error)}")
        error
    end
  end

  @doc """
  Lists all available language models.
  
  ## Examples
  
      iex> SimpleDspyExample.list_models()
      ["gemini-1.5-flash", "gemini-1.5-pro", "gemini/gemini-2.0-flash-exp"]
  
  """
  @spec list_models() :: [String.t()]
  def list_models do
    models = DSPex.list_supported_models()
    Logger.info("Available models: #{inspect(models)}")
    models
  end
end