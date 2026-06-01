# imessage-notifier — design

Internal design notes for engineers. For setup and usage, see [README.md](README.md).

This repo is the **source of truth**. The active deployment lives at `~/.claude/hooks/`. `install.sh` copies files there and wires them into `~/.claude/settings.json`.

## What gets installed where

| File | Path | Purpose |
|---|---|---|
| `imessage-start.sh` | `~/.claude/hooks/imessage-start.sh` | UserPromptSubmit hook — records turn start. |
| `imessage-notify.sh` | `~/.claude/hooks/imessage-notify.sh` | Stop hook — sends iMessage if elapsed ≥ `MIN_SECONDS`. |
| `imessage-notify.conf` | `~/.claude/hooks/imessage-notify.conf` | Per-machine config (Apple ID + threshold). |
| state files | `~/.claude/hooks/state/start-<session_id>` | Per-session turn-start timestamps. Auto-cleaned. |
| settings entries | `~/.claude/settings.json` (`hooks.UserPromptSubmit`, `hooks.Stop`) | How Claude Code finds the hooks. |

## Time sequence

Two hooks + one per-session state file. They communicate **only** through `~/.claude/hooks/state/start-<session_id>`.

```
TIME    USER ACTION          CLAUDE CODE              imessage-start.sh         imessage-notify.sh
─────   ───────────          ───────────              ─────────────────         ──────────────────
t=0     submit prompt ─────► UserPromptSubmit ──────► reads session_id
                             event with stdin JSON    writes date +%s to
                                                      state/start-<sid>
                                                      exit 0

t=N     (Claude turn runs: tool calls, file edits, response generation...)

t=N+E   turn ends ──────────► Stop event with                                    reads APPLE_ID, MIN_SECONDS from .conf
                              stdin JSON ───────────────────────────────────────► reads + deletes state/start-<sid>
                                                                                   computes elapsed = now - start
                                                                                   if elapsed ≥ MIN_SECONDS:
                                                                                     osascript → Messages.app
                                                                                     → iMessage to APPLE_ID
                                                                                     → 📱 phone notification
                                                                                   exit 0
```

## Why two scripts

The Stop event has no built-in "turn start" timestamp. So the UserPromptSubmit hook stamps `date +%s` to a per-session file, and the Stop hook reads + deletes it to compute elapsed. Session ID comes from the JSON event payload on stdin (`session_id` field), parsed via `jq`.

If the start file is missing on Stop (rare: user reloaded hooks mid-turn, or session crossed an install), the script treats elapsed as `0` and stays silent.

If `APPLE_ID` is empty (e.g. the user never edited the freshly-installed `.conf`), the Stop hook also stays silent — better a missing notification than a failing turn.

## Why the threshold

A short, chatty turn would spam iMessage. The `MIN_SECONDS` floor turns this into "alert me about long jobs only".

## Message format

Beyond `[Claude] <project> (<duration>)`, the Stop hook reads `transcript_path` from its stdin JSON and pulls two best-effort enrichment lines from the session transcript:

- **📋 session name** — the most recent `ai-title` entry (Claude Code's auto-generated session title).
- **✅ what's done** — the latest assistant message's `🎯` session-focus footer, emoji stripped and capped to ~12 words.

If `jq` is missing, the transcript is unreadable, or neither line is found, the message falls back to the original single line `[Claude] <project>: turn done (<duration>)`. The Apple ID and the assembled (possibly multi-line) message are passed to `osascript` as `argv` — **not** interpolated into the AppleScript source — so quotes, backslashes, or newlines in a title can't break or inject into the send (see Known limitations #2).

## Failure modes

| What can fail | What happens | What you see |
|---|---|---|
| `jq` missing at hook runtime | `session_id` parses to `""`; start-hook exits 0; stop-hook treats elapsed as `0`. | Notifier silently does nothing. |
| Messages.app not signed in | `osascript` block errors; Stop hook still exits `0` (errors swallowed by `2>/dev/null`). | No notification, Claude Code is unaffected. |
| `APPLE_ID` not a valid iMessage destination | Same as above — `osascript` errors, hook still exits `0`. | No notification. |
| `state/` directory not writable | Start hook silently fails to write; Stop sees no start file → elapsed `0` → no notification. | Notifier silently does nothing. |
| `settings.json` malformed | Installer refuses to patch and exits non-zero. | Clear error from `install.sh`. |
| Multiple installs | `install.sh` dedupes by exact command match. | Re-running is a no-op. |

The hooks are **fail-quiet by design** — they should never block a turn. If something is wrong, you stop getting pings; Claude Code itself is never disrupted.

## Known limitations

These were caught in review and are documented here rather than fixed. None of them affects the happy path, and all are local-machine-only (no remote attack surface). Fix them when convenient.

| # | Where | What | Impact | Fix sketch |
|---|---|---|---|---|
| 1 | `hooks/imessage-notify.sh:11` | `. "$CONFIG_FILE"` runs the conf file in the current shell. A syntax error or a failing command in a user-edited `.conf` could short-circuit the rest of the hook. | Low. The hook has no `set -e`, so most malformed configs only print to stderr (which is suppressed) and the script proceeds with defaults. A *failing* command (rare) would skip the send. | Wrap as `. "$CONFIG_FILE" 2>/dev/null \|\| true` to fully match the fail-quiet contract. |
| 2 | ~~`hooks/imessage-notify.sh`~~ | **FIXED.** The Apple ID and the (possibly multi-line) message are now passed to `osascript` as `argv` via `on run argv`, instead of being interpolated into the AppleScript heredoc. A `"`, `\`, or newline in any field can no longer break or inject into the send. | Resolved. | — |
| 3 | `install.sh:73-95` | The installer copies hook scripts and creates the conf file *before* it validates that `~/.claude/settings.json` is parseable JSON. If the JSON is malformed, install aborts at the patch step but has already done filesystem work. | Minor. Re-running install after the user fixes the JSON cleans up via the dedup logic, so no permanent harm. A user who deletes the malformed file and starts fresh sees half-installed hook scripts. | Reorder: validate `DST_SETTINGS` JSON first, then do filesystem work. |
| 4 | `README.md` failure-modes table | **MOOT** after #2's fix — there is no longer an AppleScript-quoting failure mode to document. | None. | — |

Verdict from the standalone review against `.claude/guidelines/review.md`: **APPROVE WITH NITS** — every hard-fail criterion met (no PII committed, bash 3.2 compatible, idempotent install, settings.json round-trips byte-identical, peer hooks on the same events survive install/uninstall, all hook stdin shapes exit 0).

## Project layout

```
imessage-notifier/
├── README.md
├── DESIGN.md
├── CLAUDE.md
├── install.sh
├── uninstall.sh
├── hooks/
│   ├── imessage-start.sh
│   └── imessage-notify.sh
├── config/
│   └── imessage-notify.conf.example
├── .gitignore
└── .claude/
    └── guidelines/
        ├── create.md
        └── review.md
```
