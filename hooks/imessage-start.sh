#!/bin/bash
# UserPromptSubmit hook: record turn start time so the Stop hook can compute elapsed.

input=$(cat)
session_id=$(printf '%s' "$input" | /usr/bin/jq -r '.session_id // ""' 2>/dev/null)
[ -z "$session_id" ] && exit 0

state_dir="$HOME/.claude/hooks/state"
mkdir -p "$state_dir" 2>/dev/null
date +%s > "$state_dir/start-${session_id}" 2>/dev/null
exit 0
