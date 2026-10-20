# Muse parity test

Sends the same prompts to a fresh scratch chat in Meta's Muse and in AnythingLLM and records what each does. The core set (13 probes) measures answers; the browser group (10 probes) measures watching, steering and handing over the agent's live browser. It ends in `docs/notes/muse-parity-<date>.md`. Any agent that can run shell commands and drive a browser over CDP can run it.

## Harness

`uv run tool/parity/parity.py <command>`. The probe prompts are in `tool/parity/probes.toml`.

| Command | Does |
| --- | --- |
| `probes` | Lists the probes with what each measures. |
| `probe <id>` | Prints the prompt to send word for word. A `DO:` line on stderr is what to do besides sending. |
| `fixtures <dir>` | Writes `scratch-expenses.csv` and prints the right totals. |
| `check <id> <file>` | Checks an answer saved as text: `file` against the totals, `code` against the dice counts. Exit 0 passes. |
| `chrome` | Starts Chrome with a debugging port on its own profile and prints the endpoint. |
| `mark <run> <probe> <side> sent\|ended\|note [text]` | Logs a timestamp or a note. `side` is `muse` or `allm`. `<probe>` may be `run` for a note on the whole run, such as Muse's weekly quota. |
| `table <run>` | Prints the probe table: every core probe, and a browser probe once logged. |

`<run>` is `build/parity/<date>`, which git ignores.

## Driver

The browser tool must navigate, click by accessible name, type, press keys, evaluate script, read page text, screenshot and set files on a file input. Attach it to the Chrome that `chrome` starts (Playwright MCP `--cdp-endpoint`, Chrome DevTools MCP `--browser-url`, or another CDP client), or use a tool that drives the user's own Chrome and skip `chrome`. Chrome refuses a debugging port on its default profile, so `chrome` uses `~/.cache/parity-chrome`; the user signs in to both sites there once.

Keep the window visible: a minimised one reports `document.visibilityState` `hidden` and may drop input.

## Ground rules

Agree on these with the user before the first probe.

- **Chats:** new threads in the AnythingLLM workspace the user names, and new Muse side chats. Never an existing thread or Muse's main chat. Read only scratch chats and keep the user's personal data out of the findings.
- **Prefix:** `probe` prints `[Scratch test]` on every prompt. Do not remove it.
- **Effects:** one reminder and one artifact per side. The agent deletes only what `reminder-delete` asks of the side.
- **Never:** sending, posting, buying, connecting accounts, OAuth grants, or entering credentials. Stop and ask if an agent asks for one.
- **Server:** read-only, and only if the user gives access.
- **Quota:** note Muse's weekly figure (Settings > General > Usage) before and after.
- **Browser group:** run it only if the `tools` answer lists a browser, in a workspace made for the run so its browser holds none of the user's logins. Also allowed: httpbin's test form, a login request card declined with Not now, and the practice sign-in at `https://the-internet.herokuapp.com/login`, typed by the user. Never solve a CAPTCHA or bot check; hand the browser back untouched. Keep every probe off the sites in Muse's Secure store.

## Run

1. Run `chrome`, attach the driver, have the user sign in, and run `fixtures <run>/files`.
1. Map Muse's surface without changing anything: the left rail (Chat, Search, Feed, Ideas, Goals, Library), the side panel (Activity, Approvals, Upcoming, Identity) and Settings (Connectors, Wallet, Secure store, Permissions, Messaging channels, Devices). Close Activity before the probes: it may list an earlier run. In AnythingLLM, read Settings > Agent Skills and Scheduled Jobs.
1. For each probe in `probes` order, in a fresh chat on each side (an `after` probe continues its parent's chat):
   1. `mark ... sent`, then send `probe <id>`. The `file` probe attaches `<run>/files/scratch-expenses.csv`.
   1. When the answer ends, `mark ... ended`. AnythingLLM's footer time counts only the last generation, so the marks are the wall-clock time.
   1. Save the answer to `<run>/<id>-<side>.txt`, `check` the `code` and `file` ones, and `mark ... note` what showed.
1. `reminder-ok` goes to AnythingLLM only, and only if it asks. A stock AnythingLLM ends most agent probes in "I have no such tool"; record that as the result.
1. Run the browser group one side after the other, `return` last: browsing, and any page showing a live card, keeps the browser from stopping. If Muse answers "Something went wrong", "Message failed to send" or "Conversation controls unavailable", it is degraded: do AnythingLLM's side and return to Muse later, without a retry loop.

Tag each finding **app** (AnywhereLLM's code; give file and function), **server** (AnythingLLM or the model) or **harness** (hidden tabs, synthetic keys, the clipboard; confirm by hand before reporting).

For each browser probe also note: when the browser first showed in the chat; what showed while it worked; who the chat, card and take-over view say has the browser, before and after the answer ends; the clicks to watch, take over and hand back; the wording of each state on every surface and whether they agree; failures and stale states. Screenshots of a tab not in front come back stale, so load each surface in turn in one tab.

## Driving the two sites

| Site | Task | How |
| --- | --- | --- |
| Muse | New side chat | The "New side chat" button, located by name. The message box is near the bottom centre; click, type, press Enter. |
| Muse | Slow loads | Skeletons show for 10-15 s after a navigation. Wait. |
| Muse | Reading replies | Page text or `document.querySelector('main').innerText`. The Activity list gives each task's outcome and time. |
| Muse | Permission denied | Artifact and browser previews are opaque-origin iframes, which blocks screenshots and page text. Navigating to the thread URL again clears it. |
| Muse | Browser | "Open preview" on a Browser card opens a pane. "Take control of the browser" gives it to you ("You're in control", with Stop and Done, named "Hand browser control back to the assistant"). The agent's step shows under its avatar; Stop is in the composer, and a bar under the avatar has Stop task while the card is out of view. |
| Muse | Deleting an artifact | The library menu ignores automation; ask Muse in the artifact's own side chat. |
| AnythingLLM | New thread | The sidebar's "New Thread". The sidebar scrolls as threads are added, so locate the button again each time and check the URL became `/workspace/<slug>/t/<id>`. |
| AnythingLLM | Reading replies | Page text hides the prompt and card images while the agent runs. The footer (`model · 43.2s ...`) appears when the answer ends. |
| AnythingLLM | Browser cards | A card link opens the browser page in a new tab. Close every one before `return`: a watched browser never stops as idle. |
| AnythingLLM | Confirm dialogs | Deleting a scheduled job calls `window.confirm`, which freezes the driver. Evaluate `window.confirm = () => true` first. |
| AnythingLLM | Attachments | Set files on the hidden file input. |

## Server evidence

Optional and read-only, on the AnythingLLM host.

| What | How |
| --- | --- |
| Agent tool calls and the tool list the reranker kept | `journalctl --user -u anythingllm --since -5min` |
| Scheduled jobs and runs, memories, skill config | `sqlite3.connect("file:/srv/anythingllm/storage/anythingllm.db?mode=ro", uri=True)` from Python (the host may have no `sqlite3` binary); tables `scheduled_jobs`, `scheduled_job_runs`, `memories`, `system_settings` |
| Container time zone | `podman exec systemd-anythingllm date` (UTC) |

`system_settings` holds connector API keys. Read them only inside a script that uses them; never print them.

## Cleanup

1. Hand the browser back in every view that says you have it, and decline any waiting login request.
1. List for the user, without deleting: the scratch threads and side chats, each side's artifact, any reminder still there (AnythingLLM's agent cannot delete one; it goes in Settings > Scheduled Jobs), and a practice login saved for `saved-login`.
1. Close the tabs the session opened and stop the Chrome that `chrome` started.

## Write-up

In order: the run (date, AnythingLLM commit, server, model, Muse plan and quota); a verdict in a few sentences; the `table` output with observations; what Muse does well, widget by widget for the browser group; a gap table (Muse feature, AnythingLLM now, closest repo piece, build, size S/M/L, the app's own items first); a numbered bug table (what happens, evidence, owner tag, where to look); the process (what went wrong, and the change it makes to this runbook, made here too); what was left for the user. Lint it with the `mdlint` skill.
