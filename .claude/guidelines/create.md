# Create rubric — imessage-notifier

What "good" looks like for new artifacts in this project.

## Defaults

- **macOS-only.** Don't add Linux/WSL branches. Use `osascript`, `/usr/bin/jq`, `/usr/bin/*`.
- **Bash 3.2 compatible.** macOS default `/bin/bash` is 3.2.x. Avoid `mapfile`, `${var^^}`, associative arrays, `[[ -v ]]`, process substitution where it matters.
- **No PII.** Never write a real Apple ID, phone number, email, or token into a tracked file. Placeholders only (`your-apple-id@example.com`).
- **Idempotent.** Anything that touches `~/.claude/` must be safe to re-run. Check before write, dedupe before append, never clobber user config.
- **Fail-quiet hooks.** Hook scripts must exit `0` on every error path. They cannot block a Claude Code turn.
- **`set -euo pipefail` for installers, not for hooks.** Installers should bail on error; hooks should swallow them.
- **No new features without a user request.** This project packages what exists. Resist the urge to "improve" it.

## Shape of a good change

- Edits the canonical copy under `hooks/` or `config/`, not the live deployment under `~/.claude/`.
- Adds at most one new responsibility per file. If the diff feels like two jobs, it's two changes.
- If `install.sh` changes its `jq` logic, the change includes a mental round-trip check: fresh install → uninstall → diff vs original `settings.json` should be empty (key ordering aside).
- Hook scripts stay short and linear. No subshell-heavy plumbing. No conditional notification text engines.

## Format

- Shell: 2-space indent, lowercase variables for locals, UPPERCASE for env/config.
- Markdown: ATX headers, fenced code blocks with a language tag, no trailing whitespace.
- Line endings: LF only.

## Done means

- File at the requested path with the spec'd contents.
- Executable bit set on `*.sh` (the creator runs `chmod +x`).
- No real Apple ID anywhere in the diff.
- README's design diagram still matches behavior.
