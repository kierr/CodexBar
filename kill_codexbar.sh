#!/usr/bin/env bash
# Kills all CodexBar processes.
set -euo pipefail
pkill -f "CodexBar" 2>/dev/null || true
sleep 1
# Verify
if pgrep -f "CodexBar" >/dev/null 2>&1; then
    echo "WARN: CodexBar still running, forcing..."
    pkill -9 -f "CodexBar" 2>/dev/null || true
    sleep 1
fi
if pgrep -f "CodexBar" >/dev/null 2>&1; then
    echo "ERROR: CodexBar could not be killed"
    exit 1
else
    echo "CodexBar killed successfully"
fi
