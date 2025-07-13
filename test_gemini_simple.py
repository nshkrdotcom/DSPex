#!/usr/bin/env python3
"""
Simple test for Gemini API with DSPy
"""

import os
import sys

def test_gemini_direct():
    """Test Gemini API directly first."""
    try:
        import google.generativeai as genai
        
        api_key = os.environ.get('GEMINI_API_KEY')
        if not api_key:
            print("❌ GEMINI_API_KEY not found")
            return False
            
        genai.configure(api_key=api_key)
        
        # Test with the specific model mentioned
        model_name = "gemini-2.0-flash-exp"  # Updated model name
        try:
            model = genai.GenerativeModel(model_name)
            response = model.generate_content("What is 2+2? Answer with just the number.")
            print(f"✅ Gemini direct test successful: {response.text.strip()}")
            return True
        except Exception as e:
            print(f"❌ Gemini model test failed: {e}")
            # Try alternative model names
            alt_models = ["gemini-1.5-flash", "gemini-pro"]
            for alt_model in alt_models:
                try:
                    print(f"🔄 Trying alternative model: {alt_model}")
                    model = genai.GenerativeModel(alt_model)
                    response = model.generate_content("What is 2+2?")
                    print(f"✅ Success with {alt_model}: {response.text.strip()}")
                    return True
                except Exception as alt_e:
                    print(f"❌ {alt_model} failed: {alt_e}")
            return False
            
    except ImportError:
        print("❌ google.generativeai not installed")
        return False

def test_dspy_with_gemini():
    """Test DSPy with Gemini using the correct approach."""
    try:
        import dspy
        
        api_key = os.environ.get('GEMINI_API_KEY')
        if not api_key:
            print("❌ GEMINI_API_KEY not found")
            return False
        
        # Try different ways to configure DSPy with Gemini
        try:
            # Method 1: Using Google provider directly in DSPy
            lm = dspy.Google(model="gemini-1.5-flash", api_key=api_key)
            dspy.configure(lm=lm)
            
            # Create a simple signature
            class BasicQA(dspy.Signature):
                """Answer questions briefly."""
                question = dspy.InputField()
                answer = dspy.OutputField()
            
            # Test it
            predictor = dspy.Predict(BasicQA)
            result = predictor(question="What is the capital of France?")
            print(f"✅ DSPy with Gemini successful: {result.answer}")
            return True
            
        except Exception as e1:
            print(f"⚠️ Method 1 failed: {e1}")
            
            # Method 2: Try with LiteLLM approach
            try:
                lm = dspy.LM(model="gemini/gemini-1.5-flash", api_key=api_key)
                dspy.configure(lm=lm)
                
                predictor = dspy.Predict(BasicQA)
                result = predictor(question="What is 2+2?")
                print(f"✅ DSPy with LiteLLM/Gemini successful: {result.answer}")
                return True
                
            except Exception as e2:
                print(f"⚠️ Method 2 failed: {e2}")
                print("DSPy might not have direct Gemini support yet.")
                print("But Gemini API works directly, so we can integrate manually.")
                return False
                
    except ImportError:
        print("❌ DSPy not installed")
        return False

if __name__ == "__main__":
    print("🧪 Testing Gemini integration...")
    
    # Test 1: Direct Gemini API
    print("\n1. Testing direct Gemini API...")
    gemini_works = test_gemini_direct()
    
    # Test 2: DSPy + Gemini
    print("\n2. Testing DSPy + Gemini...")
    dspy_works = test_dspy_with_gemini()
    
    print("\n" + "="*50)
    if gemini_works:
        print("✅ Gemini API is working!")
        if dspy_works:
            print("✅ DSPy + Gemini integration is working!")
            print("🎉 Full setup complete!")
        else:
            print("⚠️ DSPy + Gemini needs custom integration")
            print("But we can build a custom bridge in our Elixir code!")
    else:
        print("❌ Gemini API is not working")
        print("Please check your GEMINI_API_KEY")
        sys.exit(1)