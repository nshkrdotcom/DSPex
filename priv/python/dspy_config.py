"""
DSPy configuration helper for DSPex.

This module provides functions to properly configure DSPy with LM instances.
"""
import dspy
import os


def configure_lm(model, api_key=None, **kwargs):
    """Configure DSPy with a language model."""
    # Set API key in environment if provided
    if api_key:
        if 'gemini' in model or 'google' in model:
            os.environ['GOOGLE_API_KEY'] = api_key
        elif 'openai' in model:
            os.environ['OPENAI_API_KEY'] = api_key
        elif 'anthropic' in model:
            os.environ['ANTHROPIC_API_KEY'] = api_key
    
    # Create LM instance
    lm = dspy.LM(model=model, **kwargs)
    
    # Configure DSPy
    dspy.configure(lm=lm)
    
    return {"configured": True, "model": model}


def get_current_lm():
    """Get the currently configured LM."""
    if hasattr(dspy.settings, 'lm') and dspy.settings.lm:
        return {
            "configured": True,
            "model": getattr(dspy.settings.lm, 'model', 'unknown'),
            "type": type(dspy.settings.lm).__name__
        }
    return {"configured": False}


def create_module_with_lm(module_type, *args, **kwargs):
    """Create a DSPy module ensuring it has access to the LM."""
    # Get the module class
    if module_type == "Predict":
        module_class = dspy.Predict
    elif module_type == "ChainOfThought":
        module_class = dspy.ChainOfThought
    elif module_type == "ProgramOfThought":
        module_class = dspy.ProgramOfThought
    elif module_type == "ReAct":
        module_class = dspy.ReAct
    else:
        raise ValueError(f"Unknown module type: {module_type}")
    
    # Create the module
    module = module_class(*args, **kwargs)
    
    # Ensure it has the LM configured
    if hasattr(module, 'lm') and module.lm is None:
        module.lm = dspy.settings.lm
    
    return module