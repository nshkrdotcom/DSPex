#!/usr/bin/env python3
"""Test DSPy with Gemini model to debug the JSON adapter issue."""

import os
import dspy

# Configure API key
api_key = os.environ.get('GEMINI_API_KEY')
if not api_key:
    print("Error: GEMINI_API_KEY not set")
    exit(1)

print(f"Using API key: {api_key[:10]}...")

# Try to configure DSPy with Gemini
try:
    # Method 1: Direct configuration
    lm = dspy.LM(
        model="gemini/gemini-2.0-flash-lite",
        api_key=api_key,
        temperature=0.7
    )
    dspy.configure(lm=lm)
    print("✓ DSPy configured successfully")
    
    # Test with a simple Predict
    predictor = dspy.Predict("question -> answer")
    result = predictor(question="What is 2+2?")
    print(f"Result: {result}")
    print(f"Answer: {result.answer}")
    
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()