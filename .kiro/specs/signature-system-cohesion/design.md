# Design Document

## Overview

This design implements a cohesive signature system that bridges DSPex's rich Elixir signature DSL with Python DSPy's dynamic signature capabilities. The solution replaces the hardcoded "question → answer" pattern with a dynamic signature factory that preserves field names and types across the language boundary.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Elixir DSPex  │    │  Signature      │    │  Python DSPy    │
│   Signature     │───▶│  Converter      │───▶│  Dynamic        │
│   Definition    │    │  Pipeline       │    │  Signature      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Core Components

1. **Elixir Signature Converter** - Converts DSPex signature modules to rich metadata
2. **Python Signature Factory** - Dynamically creates DSPy signature classes
3. **Caching Layer** - Performance optimization for repeated signature usage
4. **Fallback System** - Graceful degradation to Q&A format when needed

## Components and Interfaces

### Elixir Side Enhancement

**TypeConverter Module** (`lib/dspex/adapters/type_converter.ex`)
- Converts signature modules to rich metadata dictionaries
- Extracts field names, types, and descriptions
- Maintains backward compatibility with existing formats

```elixir
def convert_signature_to_format(signature_module, :python, _opts) do
  signature = signature_module.__signature__()
  %{
    "name" => to_string(signature.module),
    "description" => get_module_doc(signature.module),
    "inputs" => convert_fields_to_python_format(signature.inputs),
    "outputs" => convert_fields_to_python_format(signature.outputs)
  }
end
```

### Python Bridge Enhancement

**Dynamic Signature Factory** (`priv/python/dspy_bridge.py`)
- Creates DSPy signature classes from Elixir metadata
- Implements caching for performance
- Provides fallback to Q&A format

```python
def _create_signature_class(self, signature_def: Dict[str, Any]) -> type:
    class_name = signature_def.get('name', 'DynamicSignature')
    attrs = {'__doc__': signature_def.get('description', '')}
    
    # Add input fields
    for field in signature_def.get('inputs', []):
        field_name = field.get('name')
        if field_name:
            attrs[field_name] = dspy.InputField(desc=field.get('description', ''))
    
    # Add output fields  
    for field in signature_def.get('outputs', []):
        field_name = field.get('name')
        if field_name:
            attrs[field_name] = dspy.OutputField(desc=field.get('description', ''))
    
    return type(class_name, (dspy.Signature,), attrs)
```

## Data Models

### Signature Metadata Format

```json
{
  "name": "SentimentAnalysis",
  "description": "Analyze sentiment of input text",
  "inputs": [
    {
      "name": "text",
      "type": "string", 
      "description": "Text to analyze"
    }
  ],
  "outputs": [
    {
      "name": "sentiment",
      "type": "string",
      "description": "Detected sentiment"
    },
    {
      "name": "confidence", 
      "type": "float",
      "description": "Confidence score"
    }
  ]
}
```

### Program Execution Flow

1. **Create Program**: Elixir sends signature metadata to Python bridge
2. **Generate Class**: Python bridge creates dynamic DSPy signature class
3. **Cache Class**: Generated class is cached for reuse
4. **Execute Program**: Inputs are mapped by field name using `**inputs`
5. **Extract Outputs**: Results are extracted by field name using `getattr`

## Error Handling

### Graceful Fallback Strategy

- **Primary Path**: Dynamic signature creation and execution
- **Fallback Path**: Q&A format when dynamic creation fails
- **Error Logging**: Clear messages for debugging signature issues

```python
try:
    DynamicSignatureClass = self._get_or_create_signature_class(signature_def)
    program = dspy.Predict(DynamicSignatureClass)
except Exception as e:
    debug_log(f"Dynamic signature failed, falling back to Q&A: {e}")
    program = dspy.Predict("question -> answer")
```

### Validation Layer

- **Input Validation**: Ensure required fields are present
- **Type Checking**: Basic type validation for inputs
- **Error Messages**: Clear, actionable error descriptions

## Testing Strategy

### Unit Tests
- Signature conversion accuracy
- Dynamic class generation
- Caching behavior
- Fallback mechanisms

### Integration Tests
- End-to-end signature execution
- Multi-field input/output scenarios
- Performance benchmarks
- Error handling validation

### Test Cases
1. **Sentiment Analysis**: `text → sentiment, confidence`
2. **Translation**: `source_text, target_language → translated_text`
3. **Multi-Output**: `text → sentiment, language, keywords, summary`

## Performance Considerations

### Caching Strategy
- **Signature Class Cache**: Avoid regenerating identical classes
- **Cache Key**: Hash of signature definition for uniqueness
- **Memory Management**: Reasonable cache size limits

### Performance Targets
- **Conversion Overhead**: < 5ms per signature conversion
- **Cache Hit Rate**: > 90% for typical usage patterns
- **Memory Usage**: < 100MB for signature cache

## Migration Strategy

### Backward Compatibility
- Existing Q&A patterns continue working unchanged
- Gradual migration path for new signature types
- No breaking changes to current API

### Rollout Plan
1. **Phase 1**: Implement dynamic system alongside existing Q&A
2. **Phase 2**: Update examples to showcase new capabilities
3. **Phase 3**: Encourage migration through documentation
4. **Phase 4**: Mark Q&A as legacy (still supported)