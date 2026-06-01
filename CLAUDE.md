# imessage-notifier — project rules

This project packages an existing, working iMessage notifier so it can be reinstalled on a new Mac. The active deployment lives under `~/.claude/hooks/`. **This repo is the source of truth; that directory is the runtime.**

## Hard constraints

1. **macOS-only.** The notifier uses `osascript` and `Messages.app`. Do not add Linux/WSL paths. Do not port.
2. **Bash 3.2 compatible.** macOS ships `/bin/bash` 3.2. No `mapfile`, no `${var^^}`, no associative arrays, no `[[ -v ]]`. Use POSIX-leaning idioms.
3. **macOS-native tools only.** `osascript`, `/usr/bin/jq`, `/usr/bin/*`, builtins. No GNU coreutils flags. No Python. No Node.
4. **No PII committed.** The user's real Apple ID **never** lands in this repo. The example config uses `your-apple-id@example.com`. The real config (`~/.claude/hooks/imessage-notify.conf`) is created by `install.sh` from the example and is `.gitignore`d. If you see a real email address in a diff, stop and remove it. The shipped `hooks/imessage-notify.sh` therefore defaults `APPLE_ID=""` and exits silently if the config didn't override it — the live runtime copy installed by some users may differ if it pre-dates this repo.
5. **Idempotent installer.** `install.sh` and `uninstall.sh` must be safe to run repeatedly. No clobbering existing user config. Settings patches dedupe by exact command match. The whole install must be reversible by the uninstaller.
6. **Don't modify the live `~/.claude/hooks/*` files directly from this project.** Edit the copies in `hooks/` here, then re-run `install.sh` to deploy.
7. **Don't modify `~/.claude/settings.json` outside the installer.** The installer is the only sanctioned way; manual edits drift the source of truth.
8. **No new features without an explicit user request.** This is a packaging project, not a feature project. No per-project thresholds, no multi-recipient, no Slack fallback, no Telegram fallback, no template engine.

## When editing here

- Edit the canonical copy under `hooks/` or `config/`. Re-run `install.sh` to push to `~/.claude/hooks/`.
- Hook scripts must stay **fail-quiet** — never block a Claude Code turn. Errors go to `/dev/null`; exit code is always `0`.
- Any change to the `jq` patch logic in `install.sh` or `uninstall.sh` must round-trip cleanly: a fresh install + uninstall must leave `settings.json` byte-identical to its pre-install state (excluding key ordering).
- Shell scripts use `set -euo pipefail` for installers, but **not** for the hook scripts themselves (hooks must keep going on errors).

## Files that matter

- `hooks/imessage-start.sh` — UserPromptSubmit hook (records start time).
- `hooks/imessage-notify.sh` — Stop hook (sends iMessage if elapsed ≥ threshold).
- `config/imessage-notify.conf.example` — config template; placeholder only.
- `install.sh` / `uninstall.sh` — only sanctioned writers to `~/.claude/`.
- `.claude/guidelines/create.md` — create rubric.
- `.claude/guidelines/review.md` — review rubric.

## Out of scope

- No tests harness, no CI, no LICENSE, no CHANGELOG.
- No `git init` from inside this project — leave that to the user.
- Don't add a packaging system (`brew`, `npm`, etc.). The shell script *is* the install.
