#!/usr/bin/env bash
# Called when a worker's claude process ends: records the exit code next to its log.
set -euo pipefail
SID="${1:?session id}"; CODE="${2:-0}"; STATE="${3:?state dir}"
printf '{"session":"%s","exit_code":%s,"exited_at":"%s"}\n' \
  "$SID" "$CODE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE/$SID.exit.json"
echo "$SID exited $CODE"
