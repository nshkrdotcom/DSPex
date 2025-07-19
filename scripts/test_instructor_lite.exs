# Test InstructorLite with Gemini for structured output
# Run with: mix run scripts/test_instructor_lite.exs

require Logger

# First compile the test schemas
Code.require_file("test/support/test_schemas.ex")

alias DSPex.LLM.Client
alias DSPex.TestSchemas.{SimpleResponse, MathProblem, CodeExample}

# Check if API key is set
unless System.get_env("GEMINI_API_KEY") do
  Logger.error("Please set GEMINI_API_KEY environment variable")
  System.halt(1)
end

Logger.info("Testing InstructorLite with Gemini for structured output...")

# Test 1: Simple structured response
Logger.info("\n1. Testing SimpleResponse schema...")
{:ok, client} = Client.new(
  adapter: :instructor_lite,
  provider: :gemini,
  response_model: SimpleResponse,
  api_key: System.get_env("GEMINI_API_KEY")
)

case Client.generate(client, "Analyze this text: 'Elixir is amazing for building scalable systems!'") do
  {:ok, response} ->
    result = response.content
    Logger.info("✓ SimpleResponse result:")
    Logger.info("  Message: #{result.message}")
    Logger.info("  Sentiment: #{result.sentiment}")
    
  {:error, reason} ->
    Logger.error("✗ SimpleResponse failed: #{inspect(reason)}")
end

# Test 2: Math problem solving
Logger.info("\n2. Testing MathProblem schema...")
{:ok, math_client} = Client.new(
  response_model: MathProblem,
  api_key: System.get_env("GEMINI_API_KEY")
)

prompt = "Solve step by step: A car travels 150 miles in 3 hours. What is its average speed in mph?"

case Client.generate(math_client, prompt) do
  {:ok, response} ->
    result = response.content
    Logger.info("✓ MathProblem result:")
    Logger.info("  Problem: #{result.problem}")
    Logger.info("  Solution: #{result.solution} mph")
    Logger.info("  Steps: #{Enum.join(result.steps, " → ")}")
    Logger.info("  Explanation: #{result.explanation}")
    
  {:error, reason} ->
    Logger.error("✗ MathProblem failed: #{inspect(reason)}")
end

# Test 3: Code generation
Logger.info("\n3. Testing CodeExample schema...")
{:ok, code_client} = Client.new(
  response_model: CodeExample,
  api_key: System.get_env("GEMINI_API_KEY")
)

case Client.generate(code_client, "Show me an Elixir function to calculate fibonacci numbers") do
  {:ok, response} ->
    result = response.content
    Logger.info("✓ CodeExample result:")
    Logger.info("  Language: #{result.language}")
    Logger.info("  Complexity: #{result.complexity}")
    Logger.info("  Explanation: #{result.explanation}")
    Logger.info("  Code:\n#{result.code}")
    
  {:error, reason} ->
    Logger.error("✗ CodeExample failed: #{inspect(reason)}")
end

Logger.info("\nAll tests completed!")