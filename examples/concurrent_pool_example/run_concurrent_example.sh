#!/bin/bash

# Concurrent Pool Example Runner
# Usage: ./run_concurrent_example.sh [command]
# Commands: concurrent, affinity, benchmark, errors, help

echo "=== Concurrent Pool Example ==="

# Check if GEMINI_API_KEY is set
if [ -z "$GEMINI_API_KEY" ]; then
    echo "❌ Error: GEMINI_API_KEY environment variable is not set"
    echo "Please set it with: export GEMINI_API_KEY='your-api-key-here'"
    exit 1
fi

# Default command is 'concurrent'
COMMAND=${1:-concurrent}

echo "Running command: $COMMAND"
echo "----------------------------------------"

# Run the Mix task
mix run_concurrent $COMMAND