# Troubleshooting Gemini Integration with DSPex

## Issue: "No LM is loaded" Despite Configuring Gemini

Even though Gemini is successfully configured (API key is shown), DSPy modules report "No LM is loaded" when trying to execute.

### Root Cause

The issue occurs due to how DSPy/LiteLLM handles API keys for different providers:

1. DSPy uses LiteLLM under the hood for LLM connections
2. LiteLLM expects the Gemini API key to be in the environment variable `GOOGLE_API_KEY` or `GEMINI_API_KEY`
3. Even if you pass `api_key` to the LM constructor, LiteLLM might not use it correctly for Gemini
4. DSPy modules check for a configured LM at execution time, not creation time

### Current Behavior

1. `DSPex.LM.configure()` successfully creates a `dspy.LM` instance
2. It calls `dspy.configure(lm=...)` to set it globally
3. BUT: When modules are created, they have `lm=None` by default
4. Execution fails because the module's `lm` attribute is not set

### Solutions

#### Solution 1: Ensure Correct API Key
```bash
# First, verify your API key works
export GOOGLE_API_KEY=your-actual-gemini-api-key

# Test with curl
curl -H "Content-Type: application/json" \
     -H "x-goog-api-key: $GOOGLE_API_KEY" \
     -X POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent \
     -d '{"contents":[{"parts":[{"text":"Hello"}]}]}'
```

#### Solution 2: Check DSPy Version
```bash
pip install --upgrade dspy-ai
```

#### Solution 3: Manual LM Configuration
In Python/DSPy directly:
```python
import dspy
from dspy.clients import LM

# Configure Gemini
lm = LM(model="google/gemini-2.0-flash-exp", api_key="your-key")
dspy.configure(lm=lm)

# Now create modules
predict = dspy.Predict("question -> answer")
result = predict(question="What is 2+2?")
```

### Current Workaround

The examples demonstrate what DSPex would do with a properly configured LM. To see real results:

1. Ensure your Gemini API key is valid
2. Use the Python DSPy directly to verify it works
3. The DSPex wrappers will work once the underlying connection is established

### Future Improvements

1. **Better LM Propagation**: Ensure modules inherit the global LM configuration
2. **Connection Validation**: Add explicit LM connection testing
3. **Error Messages**: Provide clearer diagnostics when LM configuration fails

### Testing Your Setup

Run this test to diagnose the issue:
```bash
mix run examples/dspy/test_lm_config.exs
```

This will show:
- Whether the LM instance is created successfully
- If DSPy's global configuration is working
- Where the configuration breaks down