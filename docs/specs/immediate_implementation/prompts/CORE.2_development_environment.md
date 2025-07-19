# Task CORE.2: Development Environment Setup

## Task Overview
**ID**: CORE.2  
**Component**: Core Infrastructure  
**Priority**: P0 (Critical)  
**Estimated Time**: 3 hours  
**Dependencies**: CORE.1 (Project Setup must be complete)  
**Status**: Not Started

## Objective
Set up a complete Python development environment with DSPy installed, create the necessary Snakepit Python scripts directory structure, document all environment variables, and create a comprehensive developer setup guide.

## Required Reading

### 1. Architecture Documentation
- **File**: `/home/home/p/g/n/dspex/CLAUDE.md`
  - Lines 1-50: Overview and Snakepit integration strategy
  - Lines 145-155: Configuration requirements

### 2. Snakepit Documentation
- Review Snakepit documentation at: https://hexdocs.pm/snakepit
- Understand Python process management requirements

### 3. DSPy Requirements
- DSPy GitHub: https://github.com/stanfordnlp/dspy
- Python version requirements (3.8+)
- DSPy dependencies

## Implementation Steps

### Step 1: Create Python Environment Structure
Create the following directory structure:

```bash
# Create Python environment directories
mkdir -p /home/home/p/g/n/dspex/python
mkdir -p /home/home/p/g/n/dspex/python/scripts
mkdir -p /home/home/p/g/n/dspex/python/venv
mkdir -p /home/home/p/g/n/dspex/.python-version
```

### Step 2: Set Up Python Virtual Environment
Create and configure Python virtual environment:

```bash
# Create virtual environment
cd /home/home/p/g/n/dspex
python3 -m venv python/venv

# Activate environment
source python/venv/bin/activate

# Upgrade pip
pip install --upgrade pip
```

### Step 3: Create requirements.txt
Create `/home/home/p/g/n/dspex/python/requirements.txt`:

```
# DSPy and core dependencies
dspy-ai>=2.4.0
openai>=1.0.0
anthropic>=0.18.0
google-generativeai>=0.3.0

# Serialization
msgpack>=1.0.0
pyarrow>=14.0.0

# Utilities
python-dotenv>=1.0.0
requests>=2.31.0
tenacity>=8.2.0

# Development
pytest>=7.4.0
black>=23.0.0
ruff>=0.1.0
mypy>=1.5.0

# Optional: Vector stores
chromadb>=0.4.0
qdrant-client>=1.7.0
```

### Step 4: Install Python Dependencies
```bash
# With virtual environment activated
pip install -r python/requirements.txt

# Verify DSPy installation
python -c "import dspy; print(f'DSPy version: {dspy.__version__}')"
```

### Step 5: Create Snakepit Bootstrap Script
Create `/home/home/p/g/n/dspex/python/scripts/bootstrap.py`:

```python
#!/usr/bin/env python3
"""
Bootstrap script for Snakepit Python processes.
Initializes the DSPy environment and provides helper functions.
"""

import sys
import os
import json
import msgpack
import traceback
from typing import Any, Dict

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import dspy

class SnakepitBridge:
    """Bridge between Elixir and Python DSPy processes."""
    
    def __init__(self):
        self.modules = {}
        self._initialize_dspy()
    
    def _initialize_dspy(self):
        """Initialize DSPy with default settings."""
        # This will be configured from Elixir side
        pass
    
    def register_module(self, name: str, module_class):
        """Register a DSPy module for use from Elixir."""
        self.modules[name] = module_class
    
    def call(self, module_name: str, method: str, args: Dict[str, Any]) -> Any:
        """Call a method on a registered module."""
        if module_name not in self.modules:
            raise ValueError(f"Module {module_name} not registered")
        
        module = self.modules[module_name]
        if not hasattr(module, method):
            raise ValueError(f"Method {method} not found on {module_name}")
        
        return getattr(module, method)(**args)
    
    def handle_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Handle a request from Elixir."""
        try:
            result = self.call(
                request['module'],
                request['method'],
                request.get('args', {})
            )
            return {
                'status': 'ok',
                'result': result
            }
        except Exception as e:
            return {
                'status': 'error',
                'error': str(e),
                'traceback': traceback.format_exc()
            }

# Global bridge instance
bridge = SnakepitBridge()

# Main entry point for Snakepit
if __name__ == "__main__":
    # This will be called by Snakepit
    import msgpack
    
    while True:
        try:
            # Read msgpack-encoded request from stdin
            packed = sys.stdin.buffer.read()
            if not packed:
                break
                
            request = msgpack.unpackb(packed, raw=False)
            response = bridge.handle_request(request)
            
            # Write msgpack-encoded response to stdout
            sys.stdout.buffer.write(msgpack.packb(response))
            sys.stdout.buffer.flush()
            
        except Exception as e:
            error_response = {
                'status': 'error',
                'error': str(e),
                'traceback': traceback.format_exc()
            }
            sys.stdout.buffer.write(msgpack.packb(error_response))
            sys.stdout.buffer.flush()
```

### Step 6: Create Environment Variables Documentation
Create `/home/home/p/g/n/dspex/.env.example`:

```bash
# Python Environment
PYTHON_PATH=/home/home/p/g/n/dspex/python/venv/bin/python
PYTHONPATH=/home/home/p/g/n/dspex/python

# Snakepit Configuration
SNAKEPIT_POOL_SIZE=4
SNAKEPIT_MAX_OVERFLOW=4

# LLM API Keys (optional, for testing)
OPENAI_API_KEY=your-api-key-here
ANTHROPIC_API_KEY=your-api-key-here
GOOGLE_API_KEY=your-api-key-here

# Development Settings
DSPEX_ENV=development
DSPEX_LOG_LEVEL=debug
```

### Step 7: Create Developer Setup Guide
Create `/home/home/p/g/n/dspex/docs/DEVELOPER_SETUP.md`:

```markdown
# DSPex Developer Setup Guide

## Prerequisites

- Elixir 1.16+ and Erlang/OTP 26+
- Python 3.8+ 
- Git
- A Unix-like environment (Linux, macOS, WSL2)

## Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-org/dspex.git
   cd dspex
   ```

2. **Set up Elixir dependencies**
   ```bash
   mix deps.get
   mix compile
   ```

3. **Set up Python environment**
   ```bash
   # Create Python virtual environment
   python3 -m venv python/venv
   
   # Activate virtual environment
   source python/venv/bin/activate
   
   # Install Python dependencies
   pip install -r python/requirements.txt
   ```

4. **Configure environment**
   ```bash
   # Copy example environment file
   cp .env.example .env
   
   # Edit .env with your settings
   # Update PYTHON_PATH to point to your virtual environment Python
   ```

5. **Verify installation**
   ```bash
   # Run Elixir tests
   mix test
   
   # Verify Python setup
   python python/scripts/bootstrap.py --verify
   ```

## Environment Variables

### Required Variables

- `PYTHON_PATH`: Path to Python executable (must have DSPy installed)
  - Example: `/home/user/dspex/python/venv/bin/python`

### Optional Variables

- `SNAKEPIT_POOL_SIZE`: Number of Python processes (default: 4)
- `SNAKEPIT_MAX_OVERFLOW`: Maximum additional processes (default: 4)
- `DSPEX_ENV`: Environment (development/test/production)
- `DSPEX_LOG_LEVEL`: Logging level (debug/info/warning/error)

### LLM API Keys (for testing)

- `OPENAI_API_KEY`: OpenAI API key
- `ANTHROPIC_API_KEY`: Anthropic API key
- `GOOGLE_API_KEY`: Google AI API key

## Development Workflow

### Running Tests

```bash
# Run all tests
mix test

# Run specific test layers
mix test.fast        # Mock tests only
mix test.protocol    # Protocol tests
mix test.integration # Full integration tests

# Run Python tests
python -m pytest python/tests/
```

### Code Quality

```bash
# Elixir code quality
mix format           # Format code
mix credo           # Static analysis
mix dialyzer        # Type checking

# Python code quality
black python/       # Format Python code
ruff python/        # Lint Python code
mypy python/        # Type check Python
```

### Interactive Development

```bash
# Elixir REPL with project loaded
iex -S mix

# Python REPL with DSPy loaded
source python/venv/bin/activate
python
>>> import dspy
>>> from python.scripts.bootstrap import bridge
```

## Troubleshooting

### Python Environment Issues

1. **DSPy not found**
   - Ensure virtual environment is activated
   - Verify `pip list | grep dspy`
   - Check PYTHONPATH includes project python directory

2. **Snakepit connection errors**
   - Verify PYTHON_PATH points to correct executable
   - Check Python script permissions
   - Review Snakepit logs

3. **Module import errors**
   - Ensure all requirements installed
   - Check Python version (3.8+)
   - Verify virtual environment activation

### Performance Issues

1. **Slow startup**
   - Reduce SNAKEPIT_POOL_SIZE during development
   - Use mock adapters for testing

2. **Memory usage**
   - Monitor Python process memory
   - Adjust pool settings
   - Enable process recycling

## Additional Resources

- [DSPy Documentation](https://github.com/stanfordnlp/dspy)
- [Snakepit Documentation](https://hexdocs.pm/snakepit)
- [Project Architecture](../CLAUDE.md)
```

### Step 8: Create Verification Script
Create `/home/home/p/g/n/dspex/python/scripts/verify_setup.py`:

```python
#!/usr/bin/env python3
"""Verify Python environment setup for DSPex."""

import sys
import importlib
import subprocess

def check_python_version():
    """Check Python version is 3.8+."""
    version = sys.version_info
    if version.major < 3 or (version.major == 3 and version.minor < 8):
        print(f"❌ Python {version.major}.{version.minor} detected. Need 3.8+")
        return False
    print(f"✅ Python {version.major}.{version.minor}.{version.micro}")
    return True

def check_module(module_name, display_name=None):
    """Check if a module is installed."""
    display = display_name or module_name
    try:
        module = importlib.import_module(module_name)
        version = getattr(module, '__version__', 'unknown')
        print(f"✅ {display}: {version}")
        return True
    except ImportError:
        print(f"❌ {display}: not installed")
        return False

def main():
    """Run all verification checks."""
    print("DSPex Python Environment Verification")
    print("=" * 40)
    
    all_good = True
    
    # Check Python version
    all_good &= check_python_version()
    
    # Check required modules
    print("\nRequired Modules:")
    all_good &= check_module('dspy', 'DSPy')
    all_good &= check_module('msgpack', 'MessagePack')
    all_good &= check_module('openai', 'OpenAI')
    
    # Check optional modules
    print("\nOptional Modules:")
    check_module('anthropic', 'Anthropic')
    check_module('google.generativeai', 'Google AI')
    check_module('chromadb', 'ChromaDB')
    
    # Check bootstrap script
    print("\nBootstrap Script:")
    try:
        from scripts.bootstrap import bridge
        print("✅ Bootstrap script loads correctly")
    except Exception as e:
        print(f"❌ Bootstrap script error: {e}")
        all_good = False
    
    print("\n" + "=" * 40)
    if all_good:
        print("✅ All required components verified!")
        return 0
    else:
        print("❌ Some issues found. Please fix before proceeding.")
        return 1

if __name__ == "__main__":
    sys.exit(main())
```

## Acceptance Criteria

- [ ] Python 3.8+ environment created and activated
- [ ] DSPy installed and importable in Python environment
- [ ] Snakepit Python scripts directory structure created
- [ ] Bootstrap script created and functional
- [ ] All environment variables documented in .env.example
- [ ] Developer setup guide written and comprehensive
- [ ] Verification script confirms all components installed
- [ ] Python dependencies installable via requirements.txt

## Expected Deliverables

1. Python virtual environment at `/python/venv/`
2. Complete `python/requirements.txt` with all dependencies
3. Bootstrap script at `python/scripts/bootstrap.py`
4. Environment variables documented in `.env.example`
5. Developer setup guide at `docs/DEVELOPER_SETUP.md`
6. Verification script at `python/scripts/verify_setup.py`
7. All Python dependencies successfully installed

## Verification Commands

Run these commands to verify completion:

```bash
# Activate Python environment
source python/venv/bin/activate

# Run verification script
python python/scripts/verify_setup.py

# Test DSPy import
python -c "import dspy; print('DSPy imported successfully')"

# Test bootstrap script
python python/scripts/bootstrap.py --verify
```

## Notes

- Virtual environment isolation is critical for reproducibility
- Document any system-specific setup requirements
- Keep requirements.txt minimal but complete
- Ensure all team members can replicate the setup
- Consider Docker as future enhancement for consistency