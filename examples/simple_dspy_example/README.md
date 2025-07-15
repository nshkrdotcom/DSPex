# Simple DSPy Example

This example demonstrates the fundamental DSPex workflow: configuring a language model, creating a program, and executing it.

## Overview

This is a minimal, easy-to-understand demonstration that shows how to:

1. **Set the Language Model**: Initialize the LM provider using `DSPex.set_lm/2`
2. **Create a Program**: Define a simple program with a basic Question & Answer signature using `DSPex.create_program/1`
3. **Execute the Program**: Run the program with sample inputs using `DSPex.execute_program/2`

## Prerequisites

- Elixir 1.18 or later
- Valid Gemini API key

## Setup

1. **Set your API key**:
   ```bash
   export GEMINI_API_KEY="your-api-key-here"
   ```

2. **Install dependencies**:
   ```bash
   mix deps.get
   ```

## Usage

### CLI Usage (Recommended)

The easiest way to run the example is using the provided shell script:

```bash
# Run the complete workflow
./run_simple_example.sh

# List available models
./run_simple_example.sh models

# Demonstrate error handling
./run_simple_example.sh errors

# Show help
./run_simple_example.sh help
```

Or use Mix tasks directly:

```bash
# Run the complete workflow
mix run_example

# List available models
mix run_example models

# Demonstrate error handling
mix run_example errors
```

### Interactive Usage (IEx)

You can also run the example interactively:

1. **Start the application**:
   ```bash
   iex -S mix
   ```

2. **Run the complete workflow demonstration**:
   ```elixir
   SimpleDspyExample.run()
   ```

This will:
- Configure Gemini 1.5 Flash as the language model
- Create a QuestionAnswer program
- Execute it with the question "What is the capital of France?"
- Return the result

### Individual Functions

You can also run individual parts of the workflow:

```elixir
# Setup language model
SimpleDspyExample.setup_language_model()

# Create a program
{:ok, program_id} = SimpleDspyExample.create_question_answer_program()

# Execute with a custom question
SimpleDspyExample.execute_sample_question(program_id)

# List available models
SimpleDspyExample.list_models()

# Demonstrate error handling
SimpleDspyExample.demonstrate_error_handling()
```

## Program Signature

The example uses a simple QuestionAnswer signature:

```elixir
signature = %{
  name: "QuestionAnswer",
  inputs: [%{name: "question", type: "string"}],
  outputs: [%{name: "answer", type: "string"}]
}
```

## Expected Output

When you run `SimpleDspyExample.run()`, you should see output similar to:

```
[info] Starting DSPex simple example...
[info] Setting up language model: gemini-1.5-flash
[info] Language model configured successfully
[info] Creating QuestionAnswer program...
[info] Program created with ID: simple_qa_example
[info] Executing program with question: What is the capital of France?
[info] Execution successful!
[info] Example completed successfully!
[info] Result: %{answer: "Paris"}
```

## Error Handling

The example includes comprehensive error handling for common scenarios:

- Missing API key
- Invalid model configuration
- Program creation failures
- Execution errors

## API Functions Used

This example demonstrates the following DSPex APIs:

- `DSPex.set_lm/2` - Configure language model
- `DSPex.create_program/1` - Create a new program
- `DSPex.execute_program/2` - Execute a program
- `DSPex.list_supported_models/0` - List available models

## Next Steps

After running this basic example, try the [Concurrent Pool Example](../concurrent_pool_example/) to see advanced features like session management and concurrent operations.