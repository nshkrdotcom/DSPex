# Dynamic Signature System Implementation Plan
**Date:** 2025-07-15  
**Status:** Ready for Implementation  
**Priority:** High  
**Estimated Duration:** 2-3 weeks  

## Executive Summary

This document provides a comprehensive, staged implementation plan for the DSPex dynamic signature system. The plan transforms the current hardcoded `question → answer` pattern into a flexible, field-aware system that fully leverages the Elixir signature DSL.

## Current State vs Target State

### Current State ❌
- Python bridge hardcodes all operations to `question -> answer`
- Rich signature metadata is discarded during conversion
- Field names like `text`, `sentiment`, `language` are ignored
- Cannot support multi-input/output signatures

### Target State ✅
- Dynamic signature generation based on Elixir definitions
- Full field name and type preservation
- Support for arbitrary input/output combinations
- Performance-optimized with caching
- Backward compatible with existing code

## Implementation Stages

### Stage 0: Prerequisites & Setup (Day 0)
**Duration:** 2-4 hours  
**Risk Level:** Low  

#### Objectives
- Validate development environment
- Create test infrastructure
- Set up monitoring for implementation progress

#### Deliverables
1. **Test Suite Foundation**
   ```elixir
   # test/dspex/dynamic_signature_test.exs
   defmodule DSPex.DynamicSignatureTest do
     use DSPex.TestCase
     
     @moduletag :dynamic_signature
     
     # Placeholder for Stage 1 tests
   end
   ```

2. **Baseline Performance Metrics**
   ```elixir
   # Capture current Q&A performance for comparison
   {:ok, baseline_time} = measure_execution_time(:question_answer_signature)
   ```

3. **Feature Flag Setup**
   ```elixir
   # config/config.exs
   config :dspex, :features,
     dynamic_signatures: System.get_env("DSPEX_DYNAMIC_SIGNATURES", "false") == "true"
   ```

#### Success Criteria
- [ ] Test file created and runs (even if empty)
- [ ] Baseline metrics documented
- [ ] Feature flag toggles correctly

---

### Stage 1: Python Bridge Core - Signature Factory (Days 1-2)
**Duration:** 2 days  
**Risk Level:** Medium  

#### Objectives
- Implement dynamic signature class generation in Python
- Add caching mechanism for performance
- Maintain backward compatibility

#### Deliverables

1. **Enhanced `dspy_bridge.py` with Signature Factory**
   ```python
   # priv/python/dspy_bridge.py
   
   class DSPyBridge:
       def __init__(self, mode="standalone", worker_id=None):
           self.programs = {}
           self.signature_cache = {}  # NEW: Performance optimization
           self.feature_flags = {"dynamic_signatures": False}  # NEW
           # ... existing init code ...
   
       def _create_signature_class(self, signature_def: Dict[str, Any]) -> type:
           """
           Dynamically generates a dspy.Signature class from Elixir definition.
           
           Example input:
           {
               "name": "SentimentAnalysis",
               "inputs": [{"name": "text", "type": "string", "description": "Text to analyze"}],
               "outputs": [{"name": "sentiment", "type": "string", "description": "Detected sentiment"}]
           }
           """
           class_name = signature_def.get('name', 'DynamicSignature').replace(".", "")
           docstring = signature_def.get('description', 'Dynamically generated signature')
           
           # Build class attributes
           attrs = {'__doc__': docstring}
           
           # Add input fields
           for field in signature_def.get('inputs', []):
               field_name = field.get('name')
               if field_name:
                   attrs[field_name] = dspy.InputField(
                       desc=field.get('description', f'Input field: {field_name}')
                   )
           
           # Add output fields
           for field in signature_def.get('outputs', []):
               field_name = field.get('name')
               if field_name:
                   attrs[field_name] = dspy.OutputField(
                       desc=field.get('description', f'Output field: {field_name}')
                   )
           
           # Create the dynamic class
           DynamicSigClass = type(class_name, (dspy.Signature,), attrs)
           return DynamicSigClass
   
       def _get_or_create_signature_class(self, signature_def: Dict[str, Any]) -> type:
           """Cache-aware signature class retrieval."""
           # Create deterministic cache key
           cache_key = json.dumps(signature_def, sort_keys=True)
           
           if cache_key not in self.signature_cache:
               debug_log(f"Creating new signature class for: {signature_def.get('name')}")
               self.signature_cache[cache_key] = self._create_signature_class(signature_def)
           
           return self.signature_cache[cache_key]
   ```

2. **Updated Program Creation with Feature Flag**
   ```python
   def create_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
       program_id = args.get('id')
       signature_def = args.get('signature', {})
       use_dynamic = args.get('use_dynamic_signature', self.feature_flags['dynamic_signatures'])
       
       try:
           if use_dynamic and signature_def:
               # NEW: Dynamic signature path
               sig_class = self._get_or_create_signature_class(signature_def)
               program = dspy.Predict(sig_class)
               debug_log(f"Created dynamic program with signature: {sig_class.__name__}")
           else:
               # EXISTING: Fallback to Q&A
               program = dspy.Predict("question -> answer")
               debug_log("Using legacy Q&A signature")
               
       except Exception as e:
           # Resilient fallback
           debug_log(f"Dynamic signature failed: {e}, falling back to Q&A")
           program = dspy.Predict("question -> answer")
           sig_class = None
       
       # Store program info
       program_info = {
           'program': program,
           'signature_def': signature_def,
           'is_dynamic': use_dynamic and sig_class is not None,
           'created_at': time.time()
       }
       
       self.programs[program_id] = program_info
       return {'program_id': program_id, 'status': 'created'}
   ```

3. **Dynamic Execution Handler**
   ```python
   def execute_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
       program_id = args.get('program_id')
       inputs = args.get('inputs', {})
       
       if program_id not in self.programs:
           raise ValueError(f"Program not found: {program_id}")
       
       program_info = self.programs[program_id]
       program = program_info['program']
       signature_def = program_info['signature_def']
       is_dynamic = program_info.get('is_dynamic', False)
       
       try:
           if is_dynamic:
               # Dynamic execution with field mapping
               result = program(**inputs)
               
               # Extract outputs by field name
               output_fields = [f['name'] for f in signature_def.get('outputs', [])]
               outputs = {}
               for field_name in output_fields:
                   if hasattr(result, field_name):
                       outputs[field_name] = getattr(result, field_name)
                   else:
                       outputs[field_name] = None
                       debug_log(f"Warning: Output field '{field_name}' not found in result")
               
               return outputs
           else:
               # Legacy Q&A execution
               question = inputs.get('question', '')
               result = program(question=question)
               return {'answer': result.answer}
               
       except Exception as e:
           debug_log(f"Execution error: {e}")
           raise ValueError(f"Program execution failed: {str(e)}")
   ```

#### Test Cases
```python
# test_dynamic_signatures.py (Python-side testing)

def test_create_sentiment_signature():
    bridge = DSPyBridge()
    sig_def = {
        "name": "SentimentAnalysis",
        "inputs": [{"name": "text", "type": "string"}],
        "outputs": [{"name": "sentiment", "type": "string"}]
    }
    
    sig_class = bridge._create_signature_class(sig_def)
    assert hasattr(sig_class, 'text')
    assert hasattr(sig_class, 'sentiment')

def test_signature_caching():
    bridge = DSPyBridge()
    sig_def = {"name": "Test", "inputs": [], "outputs": []}
    
    class1 = bridge._get_or_create_signature_class(sig_def)
    class2 = bridge._get_or_create_signature_class(sig_def)
    assert class1 is class2  # Same object from cache
```

#### Success Criteria
- [ ] Dynamic signature classes generate correctly
- [ ] Caching reduces redundant class creation
- [ ] Feature flag controls dynamic vs legacy behavior
- [ ] All existing Q&A tests still pass

---

### Stage 2: Elixir Adapter Enhancement (Days 3-4)
**Duration:** 2 days  
**Risk Level:** Low-Medium  

#### Objectives
- Enhance signature conversion to preserve all metadata
- Update PythonPort adapter to send rich payloads
- Add validation layer for inputs

#### Deliverables

1. **Enhanced Signature Conversion**
   ```elixir
   # lib/dspex/adapters/python_port.ex
   
   defp convert_signature(signature_module) when is_atom(signature_module) do
     signature = signature_module.__signature__()
     
     %{
       "name" => to_string(signature_module),
       "description" => get_module_doc(signature_module),
       "inputs" => convert_fields(signature.inputs),
       "outputs" => convert_fields(signature.outputs),
       "metadata" => %{
         "module" => to_string(signature_module),
         "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
       }
     }
   end
   
   defp convert_fields(fields) do
     Enum.map(fields, fn {name, type, constraints} ->
       %{
         "name" => to_string(name),
         "type" => convert_type(type),
         "description" => Keyword.get(constraints, :description, ""),
         "required" => Keyword.get(constraints, :required, true),
         "constraints" => convert_constraints(constraints)
       }
     end)
   end
   
   defp convert_type(:string), do: "string"
   defp convert_type(:integer), do: "integer"
   defp convert_type(:float), do: "float"
   defp convert_type(:boolean), do: "boolean"
   defp convert_type(:list), do: "array"
   defp convert_type(other), do: to_string(other)
   ```

2. **Input Validation Module**
   ```elixir
   # lib/dspex/signature/validator.ex
   
   defmodule DSPex.Signature.Validator do
     @moduledoc """
     Validates inputs against signature definitions.
     """
     
     def validate_inputs(inputs, signature_module) when is_atom(signature_module) do
       signature = signature_module.__signature__()
       validate_inputs(inputs, signature)
     end
     
     def validate_inputs(inputs, %{inputs: input_fields}) do
       with :ok <- check_required_fields(inputs, input_fields),
            :ok <- validate_field_types(inputs, input_fields) do
         {:ok, inputs}
       end
     end
     
     defp check_required_fields(inputs, fields) do
       required = fields
         |> Enum.filter(fn {_, _, constraints} -> 
           Keyword.get(constraints, :required, true) 
         end)
         |> Enum.map(fn {name, _, _} -> name end)
       
       missing = required -- Map.keys(inputs)
       
       case missing do
         [] -> :ok
         fields -> {:error, "Missing required fields: #{inspect(fields)}"}
       end
     end
     
     defp validate_field_types(inputs, fields) do
       # Type validation implementation
       :ok
     end
   end
   ```

3. **Updated Create Program with Dynamic Flag**
   ```elixir
   def create_program(%{signature: signature} = args, opts) do
     port = ensure_port_started(opts)
     
     # Feature flag check
     use_dynamic = Keyword.get(opts, :dynamic_signatures, false)
     
     converted_signature = convert_signature(signature)
     
     command = %{
       "command" => "create_program",
       "args" => Map.merge(args, %{
         "signature" => converted_signature,
         "use_dynamic_signature" => use_dynamic
       })
     }
     
     case send_command(port, command, opts) do
       {:ok, result} -> 
         Logger.info("Created program with #{if use_dynamic, do: "dynamic", else: "legacy"} signature")
         {:ok, result}
       error -> error
     end
   end
   ```

#### Test Cases
```elixir
# test/dspex/signature/validator_test.exs

defmodule DSPex.Signature.ValidatorTest do
  use ExUnit.Case
  
  defmodule TestSignature do
    use DSPex.Signature
    signature text: :string -> sentiment: :string
  end
  
  test "validates required fields" do
    assert {:error, _} = Validator.validate_inputs(%{}, TestSignature)
    assert {:ok, _} = Validator.validate_inputs(%{text: "hello"}, TestSignature)
  end
end
```

#### Success Criteria
- [ ] Rich signature metadata passes to Python
- [ ] Input validation catches missing fields
- [ ] Feature flag propagates correctly
- [ ] Existing tests remain green

---

### Stage 3: Integration Testing & Validation (Days 5-6)
**Duration:** 2 days  
**Risk Level:** Low  

#### Objectives
- Comprehensive end-to-end testing
- Performance benchmarking
- Documentation of new capabilities

#### Deliverables

1. **End-to-End Integration Tests**
   ```elixir
   # test/dspex/dynamic_signature_integration_test.exs
   
   defmodule DSPex.DynamicSignatureIntegrationTest do
     use DSPex.TestCase, async: false
     
     setup do
       # Enable dynamic signatures for tests
       Application.put_env(:dspex, :features, dynamic_signatures: true)
       :ok
     end
     
     describe "sentiment analysis signature" do
       defmodule SentimentSignature do
         use DSPex.Signature
         @moduledoc "Analyzes sentiment of text"
         signature text: :string -> 
                   sentiment: :string,
                   confidence: :float
       end
       
       test "executes with proper field mapping" do
         # Create program
         {:ok, program_id} = DSPex.create_program(%{
           id: "sentiment_test",
           signature: SentimentSignature
         })
         
         # Execute with named input
         {:ok, result} = DSPex.execute_program(program_id, %{
           text: "I absolutely love this new feature!"
         })
         
         # Verify named outputs
         assert Map.has_key?(result, :sentiment)
         assert Map.has_key?(result, :confidence)
         assert result.sentiment in ["positive", "negative", "neutral"]
         assert is_float(result.confidence)
       end
     end
     
     describe "translation signature" do
       defmodule TranslationSignature do
         use DSPex.Signature
         signature source_text: :string,
                   target_language: :string ->
                   translated_text: :string
       end
       
       test "handles multiple inputs correctly" do
         {:ok, program_id} = DSPex.create_program(%{
           id: "translation_test",
           signature: TranslationSignature
         })
         
         {:ok, result} = DSPex.execute_program(program_id, %{
           source_text: "Hello world",
           target_language: "French"
         })
         
         assert Map.has_key?(result, :translated_text)
         assert is_binary(result.translated_text)
       end
     end
   end
   ```

2. **Performance Benchmarks**
   ```elixir
   # bench/dynamic_signature_bench.exs
   
   defmodule DynamicSignatureBench do
     use Benchfella
     
     @legacy_program_id "legacy_qa"
     @dynamic_program_id "dynamic_sig"
     
     setup_all do
       # Create both program types
       {:ok, _} = DSPex.create_program(%{
         id: @legacy_program_id,
         signature: "question -> answer"
       }, dynamic_signatures: false)
       
       {:ok, _} = DSPex.create_program(%{
         id: @dynamic_program_id,
         signature: BenchSignature
       }, dynamic_signatures: true)
     end
     
     bench "legacy Q&A execution" do
       DSPex.execute_program(@legacy_program_id, %{
         question: "What is the meaning of life?"
       })
     end
     
     bench "dynamic signature execution" do
       DSPex.execute_program(@dynamic_program_id, %{
         text: "What is the meaning of life?"
       })
     end
   end
   ```

3. **Migration Examples**
   ```elixir
   # examples/signature_migration.exs
   
   # Before: Using Q&A format
   defmodule OldWay do
     def analyze_sentiment(text) do
       {:ok, result} = DSPex.execute(%{
         question: "What is the sentiment of: #{text}"
       })
       
       # Parse answer to extract sentiment
       parse_sentiment_from_answer(result.answer)
     end
   end
   
   # After: Using dynamic signatures
   defmodule NewWay do
     defmodule SentimentSignature do
       use DSPex.Signature
       signature text: :string -> sentiment: :string, confidence: :float
     end
     
     def analyze_sentiment(text) do
       {:ok, program_id} = DSPex.create_program(%{
         signature: SentimentSignature
       })
       
       {:ok, result} = DSPex.execute_program(program_id, %{text: text})
       
       # Direct access to structured output
       {result.sentiment, result.confidence}
     end
   end
   ```

#### Success Criteria
- [ ] All integration tests pass
- [ ] Performance overhead < 10% vs legacy
- [ ] Migration examples work correctly
- [ ] No regression in existing functionality

---

### Stage 4: Production Rollout (Days 7-8)
**Duration:** 2 days  
**Risk Level:** Medium-High  

#### Objectives
- Gradual feature flag rollout
- Monitor for issues
- Update documentation

#### Deliverables

1. **Rollout Configuration**
   ```elixir
   # config/releases.exs
   
   config :dspex, :features,
     dynamic_signatures: System.get_env("DSPEX_DYNAMIC_SIGNATURES", "false") == "true"
   
   config :dspex, :rollout,
     dynamic_signatures_percentage: String.to_integer(System.get_env("DYNAMIC_SIG_ROLLOUT", "0"))
   ```

2. **Monitoring & Metrics**
   ```elixir
   # lib/dspex/metrics/signature_metrics.ex
   
   defmodule DSPex.Metrics.SignatureMetrics do
     def record_signature_type(type) do
       :telemetry.execute(
         [:dspex, :signature, :usage],
         %{count: 1},
         %{type: type}
       )
     end
     
     def record_signature_performance(type, duration) do
       :telemetry.execute(
         [:dspex, :signature, :performance],
         %{duration: duration},
         %{type: type}
       )
     end
   end
   ```

3. **Documentation Updates**
   ```markdown
   # docs/DYNAMIC_SIGNATURES.md
   
   ## Dynamic Signatures in DSPex
   
   ### Quick Start
   ```elixir
   defmodule MySignature do
     use DSPex.Signature
     signature input_text: :string -> 
               category: :string,
               score: :float
   end
   
   {:ok, prog} = DSPex.create_program(%{signature: MySignature})
   {:ok, result} = DSPex.execute_program(prog, %{input_text: "Hello"})
   # result = %{category: "greeting", score: 0.95}
   ```
   ```

#### Success Criteria
- [ ] Feature flag controls rollout percentage
- [ ] Metrics show adoption rate
- [ ] No production incidents
- [ ] Documentation is comprehensive

---

### Stage 5: Cleanup & Optimization (Days 9-10)
**Duration:** 2 days  
**Risk Level:** Low  

#### Objectives
- Remove legacy code paths
- Optimize performance bottlenecks
- Finalize documentation

#### Deliverables

1. **Performance Optimizations**
   ```python
   # Optimize signature cache with LRU
   from functools import lru_cache
   
   @lru_cache(maxsize=100)
   def _cached_signature_class(cache_key: str, sig_json: str) -> type:
       sig_def = json.loads(sig_json)
       return _create_signature_class(sig_def)
   ```

2. **Legacy Code Deprecation**
   ```elixir
   # Add deprecation warnings
   def create_program(%{signature: "question -> answer"} = args, opts) do
     Logger.warn("Q&A signature format is deprecated. Please use DSPex.Signature modules.")
     # ... existing code ...
   end
   ```

3. **Final Test Suite**
   ```elixir
   # Comprehensive test coverage report
   mix test --cover
   # Should show > 95% coverage for signature modules
   ```

---

## Risk Mitigation Strategies

### Technical Risks
1. **DSPy Compatibility Issues**
   - **Mitigation:** Extensive testing with various DSPy versions
   - **Fallback:** Maintain Q&A compatibility layer

2. **Performance Degradation**
   - **Mitigation:** Benchmark at each stage
   - **Fallback:** Caching and optimization strategies

3. **Breaking Changes**
   - **Mitigation:** Feature flags and gradual rollout
   - **Fallback:** Quick rollback capability

### Rollback Plan
```bash
# Quick rollback if issues arise
export DSPEX_DYNAMIC_SIGNATURES=false
# Restart application
```

---

## Success Metrics

### Functional Metrics
- ✅ All signature types work correctly
- ✅ 100% backward compatibility
- ✅ Zero regression in existing tests

### Performance Metrics
- ✅ < 10% overhead vs legacy system
- ✅ < 50ms signature class generation
- ✅ Cache hit rate > 90%

### Adoption Metrics
- ✅ 50% of new programs use dynamic signatures (Week 1)
- ✅ 80% adoption rate (Week 2)
- ✅ Full migration complete (Week 4)

---

## Timeline Summary

| Stage | Duration | Risk | Key Deliverable |
|-------|----------|------|-----------------|
| Stage 0 | 2-4 hours | Low | Test infrastructure |
| Stage 1 | 2 days | Medium | Python signature factory |
| Stage 2 | 2 days | Low-Medium | Elixir adapter enhancement |
| Stage 3 | 2 days | Low | Integration testing |
| Stage 4 | 2 days | Medium-High | Production rollout |
| Stage 5 | 2 days | Low | Optimization & cleanup |

**Total Duration:** 10-11 days

---

## Conclusion

This implementation plan provides a low-risk, staged approach to delivering the dynamic signature system. With feature flags, comprehensive testing, and gradual rollout, we can confidently transform DSPex's signature capabilities while maintaining stability.

**Next Action:** Begin Stage 0 prerequisites, then proceed to Stage 1 Python bridge implementation.