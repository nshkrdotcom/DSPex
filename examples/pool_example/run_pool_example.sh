#!/bin/bash

# DSPex Pool Example Runner
# This script runs the pool example with proper environment setup

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 DSPex Pool Example Runner${NC}"
echo "=============================="

# Check if running from the correct directory
if [ ! -f "mix.exs" ]; then
    echo -e "${RED}Error: Please run this script from the pool_example directory${NC}"
    exit 1
fi

# Check for Python
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is required but not found${NC}"
    exit 1
fi

# Check for Elixir
if ! command -v elixir &> /dev/null; then
    echo -e "${RED}Error: Elixir is required but not found${NC}"
    exit 1
fi

# Install dependencies if needed
if [ ! -d "deps" ] || [ ! -d "_build" ]; then
    echo -e "${YELLOW}Installing dependencies...${NC}"
    mix deps.get
    mix compile
fi

# Check for GEMINI_API_KEY
if [ -z "$GEMINI_API_KEY" ]; then
    echo -e "${YELLOW}Warning: GEMINI_API_KEY not set. Examples will use mock responses.${NC}"
    echo "To use real AI, export GEMINI_API_KEY='your-key-here'"
    echo
fi

# Set test mode for full integration
export TEST_MODE=full_integration

# Optimize environment for better resource usage
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export OMP_NUM_THREADS=1

# Parse command line arguments
COMMAND=${1:-all}

case $COMMAND in
    session_affinity|anonymous|stress|error_recovery|all|demo)
        echo -e "${GREEN}Running: $COMMAND${NC}"
        mix run -e "PoolExample.CLI.main([\"$COMMAND\"])"
        ;;
    help|--help|-h)
        echo "Usage: ./run_pool_example.sh [command]"
        echo ""
        echo "Commands:"
        echo "  session_affinity  - Test session affinity in the pool"
        echo "  anonymous        - Test anonymous pool operations"
        echo "  stress           - Run concurrent stress test"
        echo "  error_recovery   - Test error handling and recovery"
        echo "  all              - Run all tests (default)"
        echo "  demo             - Run clean demo (minimal output for presentations)"
        echo "  help             - Show this help message"
        ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        echo "Use './run_pool_example.sh help' for usage information"
        exit 1
        ;;
esac