# Muse compared with AnywhereLLM in Chrome

Run on 2026-10-07, 15:00-15:40 CEST, in the user's own Chrome through the Claude in Chrome extension. AnywhereLLM: commit `1e280ac`, `flutter build web`, served from `http://localhost:8765`, signed in to the home server at `<server>:3001`, so answers went straight to `stream-chat` (the browser cannot use the relay). Every AnywhereLLM chat ran in a new `parity-scratch` workspace in Agent mode, with the `AnythingLLM` workspace's prompt (`everythingllm version="45f77b7e"`) and identical `settings.json`; the model was `glm-5.3-flash`. Muse: muse.ai, free plan, each probe in a new side chat. Every prompt started with `[Scratch test]`.

## Verdict

AnywhereLLM is at parity for plain chat: Markdown, streaming, Stop, context, web search with citations, scheduling a reminder and reading a page with the live browser all worked, and its agent finished sooner than Muse on most agent probes, though on A6 and A9 only because it did less. It falls behind wherever an answer carries something other than text: charts, live-browser cards, research progress, artifacts and generated files do not show in Chrome, and three bugs make the chat itself unreliable on a fresh chat. The largest gaps that are the client's own are the media rendering, full-text search, and views of what the agent keeps (scheduled jobs, memory, artifacts). Image generation, document attachments in Agent mode and research post-back are gaps in the server, not in the app.

## Probe results

Times are wall-clock from send to the end of the answer. Muse times are read from its timestamps and Activity panel, so they are accurate to about 15 s.

| Probe | Muse | AnywhereLLM |
| --- | --- | --- |
| C1 Markdown | Heading, table, bullets, highlighted code with Copy and Download, LaTeX rendered. | 9.6 s. Heading, bordered table, bullets, code with Copy but no highlighting; LaTeX shown raw as `$$x = \frac{...}$$`. |
| C2 Stream and Stop | Streams with a fade-in edge; Stop keeps the partial text. | Streams; Stop keeps the partial text with Copy and Retry. Neither marks the answer as stopped. A stopped first answer leaves the chat named "New chat". |
| C3 Context, Edit, Retry | Context kept. No Edit and no Retry; a message's menu has only Delete. | Context kept (6.5 s). Edit and Retry exist, but on a fresh answer they fall back to signed-out behaviour (bug 1). |
| C4 Image input | Thumbnail in the composer and in the sent message; "teal, #008080", exact. | File name chip only, in the composer and the sent message; "medium blue, left edge darker", wrong (model). |
| C5 Message actions | React (emoji), Reply (quote), Copy, Delete, timestamp. | Copy, Retry, thumbs, model and time, Details (tokens, tok/s); Edit on questions. No reply, reaction or single-message delete. |
| C6 Search | Command palette, full text across messages, snippets and age. | Sidebar filter on workspace and chat names only: "Nothing matches 'Gutenberg'". |
| A1 Tool inventory | About 35 s. Research, live browser, code, files, media generation, scheduling, memory, messaging channels, purchases (wallet), artifacts and widgets, credential vault. | First try failed after 20 s: "The answer was cut off: network error". Retry 42.9 s: research, browser, code sandbox, files, scheduling, memory, Gmail, Google Calendar, site publishing; no media generation, no purchases. |
| A2 News | About 90 s. Three stories, each with date and a named inline link. | 40.3 s. Three stories with outlet, date and raw URL links; 5 source chips and "56 more". Status lines while running. |
| A3 Code | Under 90 s. Inline bar chart, exact table, file saved. Counts equal numpy `default_rng(42).integers(1,7,(10000,2))`. | 103.6 s. Exact table (equal to `default_rng(42)` drawing each die in turn, also valid). The chart shows only as text: `[Dice Sum Simulation: <server>]`. |
| A4 Artifact | About 2 min, in the background with an interim reply. Artifact card with a live thumbnail that opens in the app and lands in Library. | 69.8 s. Saved to `/project/pomodoro/index.html` in the sandbox; nothing in the app opens or shows it. |
| A5 Reminder | About 40 s. Confirmation plus a scheduled-task card with "View scheduled task"; it shows in Upcoming. | 27.1 s. Text confirmation only; no view of scheduled jobs anywhere in the app. |
| A6 Image generation | About 40 s. Watercolor image inline with a one-line caption. | 11.6 s. "This workspace has no image-generation tool". |
| A7 Live browser | Under 60 s. Preview card with "Open preview"; title, points and top comment. | 22.9 s. Same title, points and top comment; the live card shows only as text. |
| A8 Memory | About 60 s. Four categories with counts; edit and delete by asking; an Identity panel. | 51.1 s. One flat vector store holding 1 memory; no view in the app and no delete tool. |
| A9 Deep research | About 90 s, inline. Verdict, named sources, a Markdown report card. | 33.2 s to start run `dr-8338e2fd`; its progress card shows only as text, and the report goes to the research site, not the chat. |
| A10 CSV | Under 60 s. Every total exact, rent flagged, a sensible cut. | Failed twice: "The agent model failed to respond: 400" followed by `图片输入格式/解析错误` (image input format error). |
| A11 Plan Saturday | About 90 s. Calendar checked, forecast, timed itinerary from the user's home city, transit times. | 71.9 s. Calendar checked, forecast, itinerary as a table, 114 sources; assumed the user lives in Stockholm. |

The A10 file had 45 rows; the right totals were rent 9800.00, utilities 8059.08, restaurants 3196.05, groceries 2895.07, transport 2523.36, total 26473.56.

## What Muse does well

- Everything an agent makes shows in the chat as a card: images, charts, artifact previews, documents, live-browser previews, scheduled tasks. Each opens in place and is kept in a Library or the Upcoming panel.
- Long jobs answer at once ("building now, I'll drop it in here"), keep the chat usable, and post the result back into the same chat.
- A status line under the agent's name ("Searching web", "Generating image", "Checking calendar") and an Activity log of every task with its outcome and time.
- Side chats retitle themselves with a summary ("Identify scratch test image color"), and unread side chats carry a dot.
- Search covers message text, not only titles.
- Attachments show as thumbnails before and after sending.

## Gaps in the app

Ranked by how much a person would notice. Size is S (under a day), M (days), L (a week or more).

| # | Muse has | AnywhereLLM now | Closest piece in the repo | Build | Size |
| --- | --- | --- | --- | --- | --- |
| G1 | Charts, live cards and progress cards inline | Muted text `[alt: host]`, the same for a failed load and a refused one, and nothing to tap | `_Image` in `lib/ui/chat/answer_body.dart`; `answerImage` in `lib/adapters/anythingllm_client.dart` | Send CORS headers from the everythingllm card host on :8445 (server). In the app, tell a failed load from a refused one and make the placeholder open the image's link through `openLink`. | S app, S server |
| G2 | Artifacts and generated files open from the chat and a Library | A sandbox file is named in the text and nothing opens it | `GeneratedFile` and `ui/chat/generated_files.dart`; the Files pane | Show sandbox outputs the server reports, or a Files node for the workspace's `/project` and `/public`, with Open and Save. Needs a server API for the sandbox. | M-L |
| G3 | Full-text search with snippets | Name filter | `core/find.dart` `matchesSearch`; sidebar search | Search loaded histories first; full server-side search needs an endpoint. | M |
| G4 | LaTeX and syntax highlighting | Raw `$$...$$`; plain code | `ui/chat/answer_body.dart` (`flutter_markdown_plus` builders) | Add a math builder (`flutter_math_fork`) and a highlighter for `_CodeBlock`. | S-M |
| G5 | Attachments as thumbnails | File name chip | composer attachment chips; the sent turn's attachments | Draw image attachments from their bytes in both places. | S |
| G6 | Scheduled tasks view | None | `/settings` folder in the Files pane | Read-only list of the server's scheduled jobs. Needs an API. | M |
| G7 | Memory view with categories | None | Files pane | Read-only memory list. Needs an API. | M |
| G8 | Summary titles for chats | First line of the first message | `defaultTitle` in `core/chat.dart`; `_nameAfter` in `ChatController` | Ask the model for a short title after the first answer, as a rename. | S |
| G9 | Reply-to and reactions | None | Message actions | Reply as a quoted prefix; reactions have no server field. | S (reply only) |
| G10 | Answer text readable by a screen reader | Answers are absent from the semantics tree; only controls are labelled | `ui/chat/answer_body.dart` | Give each answer a `Semantics` label with its plain text (`plainText`, already used by Read aloud). | S |

AnywhereLLM-only features that Muse lacks: Edit and Retry of a message, answer metrics and Details, a chat-mode chooser, a document Sources panel with Test a question, a Files pane over the server's data, and slash-command presets.

## Bugs

| # | What happens | Evidence | Where to look |
| --- | --- | --- | --- |
| B1 | A freshly streamed answer has no `chatId`, so thumbs do not show, Edit does not say it replaces, and Retry leaves the old exchange on the server. After a reload, history gives the ids: thumbs appear, and the exchange Retry replaced is back (answers of 7.3 s and 5.7 s both stored). | C3, A2; every fresh answer this run lacked thumbs. Presets load, so the web login works. | Server: AnythingLLM's agent path (`apiChatHandler.js`) closes without `chatId`, and `automatic` mode answers every message through it. Fixed in the app: `ChatController` reads the history for the ids after such an answer. |
| B2 | While a new chat's first answer runs, the chat area is blank: no question bubble and no caret, until the whole answer appears. 4 of 14 new chats. | C2, A1, A3, A6. The header still read "New chat" throughout. | `ChatController.send`, `lib/ui/state/chat_controller.dart:574-577`: `_draft.clear()` empties the list the view was built from, and `activeThread` changes without `notifyListeners()`, so a rebuild before the answer ends reads an empty list. Assign a new list instead of clearing in place, and notify after switching to the made thread. |
| B3 | One answer failed after 20 s: "The answer was cut off: network error". Retry worked. | A1, once in about 20 answers. | The browser `fetch` stream in `HttpAnythingLlmApi.streamChat`; the extension's network log does not record streaming fetches, so repeat with DevTools open. |
| B4 | A model failure is drawn as a plain answer ("The agent model failed to respond: 400 ...") rather than the red "The answer stopped" box. | A10 against A1. | Where the agent's error text arrives as a text chunk rather than an `error` chunk. |
| B5 | A document attached in Agent mode fails with a 400 and `图片输入格式/解析错误` (image input format error). Reproduced twice. The app sends `application/anythingllm-document` as designed, so the server passes the document to the model as an image. | A10. | Server: the agent path's handling of `attachments`. App: none. |

## Visual quirks

| # | Quirk | Where |
| --- | --- | --- |
| Q1 | The sidebar's "Workspace name" field (after +) is about 16 px tall, much slimmer than the Search field under it; the text crowds its border. | Sidebar, new workspace |
| Q2 | That field closes when it loses focus and drops what was typed; a click just below it lands in Search, which then filters to "Nothing matches". | Sidebar, new workspace |
| Q3 | Text streamed before and after a tool call is joined without a space: "...instead.Done -- built and kept", "in parallel.It's a scratch test". The whole answer that replaces it is correct. | Agent answers while streaming |
| Q4 | Sending while scrolled up does not scroll to the new question; the answer runs off-screen. | Chat |
| Q5 | The Retry tooltip stays up after the click and covers the slash menu. | Answer actions |
| Q6 | CJK text first paints as empty boxes until the fallback font loads. | Web build |
| Q7 | A wide table's last column is cut at the chat's right edge with no visible sign that it scrolls. | A11 itinerary table |
| Q8 | The Sources panel was caught half off-screen once, mid-slide, after switching Files to Chats. Transient. | Shell |

Two things looked like bugs but came from the harness: Send needing two presses, and an answer that seemed not to stream. Both happened only when the AnywhereLLM tab was hidden behind the Muse tab while I typed or waited, and Flutter does not paint a hidden tab. Ctrl+C in a Flutter text field also did not reach the system clipboard under automation; check it by hand.

## Fixed since the run

Each fix has a test that fails without it, and each was checked in the Chrome build against the `parity-scratch` chats.

| # | Fix |
| --- | --- |
| B1 | After an answer that closes without `chatId`, the app reads the chat's history for the ids, under guards against taking a wrong one. |
| B2 | A list of turns the controller has handed out is never changed in place, and the view redraws once a draft has its thread. |
| G1 | An image that does not load says so, with why in its tooltip, and a tap opens the link around it or its own address. |
| Q3 | Text streamed after a tool's status line starts a new paragraph. |
| B4 | A stored or streamed `The agent model failed to respond` shows as a failure box, with Retry. |
| G4 | TeX renders as math under CanvasKit, prices stay text, and a fenced block in a known language is coloured. |
| G5 | A picture shows small in the composer and in its question, including from the history, which keeps the image's data URL. |
| Q4 | Sending while scrolled up scrolls to the new question; opening another chat starts at its newest turn. |
| G10 | Confirmed for the web build only: its semantics tree had the code and math but none of the selectable text. On the web an answer now carries its words as a label. |

## Process

What went well:

- Running the same prompt on both sides back to back, in fresh chats, made most differences plain, and the fake CSV and the dice seed gave answers that could be graded rather than judged.
- Turning on Flutter's semantics tree (clicking `flt-semantics-placeholder`) gave labelled refs for Send, Edit and New chat, which were far more reliable than coordinates.
- Hooking `HTMLInputElement.prototype.click` let the test hand files to Flutter's picker, which automation cannot otherwise reach.
- The network log turned "the chart is missing" into a server finding (503 and no CORS on :8445) in one call.

What went wrong, and what the protocol now does about it:

- Both sites shared one window, so one tab was always hidden. Flutter stops painting a hidden tab, which produced stale buttons, a false "no streaming" reading in C2, and doubtful timings. The protocol puts each site in its own window.
- The sidebar scrolled and a coordinate click on "New chat" missed, so A2 went into the A1 chat. The protocol checks the header reads "New chat" before typing.
- Answer text is not in AnywhereLLM's semantics tree, so long answers were read from screenshots, which was slow and costly. The protocol reads them from the Files pane's chat Markdown instead.
- Opening Muse showed its Activity panel, which still listed the outcomes of an earlier run of these probes before any probe ran here. That is a bias risk; the protocol closes the side panel before the first probe and reads Activity only after its own probes.
- Reading Muse with `get_page_text` dumped its main chat, which holds personal data. The protocol reads only the side chat's own text.
- The extension's network log starts only when first called and does not record streaming fetches, so it could not explain B2 or B3. The protocol starts it before the first probe and keeps DevTools for the stream.
- The agent probes measured the server more than the app: A6, A9 and A10 were server gaps. The client probes found the actionable app bugs. The protocol keeps both but tags each finding as app or server.
- Sending to both sides at once saved time but made Muse timings coarse. Exact timings need one side at a time.

The run cost 2% of Muse's weekly free-plan limit (23% to 25%).

## Left on the servers

Nothing was deleted. For the user to remove or restore:

- AnythingLLM workspace `parity-scratch` and its 15 chats (the 15th, "Count from 1 to 40", checked the fixes for B1 and B2; one more exchange in the A11 chat checked Q4).
- AnythingLLM one-off job "scratch test reminder - delete me", Thursday 2026-10-08 09:00 CEST (it deletes itself after running).
- AnythingLLM sandbox file `/project/pomodoro/index.html` in `parity-scratch`, and research run `dr-8338e2fd` on the research site.
- Muse: the "Scratch test reminder" scheduled task for Thursday 09:00 (Upcoming tab; it offers only Delete), the "Pomodoro Timer" artifact, the fox image, and the "Search backend comparison report" document. The 14 scratch side chats are archived, not deleted; Muse's A1 prompt went into the C4 side chat after a missed "New side chat" click.
