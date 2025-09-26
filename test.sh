#!/bin/bash
# Test runner script for TradeMachineEx
# Usage: ./test.sh [test_file_or_pattern]

set -e

# Source test environment
source .env.test

# Run tests with optional file argument
if [ $# -eq 0 ]; then
    echo "Running all tests..."
    mix test
else
    echo "Running tests: $1"
    mix test "$1"
fi