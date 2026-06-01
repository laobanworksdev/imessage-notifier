#!/bin/bash
# Stop hook: send iMessage notification when a Claude Code turn finishes.
# Reads stop-hook JSON on stdin; pings APPLE_ID via Messages.app if elapsed >= MIN_SECONDS.
# Configurable via ~/.claude/hooks/imessage-notify.conf — edit that file to tune.

# Defaults (overridden by config file if present)
APPLE_ID=""
MIN_SECONDS=300

CONFIG_FILE="$HOME/.claude/hooks/imessage-notify.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

input=$(cat)
session_id=$(printf '%s' "$input" | /usr/bin/jq -r '.session_id // ""' 2>/dev/null)
cwd=$(printf '%s' "$input" | /usr/bin/jq -r '.cwd // ""' 2>/dev/null)
[ -z "$cwd" ] && cwd=$(pwd)
project=$(basename "$cwd")

state_dir="$HOME/.claude/hooks/state"
mkdir -p "$state_dir" 2>/dev/null
start_file="$state_dir/start-${session_id}"

now=$(date +%s)
if [ -f "$start_file" ]; then
  start=$(cat "$start_file" 2>/dev/null)
  rm -f "$start_file" 2>/dev/null
else
  start=$now
fi

elapsed=$(( now - start ))
if [ "$elapsed" -lt "$MIN_SECONDS" ]; then
  exit 0
fi

# No destination configured — stay quiet rather than failing the turn.
[ -z "$APPLE_ID" ] && exit 0

mins=$(( elapsed / 60 ))
secs=$(( elapsed % 60 ))
duration="${mins}m${secs}s"

msg="[Claude] ${project}: turn done (${duration})"

/usr/bin/osascript <<EOF 2>/dev/null
tell application "Messages"
    set targetService to 1st service whose service type = iMessage
    set targetBuddy to buddy "${APPLE_ID}" of targetService
    send "${msg}" to targetBuddy
end tell
EOF

exit 0
