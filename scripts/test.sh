#!/bin/bash

MAX_WAIT=10
WAITED=0
READY=false
while [[ $WAITED -lt $MAX_WAIT ]]; do
  WAITED=$(($WAITED + 2))
  sleep 1
done

echo "Waited for $WAITED of max $MAX_WAIT"

