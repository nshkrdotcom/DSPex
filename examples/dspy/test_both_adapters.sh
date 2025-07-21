#!/bin/bash

echo "=== Testing Simple Q&A Demo (EnhancedPython) ==="
mix run examples/dspy/simple_qa_demo.exs

echo -e "\n\n=== Testing gRPC Q&A Demo ==="
mix run examples/dspy/grpc_qa_demo.exs