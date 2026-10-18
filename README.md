# imessage-notifier

**Get a text on your iPhone when Claude Code finishes a long task.**

Start a long job → walk away → your phone buzzes when it's done.

---

## What you need

- A Mac
- Messages.app signed into iMessage with your Apple ID
- An iPhone (or any Apple device) on the same Apple ID
- `jq` — if you don't have it: `brew install jq`

## Set it up

```sh
./install.sh
```

Then open the config file and set your Apple ID:

```sh
open ~/.claude/hooks/imessage-notify.conf
```

Change this line to the email or phone you'd use to iMessage yourself:

```
APPLE_ID="you@example.com"
```

Save. Done. The next long task in Claude Code will text you when it finishes.

## Test it

Run a task that takes more than 5 minutes. When it finishes, you'll get an iMessage like:

> [Claude] my-project (8m12s)
> 📋 Add session name + what's-done to notifier
> 📝 Fixed the pager's off-by-one and re-ran the test suite; all green.
> ✅ Built + hardened the self-contained work-laptop prompt

Line 1 is the project and how long the turn took. 📋 is the session's auto-generated name. 📝 is what this turn did: the headline of Claude's final reply (its `result:` / `needs input:` / `failed:` line if it wrote one, otherwise its first real sentence), up to 140 characters. ✅ is a ~10-word recap of the session's focus, taken from the assistant's own session-focus line. Each of those three lines appears only when its info is available; with none of them you just get the plain `turn done` line.

If your task was shorter than 5 minutes, no message — that's by design (see below).

## Tweak when you get pinged

Edit `~/.claude/hooks/imessage-notify.conf` and change `MIN_SECONDS`:

| Value | What you'll get |
|---|---|
| `0` | A ping for every response, even instant ones |
| `30` | Skip only the truly trivial back-and-forth |
| `90` | Skip "quick chat" turns |
| `300` | Only ping on long jobs (default) |
| `600` | Only "I went to lunch" jobs |

Saves take effect on the very next turn — no restart needed.

Don't want the 📝 line? Set `TURN_SUMMARY=0` in the same file (add the line if your config predates it).

## Remove it

```sh
./uninstall.sh
```

It'll ask before deleting your config (since it has your Apple ID in it). The hooks and Claude Code wiring come out unconditionally.

## Not getting messages?

| Symptom | What to try first |
|---|---|
| No message after a task | Was the task shorter than `MIN_SECONDS`? Lower it and try again. |
| Still nothing | Inside Claude Code, type `/hooks` to reload settings. |
| Error about iMessage service | Open Messages.app, sign in to iMessage with the Apple ID you put in the config. |
| `jq: command not found` during install | `brew install jq` and re-run `./install.sh`. |

## How does it actually work?

For the architecture, time-sequence diagram, failure modes, and known limitations, see [DESIGN.md](DESIGN.md).
