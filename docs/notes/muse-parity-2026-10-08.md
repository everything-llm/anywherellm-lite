# Muse compared with AnywhereLLM in Chrome: quick run

Run on 2026-10-08, 15:43-15:59 CEST, by the runbook `docs/protocols/parity-protocol.md`, cut to the probes that finish in about a minute and need no approval. AnywhereLLM: commit `60878c6`, `flutter build web`, served from `http://localhost:8765`, already signed in to the home server, so answers went straight to `stream-chat`. Workspace `parity-scratch` from the 2026-10-07 run, in Agent mode; model `glm-5.3`. Muse: muse.ai, free plan, each probe in a new side chat. Probes run: C1-C7, A1, A2, A7, A8, A10. Skipped: A3, A4, A9 and A11 as long, A5 as needing the user's OK and leaving a job, A6 as the server has no image tool.

## Verdict

Plain chat is at parity and ahead of Muse in places: math, highlighted code, picture thumbnails, Stop with a stopped marker, Edit and Retry that replace on the server, and a browser panel all work, and every fix from the 2026-10-07 run that this run exercised held. Two new app findings: a short answer is centred in the chat column, and a stopped agent answer says it was not saved when the server saved all of it. The gaps that remain are full-text search, the live card on the web build (the card host still sends no CORS headers), and anything the server cannot do: the agent path now refuses every attachment, picture or document.

## Probe results

Times are wall-clock from send to the end of the answer, from the answer's footer on AnywhereLLM. Muse ran in parallel, so its times are coarse.

| Probe | Muse | AnywhereLLM |
| --- | --- | --- |
| C1 Markdown | Under 20 s. Heading, table, bullets, code with Download and Copy, inline math. | 8.5 s. Heading, table, bullets, highlighted code with Copy, display math. An emoji in the table showed as a box on first paint, then rendered. |
| C2 Stream and Stop | Status "Drafting article..."; fast stream; Stop keeps the partial text, with no marker. Its summary in C3 knew it was cut off. | Thinking, then a stream; Stop keeps the partial text with `Stopped · not saved in the chat`, Copy and Retry; the chat is named from the question. After a reload the full answer (63.5 s, about 1500 words) is in the chat: bug B6. |
| C3 Context, Edit, Retry | Context kept. No Edit or Retry. | 6.8 s, context kept. Edit says sending replaces the message and everything after it; the edited exchange (8.9 s) and the retried answer (8.4 s) replaced the old ones, and a reload shows only the last. |
| C4 Image input | Thumbnail in the composer and the message; "teal, exactly #008080". | Thumbnail in the composer and the question. The model failed: `400 messages.content.type is invalid, allowed values: ['text']`, shown as a failure box with Retry. |
| C5 Message actions | React, reply, copy; a menu with Delete on own messages. | Copy, Retry, thumbs, model and time, Details; Edit on questions. Unchanged. |
| C6 Search "Cai Lun" | Two hits with snippets, age and chat name. | `Nothing matches "Cai Lun".` Names only. |
| A1 Tool inventory | Still streaming after 60 s; a long list including widgets, a feed, ideas and a credential vault. | 33.1 s, no network error. Research, browser, code, sandbox files, matplotlib charts, scheduling with a list and delete, memories with view and forget, site building, apps with live cards. |
| A2 News | Under 40 s. Three stories, each with outlet and date. | 73.5 s. Status lines, three stories with named inline links and dates, 5 source chips and "227 more". |
| A7 Live browser | Under 50 s. A browser card with a thumbnail and Open preview; the story, 141 points, the top comment. | 25.0 s. The same story, points and comment. A browser chip while running and a Browser button in the header; the card shows as `[Browser: Hacker News: did not load]`. |
| A8 Memory | A curated file, a fact bank with categories and counts in the hundreds, daily logs and people pages. | 31.9 s. Global facts 5 of 5, workspace facts 0 of 20, document memory; view and delete by asking. Its table's last column was cut at the chat's edge. |
| A10 CSV | Every total exact, rent flagged, restaurants as the cut. | Failed with the same 400 as C4, shown as a failure box. |

The A10 file's right totals were rent 9800.00, utilities 8059.08, restaurants 3196.05, groceries 2895.07, transport 2523.36, total 26473.56.

## Fixes from the 2026-10-07 run, checked

| # | Held | Evidence |
| --- | --- | --- |
| B1 | Yes | Thumbs on every fresh answer; Edit and Retry replaced on the server, confirmed after a reload. |
| B2 | Yes | The question and a caret showed at once in every new chat. |
| B3 | Not seen | No cut-off answer in 10. |
| B4 | Yes | C4 and A10 failures drawn as failure boxes with Retry. |
| G1 (app) | Yes | The card that did not load says so, as a link; the browser panel opens with Take over and the steps. |
| G4 | Yes | Display math and coloured Python in C1. |
| G5 | Yes | A picture shows small in the composer and in the question. |
| Q3 | Not checked | No answer was read while it streamed between tools. |
| Q4 | Not checked | No message was sent while scrolled up. |

## Gaps in the app

| # | Muse has | AnywhereLLM now | Closest piece in the repo | Build | Size |
| --- | --- | --- | --- | --- | --- |
| G1 | Live browser card inline | `[Browser: Hacker News: did not load]`; Chrome got a 503, and curl gets a 200 `multipart/x-mixed-replace` with no `Access-Control-Allow-Origin` | Server: the everythingllm card host on :8445 | Send CORS headers from :8445 for the app's origins. | S server |
| G3 | Full-text search with snippets | Name filter | `core/find.dart` `matchesSearch`; sidebar search and `QuickSwitcher` | Search the loaded histories first; full search needs a server endpoint. | M |
| G8 | Summary titles ("History of paper essay") | The question's first line | `defaultTitle` in `core/chat.dart` | Ask the model for a short title after the first answer. | S |

## Bugs

| # | What happens | Evidence | Where to look |
| --- | --- | --- | --- |
| B6 | A stopped agent answer is labelled `Stopped · not saved in the chat`, but the server finishes and saves the whole answer. The next question is answered with the full text in its context, and a reload shows it. | C2: stopped about 5 s into the text; the reload showed 63.5 s and about 1500 words. C3's summary named the Islamic world and the Fourdrinier machine, which only the unseen part held. | App: the label in `_Answer`, `lib/ui/chat/message_list.dart:683`, and whether the web `fetch` is aborted on Stop (`HttpAnythingLlmApi.streamChat`). Server: AnythingLLM's agent path does not stop when the client goes. Say the answer may still be saved, and mark the turn `unfinished` so the chat is read again. |
| B7 | An answer narrower than the column, such as one line, is centred in the column: its reasoning toggle, text and action row start 112 px in. | C3's retried answer, before and after a reload; A7's running turn. Wrapped answers fill the column. | `_turn` in `lib/ui/chat/message_list.dart:173`: `Center` and `ConstrainedBox(maxWidth: Sizes.column)` hand `_Answer`'s `Column` loose constraints, so it shrinks to its widest child. Give the answer the column's full width. |
| B5 | The agent path refuses every attachment with `400 messages.content.type is invalid, allowed values: ['text']`; on 2026-10-07 a picture got an answer. | C4, A10. | Server: the agent path's handling of `attachments`, or the model's provider settings. App: none. |

## Visual quirks

| # | Quirk | Where |
| --- | --- | --- |
| Q6 | An emoji first paints as an empty box until the fallback font loads. | Web build, C1 table |
| Q7 | A wide table's last column is cut at the chat's edge with no sign that it scrolls. | A8 table |
| Q9 | The browser panel's steps read `Opening news.ycombinator.com` twice, though the second opened the comments page, since a step names only the host. | `browserStep`, `core/browser.dart` |
| Q10 | Escape in the sidebar search left the query in place, and the search hides New chat. Not confirmed by hand. | Sidebar search |

## Fixed since the run

Each fix has a test that fails without it.

| # | Fix |
| --- | --- |
| B6 | A stopped answer says `Stopped · the server may still save it`. The chat is already read again when it next opens, since the turn is `unfinished`, so a saved answer shows then. |
| B7 | Each turn takes the column's full width, so a one-line answer starts where a wrapped one does. |
| Q7 | A table wider than the chat shows its scrollbar under it. |
| Q9 | A browser step names the page by host and path, `Opening news.ycombinator.com/item`, never its query, the path cut at 40 characters. |

## Process

What went wrong, and the change it makes to the runbook:

- The Chrome window was hidden for the whole run (`document.visibilityState` was `hidden`, 0 animation frames a second), so Flutter painted only when a screenshot forced a frame. Fade-ins looked stuck half-drawn, and a first click after a layout change was probably lost for the same reason. The runbook now checks the window is visible before the first probe.
- Clicking `flt-semantics-placeholder` after the extension had reconnected left the composer unable to take focus; a reload fixed it. The runbook now says to reload and drive by coordinates when that happens.
- A reload reopens the last chat, so a typed probe can land in an old chat. The runbook's New chat check covers it; it now names the reload case.
- An active sidebar search hides New chat, so a click there misses. The runbook now clears the search after C6.
- Both sites shared one window, because the extension opens tabs in one group. Driving one side at a time and taking a screenshot before each action made it work.

The run cost 1% of Muse's weekly free-plan limit (41% to 42%).

## Left on the servers

Nothing was deleted. For the user to remove:

- AnywhereLLM workspace `parity-scratch`: 8 new chats from this run (C1, C2 with C3, C4, A1, A2, A7, A8, A10), beside the 2026-10-07 ones.
- The everythingllm browser session the A7 probe opened, which stops when idle.
- Muse: 8 new side chats (C1, C2 with C3, C4, A1, A2, A7, A8, A10).
