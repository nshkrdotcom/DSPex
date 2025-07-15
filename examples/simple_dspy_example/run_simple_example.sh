#!/bin/bash

# Simple DSPy Example Runner
# Usage: ./run_simple_example.sh [command]
# Commands: run, models, errors, help

echo "=== Simple DSPy Example ==="

# Check if GEMINI_API_KEY is set
if [ -z "$GEMINI_API_KEY" ]; then
    echo "❌ Error: GEMINI_API_KEY environment variable is not set"
    echo "Please set it with: export GEMINI_API_KEY='your-api-key-here'"
    exit 1
fi

# Default command is 'run'
COMMAND=${1:-run}

echo "Running command: $COMMAND"
echo "----------------------------------------"

# Run the Mix task
mix run_example $COMMAND