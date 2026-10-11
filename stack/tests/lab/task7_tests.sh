#!/usr/bin/env bash
set -e
D="$(dirname "$0")"
"$D/watchdog_test.sh"
"$D/cli_test.sh"
