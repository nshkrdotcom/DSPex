# DSPex DSPy Integration Examples

This directory contains examples demonstrating the comprehensive DSPy integration in DSPex.

## Prerequisites

1. Install DSPy and dependencies:
```bash
pip install dspy-ai litellm msgpack google-generativeai
```

2. Set up your Gemini API key:
```bash
export GOOGLE_API_KEY=your-gemini-api-key
# or
export GEMINI_API_KEY=your-gemini-api-key
```

Get your free Gemini API key at: https://makersuite.google.com/app/apikey

## Examples

### 00_dspy_mock_demo.exs
Basic demonstration that shows all DSPex wrappers are working correctly. This runs without requiring an LLM API key.

```bash
mix run examples/dspy/00_dspy_mock_demo.exs
```

### 01_question_answering_pipeline.exs
Comprehensive QA pipeline demonstrating:
- Basic prediction (Predict)
- Chain of thought reasoning (ChainOfThought)
- Multi-chain comparison (MultiChainComparison)
- Optimization (BootstrapFewShot)
- Assertions and constraints
- Evaluation framework

### 02_code_generation_system.exs
Advanced code generation system showing:
- Program of thought (ProgramOfThought)
- ReAct with tool usage
- Self-refinement (Retry)
- MIPRO optimization
- Settings management

### 03_document_analysis_rag.exs
Document analysis with retrieval demonstrating:
- Retrieval systems (ColBERTv2, vector databases)
- Advanced optimizers (MIPROv2, COPRO)
- Dataset management
- Complex pipelines

### 04_optimization_showcase.exs
Complete showcase of all optimizers and features:
- All optimizer comparisons
- Multiple LM providers
- Session management
- Performance benchmarking

## Running Without API Keys

The examples will work in "mock mode" when no Gemini API key is configured. They will:
- Create all DSPy modules successfully
- Show the expected "No LM is loaded" error when trying to execute
- Demonstrate that all wrappers are functioning correctly

To use real language models, you must set GOOGLE_API_KEY or GEMINI_API_KEY.

## Running With Real LLMs

All examples are configured to use **Gemini 2.0 Flash** by default. This is Google's latest, fastest, and most cost-effective model.

```elixir
# Automatically configured when GOOGLE_API_KEY is set
DSPex.LM.configure("google/gemini-2.0-flash-exp", api_key: System.get_env("GOOGLE_API_KEY"))
```

### Why Gemini 2.0 Flash?
- Fast response times
- Free tier available
- Excellent performance for DSPy tasks
- Native multimodal support

## Architecture

These examples demonstrate DSPex's dual implementation architecture:
- Python DSPy modules are called through Snakepit
- Native Elixir implementations will be used automatically when available
- The same API works for both implementations

See [DSPy Integration Guide](../../README_DSPY_INTEGRATION.md) for complete documentation.