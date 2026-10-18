#!/bin/bash
# Stop hook: send iMessage notification when a Claude Code turn finishes.
# Reads stop-hook JSON on stdin; pings APPLE_ID via Messages.app if elapsed >= MIN_SECONDS.
# Configurable via ~/.claude/hooks/imessage-notify.conf — edit that file to tune.
#
# Message format (up to 4 lines when data is available):
#   [Claude] <project> (<duration>)
#   📋 <session name>        ← the session's auto-generated ai-title
#   📝 <turn summary>        ← headline of this turn's final reply, ≤140 chars (TURN_SUMMARY=0 hides it)
#   ✅ <what's done>         ← the 🎯 session-focus footer from the last reply (~10 words)
# Each enrichment line is omitted when its data is missing; if all three are,
# the message falls back to the original "turn done" wording.

# Defaults (overridden by config file if present)
APPLE_ID=""
MIN_SECONDS=300
TURN_SUMMARY=1

CONFIG_FILE="$HOME/.claude/hooks/imessage-notify.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# Resolve jq: macOS ships it via Homebrew (not /usr/bin, which is SIP-protected),
# and the hook's PATH may be minimal, so probe known locations explicitly.
JQ="$(command -v jq 2>/dev/null || true)"
for c in /opt/homebrew/bin/jq /usr/local/bin/jq /usr/bin/jq; do [ -n "$JQ" ] && break; [ -x "$c" ] && JQ="$c"; done

input=$(cat)
session_id=""; cwd=""; transcript=""
if [ -n "$JQ" ]; then
  session_id=$(printf '%s' "$input" | "$JQ" -r '.session_id // ""' 2>/dev/null)
  cwd=$(printf '%s' "$input" | "$JQ" -r '.cwd // ""' 2>/dev/null)
  transcript=$(printf '%s' "$input" | "$JQ" -r '.transcript_path // ""' 2>/dev/null)
fi
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

# --- enrichment: session name + this turn's summary + a ~10-word "what's done" ---
session_name=""
turn_summary=""
whats_done=""
if [ -n "$JQ" ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
  # Session name = the most recent auto-generated session title.
  session_name=$("$JQ" -r 'select(.type=="ai-title") | .aiTitle // empty' "$transcript" 2>/dev/null | tail -1)
  # What's done = the latest 🎯 session-focus footer from an assistant reply,
  # with the emoji dropped and capped to ~14 words (the footer is ~6-12 by rule).
  whats_done=$("$JQ" -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' "$transcript" 2>/dev/null \
    | grep '^[[:space:]]*🎯' | tail -1 \
    | awk '{ out=""; cnt=0; for (i=2; i<=NF; i++) { if (cnt>=12) { out=out" …"; break } out=out (cnt>0?" ":"") $i; cnt++ } print out }')
fi

# Turn summary = one plain-text headline of this turn's final reply: its last
# result: / needs input: / failed: status line (the "result:" label dropped),
# else its first meaningful line (skipping code blocks, table rows, rules and
# 🎯/📝 footers); markdown stripped, capped at 140 characters. The capping is
# done in jq because jq counts characters, not bytes, so emoji/CJK never split.
summary_jq='
def clean:
  gsub("!?\\[(?<t>[^\\]]*)\\]\\([^)]*\\)"; .t)
  | [split("`") | to_entries[] | if .key % 2 == 0 then .value | gsub("\\*\\*|__"; "") else .value end] | join("")
  | sub("^\\s*((#{1,6}|[-*+]|[0-9]+[.)])\\s+|>\\s*)+"; "")
  | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
def summary:
  [foreach (gsub("\r"; "") | split("\n"))[] as $l ({open: false};
      ($l | test("^\\s*(```|~~~)")) as $f
      | {open: (if $f then (.open | not) else .open end), keep: (($f or .open) | not), l: $l};
      select(.keep) | .l)]
  | ([.[] | select(test("^\\s*(result|needs input|failed)\\s*:\\s*\\S"; "i"))] | last) as $status
  | if $status then $status | sub("^\\s*result\\s*:\\s*"; ""; "i") | clean
    else first(.[] | select(test("^\\s*(\\||🎯|📝)") | not)
                   | select(test("^\\s*([-*_=])(\\s*\\1){2,}\\s*$") | not)
                   | clean | select(length > 0)) // ""
    end
  | if length <= 140 then .
    else .[0:140] as $w | ($w | sub("\\s+\\S*$"; "")) as $b
      | (if ($b | length) >= 70 and ($b | length) < 140 then $b else $w[0:139] end)
      | sub("[\\s,;:.–—-]+$"; "") + "…"
    end;'
if [ "$TURN_SUMMARY" = "1" ] && [ -n "$JQ" ]; then
  # Claude Code hands the final reply over as .last_assistant_message. jq -e
  # exits non-zero only when that field is absent (older Claude Code); then
  # fall back to the transcript: its last assistant text, if any was written
  # after the last real user prompt.
  if ! turn_summary=$(printf '%s' "$input" | "$JQ" -er "$summary_jq"'
       .last_assistant_message | select(type == "string" and length > 0) | summary' 2>/dev/null) \
     && [ -n "$transcript" ] && [ -f "$transcript" ]; then
    turn_summary=$(tail -n 400 "$transcript" | "$JQ" -Rnr "$summary_jq"'
      [inputs | fromjson? | objects | select(.isSidechain != true)] as $e
      | ([$e | to_entries[] | select(.value.type == "user" and .value.isMeta != true
            and (.value.message.content | type == "string" or any(.[]?; .type == "text")))
          | .key] | last // -1) as $p
      | [$e[($p + 1):][] | select(.type == "assistant") | .message.content[]?
          | select(.type == "text") | .text | select(test("\\S"))]
      | last // "" | summary' 2>/dev/null)
  fi
fi

# --- build the message (single string, newline-separated) ---
if [ -n "$session_name" ] || [ -n "$turn_summary" ] || [ -n "$whats_done" ]; then
  msg="[Claude] ${project} (${duration})"
  [ -n "$session_name" ] && msg="${msg}
📋 ${session_name}"
  [ -n "$turn_summary" ] && msg="${msg}
📝 ${turn_summary}"
  [ -n "$whats_done" ] && msg="${msg}
✅ ${whats_done}"
else
  msg="[Claude] ${project}: turn done (${duration})"
fi

# Send via Messages.app. Pass the Apple ID and message as argv (NOT interpolated
# into the AppleScript source) so quotes/backslashes/newlines in a title can't
# break or inject into the script.
/usr/bin/osascript - "$APPLE_ID" "$msg" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set theId to item 1 of argv
    set theMsg to item 2 of argv
    tell application "Messages"
        set targetService to 1st service whose service type = iMessage
        set targetBuddy to buddy theId of targetService
        send theMsg to targetBuddy
    end tell
end run
APPLESCRIPT

exit 0
