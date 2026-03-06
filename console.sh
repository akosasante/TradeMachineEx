#!/bin/bash
# Connect to the running TradeMachineEx container's IEx console

CONTAINER="trademachineex-app-1"
SNAME="${1:-console}"

exec docker exec -it "$CONTAINER" sh -c "iex --sname ${SNAME} --remsh trade_machine@\$(hostname)"
