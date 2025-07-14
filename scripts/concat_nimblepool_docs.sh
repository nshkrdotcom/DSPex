#!/bin/bash

# Script to concatenate all NimblePool-related documentation for analysis

OUTPUT_FILE="nimblepool_complete_docs.md"

echo "# Complete NimblePool Documentation and Analysis" > $OUTPUT_FILE
echo "Generated on: $(date)" >> $OUTPUT_FILE
echo "" >> $OUTPUT_FILE

# Function to add a document section
add_doc() {
    local file=$1
    local title=$2
    
    if [ -f "$file" ]; then
        echo "" >> $OUTPUT_FILE
        echo "---" >> $OUTPUT_FILE
        echo "## $title" >> $OUTPUT_FILE
        echo "File: $file" >> $OUTPUT_FILE
        echo "---" >> $OUTPUT_FILE
        echo "" >> $OUTPUT_FILE
        cat "$file" >> $OUTPUT_FILE
        echo "" >> $OUTPUT_FILE
    else
        echo "Warning: $file not found" >&2
    fi
}

# Add all relevant documents
add_doc "docs/UNDERSTANDING_NIMBLE_POOL.md" "Understanding NimblePool"
add_doc "docs/UNDERSTANDING_NIMBLE_POOL_integrationRecs.md" "Integration Recommendations"
add_doc "docs/NIMBLEPOOL_FIX_PLAN.md" "Fix Plan"
add_doc "docs/NIMBLEPOOL_V2_CHALLENGES.md" "V2 Implementation Challenges"
add_doc "docs/POOL_V2_MIGRATION_GUIDE.md" "Migration Guide"

# Add key source files
echo "" >> $OUTPUT_FILE
echo "---" >> $OUTPUT_FILE
echo "# Key Source Code Files" >> $OUTPUT_FILE
echo "---" >> $OUTPUT_FILE

add_doc "lib/dspex/python_bridge/session_pool.ex" "SessionPool V1 (Current)"
add_doc "lib/dspex/python_bridge/session_pool_v2.ex" "SessionPool V2 (Refactored)"
add_doc "lib/dspex/python_bridge/pool_worker.ex" "PoolWorker V1 (Current)"
add_doc "lib/dspex/python_bridge/pool_worker_v2.ex" "PoolWorker V2 (Refactored)"
add_doc "lib/dspex/adapters/python_pool.ex" "PythonPool Adapter V1"
add_doc "lib/dspex/adapters/python_pool_v2.ex" "PythonPool Adapter V2"
add_doc "priv/python/dspy_bridge.py" "Python Bridge Script"

# Add test files
echo "" >> $OUTPUT_FILE
echo "---" >> $OUTPUT_FILE
echo "# Test Files" >> $OUTPUT_FILE
echo "---" >> $OUTPUT_FILE

add_doc "test/pool_v2_test.exs" "Pool V2 Tests"
add_doc "test/pool_v2_simple_test.exs" "Pool V2 Simple Tests"

echo "" >> $OUTPUT_FILE
echo "---" >> $OUTPUT_FILE
echo "# Summary" >> $OUTPUT_FILE
echo "---" >> $OUTPUT_FILE
echo "" >> $OUTPUT_FILE
echo "This document contains all relevant code and documentation for the NimblePool integration in DSPex." >> $OUTPUT_FILE
echo "The main issue is that the V2 refactoring encounters worker initialization timeouts when trying to" >> $OUTPUT_FILE
echo "implement the correct NimblePool pattern where blocking operations happen in client processes." >> $OUTPUT_FILE

echo "Documentation concatenated to $OUTPUT_FILE"
echo "File size: $(wc -c < $OUTPUT_FILE) bytes"
echo "Line count: $(wc -l < $OUTPUT_FILE) lines"

# Make it executable
chmod +x scripts/concat_nimblepool_docs.sh