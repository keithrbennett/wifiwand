#!/bin/bash

# Convenience script for running wifi-wand tests with different levels of system impact
# Usage: ./scripts/test.sh [level]
#   level: read-only | system-modifying | all

set -e

LEVEL=${1:-read-only}

case $LEVEL in
  "read-only")
    echo "Running read-only tests only (safe to run anytime)..."
    bundle exec rspec
    ;;
  "system-modifying")
    echo "Running read-only and system-modifying tests (will change wifi state)..."
    bundle exec rspec --tag modifies_system
    ;;
  "all")
    echo "Running ALL tests including network connections (high impact)..."
    bundle exec rspec --tag network_connection
    ;;
  *)
    echo "Usage: $0 [read-only|system-modifying|all]"
    echo "  read-only: Only read-only tests (default)"
    echo "  system-modifying: Read-only + system-modifying tests"
    echo "  all: All tests including network connections"
    exit 1
    ;;
esac