# Muse parity test: what the 2026-10-14 rewrite changed

Sidecar to `docs/protocols/muse-parity-process.md`.

## Why

The runbook was written on 2026-10-07 for Claude Code with the Claude in Chrome extension, against the everythingllm host on owen. Two things made it unusable by another agent or on today's server:

1. Its mechanics lived in prose: the probe prompts, the CSV recipe and its right totals, the dice answers, and timing by hand. Every run restated them.
1. Its evidence section and several probes assumed host code that was archived on 2026-10-12.

## What moved into `tool/parity/`

| Was prose | Now |
| --- | --- |
| The 11 prompts and what each measures | `probes.toml`, printed by `parity.py probe` |
| The CSV recipe and totals | `parity.py fixtures`, which prints the totals; they are the ones the deleted `parity-process.md` gave (total 26473.56), not the 28840.28 this runbook gave, whose generator was never written down |
| Comparing an answer with the totals or the dice counts | `parity.py check` |
| Wall-clock timing | `parity.py mark` and `table` |
| Claude in Chrome | Any CDP client, attached to the Chrome that `parity.py chrome` starts |

## What was dropped

- `hostctl`, `research-runner`, `agents-runner`, the sandbox folders and the Google Apps Script bridge check: the host is archived and AnythingLLM runs stock, so these have nothing to read.
- The findings location `docs/.notes/muse-parity.md` on owen. Reports go in this repository's `docs/notes/`, as the 2026-10-07 and 2026-10-08 ones did.
- Deleting the deep-research entry on the research site, and the `algorithms` workspace slug: the user names the workspace.

## The merge of 2026-10-14

`docs/protocols/parity-process.md` and `docs/protocols/browser-parity-process.md` were folded into the Muse runbook and deleted. Both are in git history (the commit before this one).

| From | Kept | Dropped |
| --- | --- | --- |
| `parity-process.md` | The totals (via `fixtures`), the dice check, the owner tags, the findings outline, the Muse driving notes | The client probes C1-C7 and every note on driving AnywhereLLM's Flutter web build: the Android-only branch has no web target. The `parity-scratch` setup that copied a prompt between workspaces. The CORS check for card images |
| `browser-parity-process.md` | The browser probes as the `browser` group (W1 is the core `browser` probe; W7, the narrow-window probe, is dropped with the web build), the measures, the Muse browser driving notes, the ground rules for logins | `hostctl browser-reset`, the card host on :8445, the browser container and `browser-runner` evidence, and its seven-part report (the shared write-up covers it) |

The browser group assumes the browser-lean skill from `CLAUDE.md`; whether a stock AnythingLLM has it was not checked, which is why the runbook gates the group on the `tools` answer.

Dated records that cite the deleted runbook, left as written: `docs/archive/browser-ux-2026-10-08.md` and `docs/archive/browser-parity-2026-10-07.md` cite `browser-parity-process.md`; `docs/notes/muse-parity-2026-10-08.md` cites `docs/protocols/parity-protocol.md`, a name that never existed.
