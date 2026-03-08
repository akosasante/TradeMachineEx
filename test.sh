#!/bin/bash
# Test runner script for TradeMachineEx
# Usage: ./test.sh [--cover] [test_file_or_pattern]
#   --cover  Run with HTML coverage report (opens cover/excoveralls.html)

set -e

# Source test environment
source .env.test

COVER=false
ARGS=()

for arg in "$@"; do
    if [ "$arg" = "--cover" ]; then
        COVER=true
    else
        ARGS+=("$arg")
    fi
done

if [ "$COVER" = true ]; then
    echo "Running tests with coverage..."
    mix coveralls.html "${ARGS[@]}"
else
    if [ ${#ARGS[@]} -eq 0 ]; then
        echo "Running all tests..."
        mix test
    else
        echo "Running tests: ${ARGS[*]}"
        mix test "${ARGS[@]}"
    fi
fi
