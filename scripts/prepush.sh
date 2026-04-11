#!/usr/bin/env bash
# Run the same checks as CI (and local quality gates) before pushing to main.
# Usage: from repo root —  bash scripts/prepush.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MIX_ENV=dev mix format
MIX_ENV=dev mix credo
MIX_ENV=dev mix dialyzer
MIX_ENV=dev mix compile --warnings-as-errors
MIX_ENV=test mix compile --warnings-as-errors

set -a
# shellcheck disable=SC1091
source .env.test
set +a

MIX_ENV=test mix test --cover
