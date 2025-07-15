# DSPex Examples

This directory contains practical examples demonstrating how to use the DSPex library effectively. Each example is a self-contained Elixir application showcasing different aspects of DSPex functionality.

## Examples Overview

### 1. [Simple DSPy Example](simple_dspy_example/)
**Purpose**: Fundamental DSPex workflow demonstration  
**Difficulty**: Beginner  
**Features**:
- Language model configuration with `DSPex.set_lm/2`
- Program creation with QuestionAnswer signature
- Basic program execution with `DSPex.execute_program/2`
- Error handling examples

**Quick Start**:
```bash
cd simple_dspy_example
export GEMINI_API_KEY="your-api-key-here"
./run_simple_example.sh
```

### 2. [Dynamic Signature Example](signature_example/) 🆕
**Purpose**: Advanced dynamic signature capabilities beyond "question → answer"  
**Difficulty**: Intermediate  
**Features**:
- Multi-input signatures (text + style, text + target_language)
- Multi-output signatures (sentiment + summary + keywords + confidence)
- Dynamic signature generation and caching
- Real-world use cases (analysis, translation, enhancement, creative writing)
- Fallback mechanisms for reliability

**Quick Start**:
```bash
cd signature_example
export GEMINI_API_KEY="your-api-key-here"
./run_signature_example.sh
```

### 3. [Concurrent Pool Example](concurrent_pool_example/)
**Purpose**: Advanced concurrent operations with SessionPoolV2  
**Difficulty**: Advanced  
**Features**:
- Three concurrent operations (classification, translation, summarization)
- Session affinity for stateful operations
- Performance benchmarking (concurrent vs sequential)
- Comprehensive error handling and recovery
- Pool resource management

**Quick Start**:
```bash
cd concurrent_pool_example
export GEMINI_API_KEY="your-api-key-here"
./run_concurrent_example.sh
```

## Prerequisites

### General Requirements
- Elixir 1.18 or later
- Valid Gemini API key
- Python 3.8+ with dspy-ai package

### API Key Setup
Both examples require a Gemini API key:

```bash
export GEMINI_API_KEY="your-api-key-here"
```

You can get a free API key from [Google AI Studio](https://aistudio.google.com/app/apikey).

## Running Examples

### Option 1: Shell Scripts (Easiest)
Each example includes an executable shell script for easy CLI usage:

```bash
# Simple example
cd simple_dspy_example
./run_simple_example.sh [command]

# Dynamic signature example
cd signature_example
./run_signature_example.sh [command]

# Concurrent example  
cd concurrent_pool_example
./run_concurrent_example.sh [command]
```

### Option 2: Mix Tasks
Use Elixir Mix tasks directly:

```bash
# Simple example
cd simple_dspy_example
mix run_example [command]

# Dynamic signature example  
cd signature_example
mix run_all_examples [command]

# Concurrent example
cd concurrent_pool_example  
mix run_concurrent [command]
```

### Option 3: Interactive Mode
Start an IEx session and run functions interactively:

```bash
cd [example_directory]
iex -S mix

# Then run example functions
iex> SimpleDspyExample.run()
iex> SignatureExample.run_all_examples()
iex> ConcurrentPoolExample.run_concurrent_operations()
```

## Available Commands

### Simple DSPy Example
- `run` (default) - Complete workflow demonstration
- `models` - List available language models
- `errors` - Demonstrate error handling
- `help` - Show help message

### Dynamic Signature Example
- Interactive menu (default) - Choose specific examples
- `--all` - Run all signature examples
- `--text-analysis` - Text analysis with multiple outputs
- `--translation` - Multi-language translation
- `--enhancement` - Content improvement
- `--creative` - Creative writing generation
- `--help` - Show help message

### Concurrent Pool Example
- `concurrent` (default) - Run concurrent operations demo
- `affinity` - Demonstrate session affinity
- `benchmark` - Performance comparison (concurrent vs sequential)
- `errors` - Error handling demonstrations
- `help` - Show help message

## Learning Path

For new users, we recommend following this learning path:

1. **Start with Simple Example**: Understand basic DSPex concepts
   ```bash
   cd simple_dspy_example
   ./run_simple_example.sh
   ```

2. **Explore Available Models**: See what language models are supported
   ```bash
   ./run_simple_example.sh models
   ```

3. **Learn Error Handling**: Understand how DSPex handles failures
   ```bash
   ./run_simple_example.sh errors
   ```

4. **Try Dynamic Signatures**: Learn advanced signature capabilities
   ```bash
   cd ../signature_example
   ./run_signature_example.sh
   ```

5. **Explore Different Signature Types**: Test various use cases
   ```bash
   ./run_signature_example.sh # Choose from interactive menu
   ```

6. **Move to Concurrent Example**: Learn advanced pool features
   ```bash
   cd ../concurrent_pool_example
   ./run_concurrent_example.sh
   ```

7. **Test Session Affinity**: See how stateful operations work
   ```bash
   ./run_concurrent_example.sh affinity
   ```

8. **Benchmark Performance**: Compare concurrent vs sequential execution
   ```bash
   ./run_concurrent_example.sh benchmark
   ```

## Architecture Insights

### Simple Example Demonstrates
- **Basic DSPex workflow**: LM setup → program creation → execution
- **Error handling patterns**: Robust error checking and reporting
- **Configuration management**: Environment variable usage
- **Program signatures**: Input/output type definitions

### Dynamic Signature Example Demonstrates
- **Multi-input/output signatures**: Beyond "question → answer" patterns
- **Dynamic signature generation**: Runtime signature class creation
- **Signature caching**: Performance optimization through reuse
- **Real-world use cases**: Text analysis, translation, enhancement, creative writing
- **Fallback mechanisms**: Graceful degradation when dynamic signatures fail
- **Type safety**: Automatic type conversion and validation

### Concurrent Example Demonstrates
- **SessionPoolV2 capabilities**: Advanced pool management
- **Concurrent execution**: Parallel operation coordination
- **Session affinity**: Worker persistence for stateful operations
- **Performance optimization**: Resource utilization and timing
- **Error recovery**: Circuit breaker patterns and retry logic

## Configuration Examples

### Basic Configuration (Simple Example)
```elixir
# Set language model
DSPex.set_lm("gemini-1.5-flash", api_key: System.get_env("GEMINI_API_KEY"))

# Create program
program_config = %{
  signature: %{
    name: "QuestionAnswer",
    inputs: [%{name: "question", type: "string"}],
    outputs: [%{name: "answer", type: "string"}]
  }
}
```

### Dynamic Signature Configuration (Signature Example)
```elixir
# Multi-input, multi-output signature
signature = %{
  name: "TextAnalysisSignature",
  description: "Comprehensive text analysis",
  inputs: [
    %{name: "text", type: "string", description: "Input text to analyze"},
    %{name: "style", type: "string", description: "Analysis style"}
  ],
  outputs: [
    %{name: "sentiment", type: "string", description: "Detected sentiment"},
    %{name: "summary", type: "string", description: "Text summary"},
    %{name: "keywords", type: "string", description: "Key terms"},
    %{name: "confidence_score", type: "string", description: "Confidence level"}
  ]
}

# Create program with dynamic signature
{:ok, prog_id} = adapter.create_program(%{
  id: "analysis_program",
  signature: signature
})

# Execute with multiple inputs
inputs = %{text: "Sample text", style: "detailed"}
{:ok, result} = adapter.execute_program(prog_id, inputs)
```

### Advanced Configuration (Concurrent Example)
```elixir
# Enhanced workers with session affinity
config :dspex, DSPex.PythonBridge.SessionPoolV2,
  worker_module: DSPex.PythonBridge.PoolWorkerV2Enhanced,
  pool_size: 4,
  overflow: 2

# Execute with session affinity
SessionPoolV2.execute_in_session(session_id, :predict, args)
```

## Troubleshooting

### Common Issues

1. **Missing API Key**
   ```
   Error: GEMINI_API_KEY environment variable is not set
   ```
   **Solution**: Set your API key with `export GEMINI_API_KEY="your-key"`

2. **Python Dependencies**
   ```
   Error: dspy-ai package not found
   ```
   **Solution**: Install with `pip install dspy-ai`

3. **Compilation Errors**
   ```
   Error: mix deps.get failed
   ```
   **Solution**: Ensure you're in the correct example directory

4. **Port Communication Issues**
   ```
   Error: Python bridge connection failed
   ```
   **Solution**: Check Python installation and PATH

### Getting Help

- **Example Help**: Run `./run_[example]_example.sh help`
- **DSPex Documentation**: See main project README
- **API Reference**: Check module documentation with `h ModuleName` in IEx

## Next Steps

After completing these examples:

1. **Implement Your Own Signatures**: Create custom input/output definitions beyond the provided examples
2. **Experiment with Different Models**: Try various Gemini model variants and compare performance
3. **Combine Dynamic Signatures with Pooling**: Use advanced signatures with SessionPoolV2 for production
4. **Optimize Pool Configuration**: Tune pool sizes for your workload
5. **Build Production Applications**: Apply patterns to real-world scenarios
6. **Contribute Examples**: Share your own examples with the community

## Contributing

If you create additional examples or improvements:

1. Follow the existing pattern of self-contained applications
2. Include comprehensive documentation and error handling
3. Add both CLI and interactive usage options
4. Test with various Gemini API keys and configurations
5. Submit a pull request with your contributions