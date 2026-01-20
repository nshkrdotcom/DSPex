#!/usr/bin/env bash
#
# Run all DSPex examples
#
# Usage: ./examples/run_all.sh
#

set -o pipefail

# Keep OTLP exporters disabled unless explicitly enabled by the caller.
export SNAKEPIT_ENABLE_OTLP="${SNAKEPIT_ENABLE_OTLP:-false}"
export SNAKEPIT_OTEL_CONSOLE="${SNAKEPIT_OTEL_CONSOLE:-false}"
export OTEL_TRACES_EXPORTER="${OTEL_TRACES_EXPORTER:-none}"
export OTEL_METRICS_EXPORTER="${OTEL_METRICS_EXPORTER:-none}"
export OTEL_LOGS_EXPORTER="${OTEL_LOGS_EXPORTER:-none}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

# Timeout wrapper (seconds). Set DSPEX_RUN_TIMEOUT_SECONDS=0 to disable.
RUN_TIMEOUT_SECONDS="${DSPEX_RUN_TIMEOUT_SECONDS:-120}"
TIMEOUT_CMD=()

if [[ "$RUN_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] && [[ "$RUN_TIMEOUT_SECONDS" -gt 0 ]]; then
    if command -v timeout >/dev/null 2>&1; then
        TIMEOUT_CMD=(timeout --foreground --preserve-status "$RUN_TIMEOUT_SECONDS")
    elif command -v gtimeout >/dev/null 2>&1; then
        TIMEOUT_CMD=(gtimeout --foreground --preserve-status "$RUN_TIMEOUT_SECONDS")
    fi
fi

run_cmd() {
    if ((${#TIMEOUT_CMD[@]})); then
        "${TIMEOUT_CMD[@]}" "$@"
    else
        "$@"
    fi
}

# Track results
declare -a NAMES
declare -a RESULTS
declare -a DURATIONS

START_TIME=$(date +%s)

print_header() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    DSPex Examples Runner                   ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    # Use elixir -v for single-line output (avoids EPIPE crash with head)
    echo -e "${BLUE}Elixir:${NC} $(elixir -v 2>/dev/null)"
    echo -e "${BLUE}Python:${NC} $(python3 --version 2>&1)"
    echo ""
}

run_example() {
    local file=$1
    local name=$(basename "$file" .exs)
    local start=$(date +%s)

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Running: ${NC}${name}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if run_cmd mix run --no-start "$file" 2>&1; then
        local end=$(date +%s)
        local duration=$((end - start))
        RESULTS+=("0")
        DURATIONS+=("$duration")
        echo ""
        echo -e "${GREEN}✓ ${name} completed in ${duration}s${NC}"
    else
        RESULTS+=("1")
        DURATIONS+=("0")
        echo ""
        echo -e "${RED}✗ ${name} failed${NC}"
    fi
    echo ""

    NAMES+=("$name")
}

print_summary() {
    local end_time=$(date +%s)
    local total=$((end_time - START_TIME))
    local passed=0
    local failed=0

    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                         SUMMARY                            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    for i in "${!NAMES[@]}"; do
        if [ "${RESULTS[$i]}" == "0" ]; then
            echo -e "  ${GREEN}✓${NC} ${NAMES[$i]} (${DURATIONS[$i]}s)"
            ((passed++))
        else
            echo -e "  ${RED}✗${NC} ${NAMES[$i]}"
            ((failed++))
        fi
    done

    echo ""
    echo -e "${BLUE}Total time:${NC} ${total}s"

    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}All ${passed} examples passed!${NC}"
    else
        echo -e "${YELLOW}Passed: ${passed}, Failed: ${failed}${NC}"
    fi
    echo ""
}

main() {
    print_header

    # Check for API key
    if [[ -z "$GEMINI_API_KEY" ]]; then
        echo -e "${RED}Error: GEMINI_API_KEY not set${NC}"
        exit 1
    fi

    # Compile first
    echo -e "${BLUE}Compiling...${NC}"
    mix compile --no-warnings || exit 1
    echo ""

    # Run examples in order
    EXAMPLES=(
        "examples/basic.exs"
        "examples/chain_of_thought.exs"
        "examples/classification.exs"
        "examples/summarization.exs"
        "examples/multi_field.exs"
        "examples/translation.exs"
        "examples/entity_extraction.exs"
        "examples/math_reasoning.exs"
        "examples/qa_with_context.exs"
        "examples/multi_hop_qa.exs"
        "examples/rag.exs"
        "examples/code_gen.exs"
        "examples/custom_signature.exs"
        "examples/custom_module.exs"
        "examples/optimization.exs"
        "examples/flagship_multi_pool_gepa.exs"
        "examples/flagship_multi_pool_rlm.exs"
        "examples/rlm/rlm_data_extraction_experiment_fixed.exs"
        "examples/direct_lm_call.exs"
    )

    for example in "${EXAMPLES[@]}"; do
        if [ -f "$example" ]; then
            run_example "$example"
        else
            echo -e "${RED}Not found: $example${NC}"
        fi
    done

    print_summary
}

main "$@"
