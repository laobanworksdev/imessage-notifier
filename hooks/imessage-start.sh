#!/bin/bash
# UserPromptSubmit hook: record turn start time so the Stop hook can compute elapsed.

# Resolve jq: macOS ships it via Homebrew (not /usr/bin, which is SIP-protected),
# and the hook's PATH may be minimal, so probe known locations explicitly.
JQ="$(command -v jq 2>/dev/null || true)"
for c in /opt/homebrew/bin/jq /usr/local/bin/jq /usr/bin/jq; do [ -n "$JQ" ] && break; [ -x "$c" ] && JQ="$c"; done
[ -z "$JQ" ] && exit 0

input=$(cat)
session_id=$(printf '%s' "$input" | "$JQ" -r '.session_id // ""' 2>/dev/null)
[ -z "$session_id" ] && exit 0

state_dir="$HOME/.claude/hooks/state"
mkdir -p "$state_dir" 2>/dev/null
date +%s > "$state_dir/start-${session_id}" 2>/dev/null
exit 0
