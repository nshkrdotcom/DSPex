"""
DSPex Helper Module for Python-side operations.

This module provides helper functions that need to be executed on the Python side
to properly configure DSPy with stored language models.
"""

import dspy

# This will be populated by the bridge
stored_objects = {}

def configure_dspy_with_stored_lm(lm_id='default_lm'):
    """Configure DSPy with a stored language model object."""
    if lm_id not in stored_objects:
        raise ValueError(f"Language model '{lm_id}' not found in stored objects")
    
    lm = stored_objects[lm_id]
    dspy.configure(lm=lm)
    return {"status": "ok", "message": f"Configured DSPy with {lm}"}

def create_and_configure_lm(model, api_key, **kwargs):
    """Create a language model and configure DSPy in one step."""
    # Create the LM
    lm = dspy.LM(model=model, api_key=api_key, **kwargs)
    
    # Store it for reference
    stored_objects['default_lm'] = lm
    
    # Configure DSPy
    dspy.configure(lm=lm)
    
    return {"status": "ok", "lm_id": "default_lm", "model": model}

def get_dspy_settings():
    """Get current DSPy settings."""
    settings = dspy.settings
    return {
        "lm": str(settings.lm) if settings.lm else None,
        "rm": str(settings.rm) if settings.rm else None,
        "adapter": str(settings.adapter) if settings.adapter else None,
        "configured": settings.lm is not None
    }

def test_lm_configured():
    """Test if a language model is properly configured."""
    try:
        # Try to create a simple predict module
        predict = dspy.Predict("question -> answer")
        # Try to use it
        result = predict(question="test")
        return {"status": "ok", "configured": True}
    except AssertionError as e:
        if "No LM is loaded" in str(e):
            return {"status": "error", "configured": False, "error": "No LM is loaded"}
        raise
    except Exception as e:
        return {"status": "error", "configured": False, "error": str(e)}