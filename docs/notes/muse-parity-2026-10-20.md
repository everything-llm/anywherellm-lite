# Muse compared with AnythingLLM's web UI: browser run

Run on 2026-10-20, 14:03-16:20 UTC, by `docs/protocols/muse-parity-process.md`. AnythingLLM 1.16.2 with the suite's system prompt on the home server, its web UI, in a new workspace `parity-scratch-1020` in Agent mode on the system default model (`glm-5.3-flash`). Muse: muse.ai, Power plan. The driver was Claude Haiku through the Claude in Chrome extension in the user's own Chrome, in five batches, each reviewed by the supervising session, which re-ran every `check` and read the saved answers. The Lite client was not run. Probes run: all core probes except `research`, and every browser probe except `saved-login`, which needs the user to save a login.

## Verdict

Both sides answered the plain probes correctly and agree on the file totals. AnythingLLM stalled on `code` twice, created a scheduled job without asking, sent an image prompt to a third-party service, and lost the whole exchange when Stop was pressed in Agent mode. Its browser cards go stale once the agent's tab is closed: the card link and its image answer 404 after 20 minutes. Muse started an unrequested second artifact and showed a take-over pane that did not match what its reply described. Muse's Stop and AnythingLLM's leave-and-return could not be measured.

## Probe results

Times are from the `sent` and `ended` marks, written just before the send key from batch 2 on. Batch 1's `sent` marks were written up to 60 s early, so the batch 1 times (Tools, News, Code, File) are upper bounds.

| Probe | Muse | AnythingLLM |
| --- | --- | --- |
| Tools | 108 s. Self-inventory from context; no tool called. | 128 s. Says it used no tool; lists a sandbox it says it cannot call. |
| News | 100 s. Three stories with outlet and date; no URLs in the text. | 85 s. Three stories and an honourable mention, URLs in the text; one story overlaps Muse's. |
| Code | 87 s. Exact-count table totalling 10,000 and a bar chart; check passes (11 of 11). | Stalled twice (after a thought block that said the workspace has no Python sandbox); no answer. The first thread kept no exchange. Check fails. |
| File | 46 s. Total 26,473.56 kr, rent biggest; check passes. The attachment shows as `scratch-expenses-2.csv`. | 131 s. Same totals; check passes. Its file tool was denied access, so it summed the pasted CSV. |
| Artifact | 169 s. Card `Pomodoro Timer`; also started an unrequested second artifact. Hosting not verified. | 773 s. Wrote an apps-lean app called `pomodoro` after a validator rejected several writes; whether it edited an app that already existed or the starter it had just made is unresolved. Reply says private; not verified. |
| Reminder | 64 s. One-off, Oct 21 09:00 CEST. | 97 s. Created scheduled job #28 for Oct 21 09:00 CEST without asking. |
| Reminder approval | Not run. | Not run: it never asked. |
| Reminder delete | 30 s. Reply says deleted; not verified in Muse. | 35 s. Reply says deleted; the Scheduled Jobs page no longer lists #28. |
| Image | 73 s. Inline image, one-line description. | 124 s. Fetched from `image.pollinations.ai`, a third-party service, with the prompt in the address. |
| Memory | 83 s. Counts only: 39 entries in four categories. | 176 s. Counts only: 5 pinned, 25 notes, 0 documents. Its reply listed personal facts, which were not saved. |
| Multi-step | 146 s. Checked the calendar: clear for the day. Weather source not named. | 304 s. Could not check the calendar (none connected to this workspace; the Gmail toolkit sign-in is stale). Weather from Yr. |
| Browser | 81 s. Card about 14 s after sending; Completed with Open preview. | 50 s. Status line about 11 s after sending; the card link opens a page whose bar reads Agent. |
| Browser navigate | 104 s. 1950. Status stayed `Browsing Wikipedia` about a minute after the card said Completed. Counted the search as a page. | 85 s. 1950. Two page loads; did not count the search. |
| Browser fill | 48 s. Echo matched; the form labels the topping `Extra Cheese`. | 57 s. Substituted `Extra Cheese` for `Cheese` and said so, without asking. |
| Browser handoff | 41 s. Four clicks to watch, take over, scroll and hand back. The pane showed `httpbin.org/post`, not the form the reply named. | 48 s. One tap to take over, one to hand back. Clicking the card link opened nothing; its address was opened by hand. |
| Browser take-back | 60 s. Read the field as empty, from a fresh copy of the form. | 62 s. Could not read the textarea; did not say the field was empty because nothing was typed. |
| Browser login wall | 77 s. No login card; listed the forms. | 70 s. No login card; told the person to take the tab over and enter credentials. |
| Browser second task | 73 s. A second card of its own; the first stayed unchanged. | 213 s. About 3 minutes of silent `Agent is thinking...` before the card appeared. |
| Browser leave and return | 91 s. The running chat's row showed a blue dot, with no spinner or label; the chat resumed live on return. | Not measured: leaving a running thread opens a `Stop generating response?` guard, and Continue stops the answer. |
| Browser stop | Not tested: the agent finished before a second step showed, and Stop was not pressed. | 92 s. Stop worked, but the thread was empty after a reload, question included. |
| Browser return | 46 s. After 20 minutes the card still read `Completed`; the agent named the last page. | 60 s. The card link and its image both answer 404; the agent says its browser has no page open. |

## Findings

Each is tagged with its owner. Items marked unresolved have no confirmed cause.

1. **Server, unresolved:** `code` on AnythingLLM stalled twice, once in batch 1 and once on a retry in a new thread. After its thought block the model said the workspace has no Python sandbox and then went silent. The suite's system prompt says sandbox access is per workspace, and a new workspace may lack it. This was not checked.
1. **Server:** the `reminder` probe created scheduled job #28 with no approval request, although the suite's system prompt says to ask before creating scheduled jobs. The job was removed afterwards.
1. **Server:** the `image` probe fetched its picture from `image.pollinations.ai` with the prompt in the address. The prompt left the home server.
1. **Server:** the `login-wall` reply told the person to take the tab over and enter credentials there, instead of using a login request.
1. **Server:** `fill` changed the topping from Cheese to Extra Cheese on its own; it said so in the reply.
1. **Server:** pressing Stop in Agent mode left the thread empty after a reload, question included. Whether the server dropped the save or the page read nothing was not verified.
1. **Server or app, unresolved:** the browser card on AnythingLLM answers 404 for the page and for its image after the agent's tab is closed, so the card is a broken image.
1. **Server:** `plan` could not read a calendar: none is connected to this workspace, and the Gmail toolkit sign-in is stale. Re-signing in is the user's step.
1. **Muse:** the `artifact` probe started a second artifact that was not asked for. Its take-over pane showed `httpbin.org/post`, not the form its reply described.
1. **Web UI:** leaving a running thread opens `Stop generating response?`, and Continue ends the answer. Lite does not have this guard and lets other chats answer at once.

## What this means for Lite

1. Lite's `Stopped · the server may still save it` line promises a saved answer. This run saw a Stop in Agent mode that kept nothing. The line is one data point away from being wrong, and Lite's note that Retry and Edit leave the old exchange on the server does not cover a missing one.
1. A card image that 404s shows in Lite as `[alt: did not load]`. That is the right fallback, but the card's page and image also go missing when the agent's tab closes, so Lite's browser sheet can open to a 404.
1. Muse's unread dot on a running chat in the list has no counterpart on a running chat in AnythingLLM's web UI. Lite's `ReadyDot` marks only an answer that ended.

## Process

1. The driver was Claude Haiku. A DeepSeek driver (`~/.local/bin/claude-ds`, on DeepSeek's Anthropic-compatible endpoint) was set up and passed a one-word test, but was not used.
1. Batch 1 read Muse's main chat, which holds personal content, and two screenshots of it were deleted from `/tmp`. Batch 4 opened another personal chat by a mis-click on a list row that had shifted; its text was not read or recorded. The protocol now says to open a Muse chat by its URL.
1. `parity.py mark` now accepts `run` as the probe for a note on the whole run, and `table` says when there is no log. Both are in commit `cfb333a`.
1. The protocol's server-evidence commands were checked read-only on owen and are all still correct: the user unit `anythingllm`, the database at `/srv/anythingllm/storage/anythingllm.db` with its four tables, and the container `systemd-anythingllm`, on UTC.
1. The run's text is archived in `docs/notes/parity-runs/2026-10-20/`, but only as final answers and notes: the whole chats were not saved. After the user deleted the Muse side chats, Muse's archived view listed none of them, and Muse itself, asked read-only, reported all 15 as gone with no messages. The AnythingLLM threads were not exported.
1. Muse's weekly quota went from 17% used (412M tokens left) to 18% (409M left).

## Left on the servers

1. AnythingLLM: the workspace `parity-scratch-1020`, which holds every scratch thread of this run. The apps-lean app made by the `artifact` probe may outlive the workspace and should be looked for in the apps list afterwards.
1. Muse: 15 scratch side chats, one empty draft, and the artifacts `Pomodoro Timer` and `pomodoro-timer-2`. Muse's reminder is reported deleted but was not checked in its list.
1. `image.pollinations.ai` holds one picture that cannot be removed from here.
