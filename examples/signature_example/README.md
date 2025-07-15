# DSPex Dynamic Signature Example

This example demonstrates the powerful dynamic signature capabilities of DSPex, which allows you to define custom input/output fields beyond the basic "question → answer" pattern.

## What This Example Shows

- **Multi-Input Signatures**: Define multiple input fields (text, style, language)
- **Multi-Output Signatures**: Get multiple structured outputs (sentiment, summary, keywords, confidence)
- **Dynamic Field Generation**: No need to hardcode field names
- **Signature Caching**: Efficient reuse of generated signature classes
- **Fallback Mechanisms**: Graceful degradation when dynamic signatures fail

## Features Demonstrated

### 1. Text Analysis Signature
- **Inputs**: `text` (content to analyze), `style` (analysis style)
- **Outputs**: `sentiment`, `summary`, `keywords`, `confidence_score`

### 2. Translation Signature  
- **Inputs**: `text` (content to translate), `target_language`
- **Outputs**: `translated_text`, `source_language`, `confidence_score`

### 3. Content Enhancement Signature
- **Inputs**: `text` (original content), `enhancement_type`, `tone`
- **Outputs**: `enhanced_text`, `changes_made`, `readability_score`

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│   Elixir App    │───▶│  DSPex Bridge    │───▶│  Python DSPy        │
│                 │    │                  │    │                     │
│ Dynamic         │    │ TypeConverter    │    │ Dynamic Signature   │
│ Signatures      │    │ Enhanced Payload │    │ Factory & Caching   │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
```

## Key Benefits

1. **Flexibility**: Define any combination of input/output fields
2. **Type Safety**: Automatic type conversion and validation
3. **Performance**: Signature caching for efficiency
4. **Reliability**: Fallback to Q&A format when needed
5. **Extensibility**: Easy to add new signature patterns

## Running the Example

```bash
# Navigate to the signature example directory
cd examples/signature_example

# Install dependencies
mix deps.get

# Set your API key
export GEMINI_API_KEY="your-api-key-here"

# Run the interactive example
./run_signature_example.sh

# Or run specific examples
mix run_text_analysis
mix run_translation  
mix run_content_enhancement
```

## Example Output

```
🔍 Text Analysis Example:
Input: "The weather is absolutely beautiful today! Perfect for a picnic."
Style: "detailed"

✅ Results:
   Sentiment: positive
   Summary: Enthusiastic comment about perfect weather conditions for outdoor activities
   Keywords: weather, beautiful, picnic, outdoor
   Confidence: 0.95

🌍 Translation Example:
Input: "Hello, how are you today?"
Target: "spanish"

✅ Results:
   Translated: "Hola, ¿cómo estás hoy?"
   Source Language: english
   Confidence: 0.98
```

## Code Structure

- `lib/signature_example.ex` - Main application logic
- `lib/signature_example/cli.ex` - Command-line interface
- `lib/signature_example/signatures.ex` - Signature definitions
- `lib/mix/tasks/` - Mix tasks for running examples
- `test/` - Comprehensive test suite

## Technical Implementation

The dynamic signature system works by:

1. **Elixir Side**: Define signatures with multiple inputs/outputs
2. **Bridge Layer**: Convert to enriched Python payload format
3. **Python Side**: Generate DSPy signature classes dynamically
4. **Execution**: Use `**inputs` unpacking for flexible I/O
5. **Caching**: Store generated classes for performance

This replaces the old hardcoded "question → answer" approach with a flexible system that can handle any signature pattern.