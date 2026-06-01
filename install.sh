#!/bin/bash
# install.sh — package iMessage notifier into ~/.claude/.
# Idempotent: safe to re-run. Never clobbers an existing user config.
#
# What this does:
#   1. Validates jq is available.
#   2. Copies hooks/*.sh to ~/.claude/hooks/ (chmod +x).
#   3. Copies config/imessage-notify.conf.example to ~/.claude/hooks/imessage-notify.conf
#      ONLY if that file does not already exist.
#   4. Patches ~/.claude/settings.json to register:
#        UserPromptSubmit -> ~/.claude/hooks/imessage-start.sh
#        Stop            -> ~/.claude/hooks/imessage-notify.sh
#      Existing entries with an exact-match command are left alone (dedup).
#      All unrelated keys / hooks / events are preserved.
#   5. Validates the resulting JSON parses.
#
# Usage:
#   ./install.sh           # install / re-install
#   ./install.sh --dry-run # show what would change without writing
#   ./install.sh -h        # help

set -euo pipefail

# ---------- args ----------
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,21p' "$0"
      exit 0
      ;;
    *)
      echo "install.sh: unknown argument: $arg" >&2
      echo "try: $0 --help" >&2
      exit 2
      ;;
  esac
done

# ---------- paths ----------
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SRC_HOOKS_DIR="$SCRIPT_DIR/hooks"
SRC_CONFIG_EXAMPLE="$SCRIPT_DIR/config/imessage-notify.conf.example"

DST_HOOKS_DIR="$HOME/.claude/hooks"
DST_CONFIG="$DST_HOOKS_DIR/imessage-notify.conf"
DST_SETTINGS="$HOME/.claude/settings.json"

START_HOOK_NAME="imessage-start.sh"
STOP_HOOK_NAME="imessage-notify.sh"
START_HOOK_PATH="$DST_HOOKS_DIR/$START_HOOK_NAME"
STOP_HOOK_PATH="$DST_HOOKS_DIR/$STOP_HOOK_NAME"

CHANGES=()

note() { CHANGES+=("$1"); echo "  - $1"; }

# ---------- preflight ----------
echo "==> preflight"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "install.sh: this notifier is macOS-only (Messages.app + osascript)." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "install.sh: 'jq' not found in PATH. Install it first:" >&2
  echo "    brew install jq" >&2
  exit 1
fi

if [ ! -f "$SRC_HOOKS_DIR/$START_HOOK_NAME" ] || [ ! -f "$SRC_HOOKS_DIR/$STOP_HOOK_NAME" ]; then
  echo "install.sh: source hooks missing under $SRC_HOOKS_DIR" >&2
  exit 1
fi

if [ ! -f "$SRC_CONFIG_EXAMPLE" ]; then
  echo "install.sh: example config missing at $SRC_CONFIG_EXAMPLE" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "  (dry-run mode: no files will be written)"
fi

# ---------- 1. hooks dir + scripts ----------
echo "==> hooks"

if [ ! -d "$DST_HOOKS_DIR" ]; then
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$DST_HOOKS_DIR"
  fi
  note "create $DST_HOOKS_DIR"
fi

for h in "$START_HOOK_NAME" "$STOP_HOOK_NAME"; do
  src="$SRC_HOOKS_DIR/$h"
  dst="$DST_HOOKS_DIR/$h"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    echo "  - $dst already up to date"
  else
    if [ "$DRY_RUN" -eq 0 ]; then
      cp "$src" "$dst"
      chmod +x "$dst"
    fi
    note "install $dst"
  fi
done

# ---------- 2. config (don't clobber) ----------
echo "==> config"

if [ -f "$DST_CONFIG" ]; then
  echo "  - $DST_CONFIG exists; leaving it alone"
else
  if [ "$DRY_RUN" -eq 0 ]; then
    cp "$SRC_CONFIG_EXAMPLE" "$DST_CONFIG"
  fi
  note "create $DST_CONFIG (edit APPLE_ID before next turn)"
fi

# ---------- 3. patch settings.json ----------
echo "==> settings.json"

if [ ! -f "$DST_SETTINGS" ]; then
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$(dirname "$DST_SETTINGS")"
    printf '{}\n' > "$DST_SETTINGS"
  fi
  note "create $DST_SETTINGS (was missing)"
fi

# Validate existing JSON before touching it.
if ! jq -e . "$DST_SETTINGS" >/dev/null 2>&1; then
  echo "install.sh: $DST_SETTINGS is not valid JSON; refusing to patch." >&2
  exit 1
fi

# Build the new JSON in memory. The jq program walks .hooks.<event>[].hooks[]
# looking for an exact .command match; if absent, it appends a new wrapper
# entry { "hooks": [ { "type": "command", "command": "..." } ] }.
NEW_JSON=$(jq \
  --arg start_event "UserPromptSubmit" \
  --arg start_cmd "$START_HOOK_PATH" \
  --arg stop_event "Stop" \
  --arg stop_cmd "$STOP_HOOK_PATH" '
  def has_cmd(event; cmd):
    (.hooks[event] // []) as $arr
    | any($arr[]?; (.hooks // []) | any(.command == cmd));

  def add_cmd(event; cmd):
    if has_cmd(event; cmd) then .
    else
      .hooks = (.hooks // {})
      | .hooks[event] = ((.hooks[event] // []) + [
          { "hooks": [ { "type": "command", "command": cmd } ] }
        ])
    end;

  add_cmd($start_event; $start_cmd)
  | add_cmd($stop_event;  $stop_cmd)
' "$DST_SETTINGS")

# Sanity-check the result parses.
if ! printf '%s' "$NEW_JSON" | jq -e . >/dev/null 2>&1; then
  echo "install.sh: produced invalid JSON; aborting without writing." >&2
  exit 1
fi

# Compare; only write if different.
CURRENT_JSON=$(jq -S . "$DST_SETTINGS")
NEW_JSON_SORTED=$(printf '%s' "$NEW_JSON" | jq -S .)

if [ "$CURRENT_JSON" = "$NEW_JSON_SORTED" ]; then
  echo "  - $DST_SETTINGS already registers both hooks"
else
  if [ "$DRY_RUN" -eq 0 ]; then
    tmp="${DST_SETTINGS}.tmp.$$"
    printf '%s\n' "$NEW_JSON" > "$tmp"
    mv "$tmp" "$DST_SETTINGS"
  fi
  note "register hooks in $DST_SETTINGS (UserPromptSubmit + Stop)"
fi

# ---------- summary ----------
echo "==> done"
if [ "${#CHANGES[@]}" -eq 0 ]; then
  echo "  no changes (already installed)"
else
  echo "  ${#CHANGES[@]} change(s):"
  for c in "${CHANGES[@]}"; do echo "    * $c"; done
fi

if [ "$DRY_RUN" -eq 0 ] && [ -f "$DST_CONFIG" ] && grep -q 'your-apple-id@example.com' "$DST_CONFIG" 2>/dev/null; then
  echo
  echo "NEXT: edit $DST_CONFIG and set APPLE_ID to your real iMessage address."
fi

if [ "$DRY_RUN" -eq 0 ]; then
  echo
  echo "If hooks don't fire on the next turn, run /hooks in Claude Code to reload."
fi
