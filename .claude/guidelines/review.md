# Review rubric — imessage-notifier

What a reviewer checks for in this project.

## Hard fails (must fix before merge)

1. **Real PII committed.** Any real Apple ID, phone number, email, or auth token in a tracked file. The example config must use `your-apple-id@example.com`.
2. **Bash 3.2 incompatibility.** `mapfile`, `readarray`, `${var^^}`, `${var,,}`, associative arrays (`declare -A`), `[[ -v ]]`, `&>` redirection where it matters. macOS's `/bin/bash` is 3.2.x.
3. **Non-idempotent installer.** Re-running `install.sh` writes anything new on the second run, or clobbers an existing `~/.claude/hooks/imessage-notify.conf`.
4. **Settings.json drift.** `install.sh` deletes, reorders destructively, or doesn't preserve unrelated `hooks.*` entries / other top-level keys.
5. **Hooks block on error.** A hook script can exit non-zero, hang, or throw on missing tools. Hooks must be fail-quiet (`exit 0` on every path).
6. **`install.sh` patches without `jq`.** No `sed`/`awk`/regex JSON edits. JSON is patched via `jq` only, with a parse-validation step before write.
7. **Uninstaller doesn't round-trip.** `install.sh` then `uninstall.sh` should leave `settings.json` semantically identical to its pre-install state. Any leftover `hooks.UserPromptSubmit` / `hooks.Stop` entries pointing at our paths is a fail.
8. **Missing `chmod +x`.** Hook scripts copied to `~/.claude/hooks/` must be executable.

## Soft fails (request changes)

- `set -euo pipefail` missing from `install.sh` / `uninstall.sh`.
- Hook scripts gain `set -e` (they shouldn't have it).
- README's design diagram out of sync with the actual hook flow.
- New runtime dependency added without a preflight check.
- New feature added without a paper-trail user request.
- Hook scripts use non-`/usr/bin/jq` paths or assume `jq` is on `$PATH` (live hooks should pin to `/usr/bin/jq` since shell PATH at hook runtime is minimal).

## Smell-test checklist

- [ ] `shellcheck install.sh` clean (or only known-tolerated warnings).
- [ ] `shellcheck uninstall.sh` clean.
- [ ] `shellcheck hooks/*.sh` clean.
- [ ] `bash -n` passes on all `*.sh`.
- [ ] `jq -e .` passes on every `settings.json` produced by a dry-run install on a synthetic input.
- [ ] No real Apple ID (the user's actual email/phone) appears in `git grep`. Only placeholder addresses such as `your-apple-id@example.com` may be tracked.
- [ ] `install.sh --dry-run` after a real install reports zero changes.
- [ ] `uninstall.sh` after a fresh install removes only what `install.sh` added.
- [ ] `.gitignore` covers `config/imessage-notify.conf` and `hooks/state/`.

## What review is not

- Review does not edit. Findings go back as a written list.
- Review does not run installs against the user's real `~/.claude/`. Use a synthetic `HOME` if testing.
- Review does not propose new features. Out-of-scope ideas go in a separate note, not in the review.
