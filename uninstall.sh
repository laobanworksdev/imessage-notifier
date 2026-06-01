#!/bin/bash
# uninstall.sh — remove this notifier from ~/.claude/.
# Idempotent: re-running is safe.
#
# What this does:
#   1. Removes the two hook entries from ~/.claude/settings.json
#      (only entries whose .command matches our installed paths;
#       all other keys, events, and hooks are preserved).
#   2. Deletes ~/.claude/hooks/imessage-start.sh
#       and ~/.claude/hooks/imessage-notify.sh.
#   3. Asks before deleting ~/.claude/hooks/imessage-notify.conf
#      (it contains your Apple ID).
#
# Usage:
#   ./uninstall.sh                 # interactive
#   ./uninstall.sh --keep-config   # never touch the .conf file
#   ./uninstall.sh --purge         # also remove the .conf without asking
#   ./uninstall.sh --dry-run       # show what would change without writing

set -euo pipefail

# ---------- args ----------
KEEP_CONFIG=0
PURGE=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --keep-config) KEEP_CONFIG=1 ;;
    --purge)       PURGE=1 ;;
    --dry-run|-n)  DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "uninstall.sh: unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

# ---------- paths ----------
DST_HOOKS_DIR="$HOME/.claude/hooks"
DST_CONFIG="$DST_HOOKS_DIR/imessage-notify.conf"
DST_SETTINGS="$HOME/.claude/settings.json"
START_HOOK_PATH="$DST_HOOKS_DIR/imessage-start.sh"
STOP_HOOK_PATH="$DST_HOOKS_DIR/imessage-notify.sh"

CHANGES=()
note() { CHANGES+=("$1"); echo "  - $1"; }

# ---------- preflight ----------
if ! command -v jq >/dev/null 2>&1; then
  echo "uninstall.sh: 'jq' not found in PATH. Install it first: brew install jq" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "(dry-run mode: no files will be written)"
fi

# ---------- 1. patch settings.json ----------
echo "==> settings.json"
if [ -f "$DST_SETTINGS" ]; then
  if ! jq -e . "$DST_SETTINGS" >/dev/null 2>&1; then
    echo "uninstall.sh: $DST_SETTINGS is not valid JSON; refusing to patch." >&2
    exit 1
  fi

  NEW_JSON=$(jq \
    --arg start_cmd "$START_HOOK_PATH" \
    --arg stop_cmd "$STOP_HOOK_PATH" '
    def strip_cmd(event; cmd):
      if (.hooks // {}) | has(event) | not then .
      else
        .hooks[event] = (
          (.hooks[event] // [])
          | map(
              .hooks = ((.hooks // []) | map(select(.command != cmd)))
            )
          | map(select((.hooks // []) | length > 0))
        )
        | if (.hooks[event] | length) == 0 then del(.hooks[event]) else . end
      end;

    strip_cmd("UserPromptSubmit"; $start_cmd)
    | strip_cmd("Stop";            $stop_cmd)
    | if (.hooks // {}) == {} then del(.hooks) else . end
  ' "$DST_SETTINGS")

  if ! printf '%s' "$NEW_JSON" | jq -e . >/dev/null 2>&1; then
    echo "uninstall.sh: produced invalid JSON; aborting without writing." >&2
    exit 1
  fi

  CURRENT_JSON=$(jq -S . "$DST_SETTINGS")
  NEW_JSON_SORTED=$(printf '%s' "$NEW_JSON" | jq -S .)

  if [ "$CURRENT_JSON" = "$NEW_JSON_SORTED" ]; then
    echo "  - $DST_SETTINGS has no entries to remove"
  else
    if [ "$DRY_RUN" -eq 0 ]; then
      tmp="${DST_SETTINGS}.tmp.$$"
      printf '%s\n' "$NEW_JSON" > "$tmp"
      mv "$tmp" "$DST_SETTINGS"
    fi
    note "remove hook entries from $DST_SETTINGS"
  fi
else
  echo "  - $DST_SETTINGS not found; skipping"
fi

# ---------- 2. delete hook scripts ----------
echo "==> hook scripts"
for f in "$START_HOOK_PATH" "$STOP_HOOK_PATH"; do
  if [ -f "$f" ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
      rm -f "$f"
    fi
    note "delete $f"
  else
    echo "  - $f not present"
  fi
done

# ---------- 3. config file (sensitive) ----------
echo "==> config"
if [ -f "$DST_CONFIG" ]; then
  if [ "$KEEP_CONFIG" -eq 1 ]; then
    echo "  - keeping $DST_CONFIG (--keep-config)"
  elif [ "$PURGE" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
      rm -f "$DST_CONFIG"
    fi
    note "delete $DST_CONFIG (--purge)"
  else
    printf "  remove %s? [y/N] " "$DST_CONFIG"
    read -r answer || answer=""
    case "$answer" in
      y|Y|yes|YES)
        if [ "$DRY_RUN" -eq 0 ]; then
          rm -f "$DST_CONFIG"
        fi
        note "delete $DST_CONFIG"
        ;;
      *)
        echo "  - keeping $DST_CONFIG"
        ;;
    esac
  fi
else
  echo "  - $DST_CONFIG not present"
fi

# ---------- summary ----------
echo "==> done"
if [ "${#CHANGES[@]}" -eq 0 ]; then
  echo "  nothing to remove (already uninstalled)"
else
  echo "  ${#CHANGES[@]} change(s):"
  for c in "${CHANGES[@]}"; do echo "    * $c"; done
  echo
  echo "If a turn-in-progress was tracked, stale state files may remain in:"
  echo "  $DST_HOOKS_DIR/state/"
  echo "They are harmless and self-clean as new sessions run."
fi
