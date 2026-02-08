#!/bin/bash

# Temporary debug version
echo "DEBUG: Script started"

command_exists() {
    echo "DEBUG: Checking for $1..."
    if command -v "$1" >/dev/null 2>&1; then
        echo "DEBUG: Found $1"
        return 0
    else
        echo "DEBUG: NOT found $1"
        return 1
    fi
}

echo "DEBUG: Checking cfn-lint..."
command_exists cfn-lint

echo "DEBUG: Checking jq..."
command_exists jq

echo "DEBUG: Checking shellcheck..."
command_exists shellcheck

echo "DEBUG: Checking aws..."
command_exists aws

echo "DEBUG: All checks complete"