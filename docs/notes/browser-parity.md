# AnywhereLLM's in-chat browser compared with Muse's

Run on 2026-10-07, 21:05-21:45 CEST, in the user's own Chrome through the Claude in Chrome extension, by the protocol in `docs/notes/browser-parity-process.md`. AnywhereLLM: commit `468e74d` with the uncommitted Markdown fix for cards whose description holds an address, `flutter build web`, served from `http://localhost:8765`, signed in to owen at `https://<server>:3001`, so answers went straight to `stream-chat`. Every AnywhereLLM chat ran in a new `parity-scratch` workspace in Agent mode with the server's default prompt and `glm-5.3`. everythingllm on owen: `6d92928`. Muse: muse.ai, free plan (26% of the weekly limit used before the run), each probe in a new side chat; the run took Muse from 26% to 28% of its weekly limit, while Muse also ran the user's own tasks.

## Verdict

Both agents got every answer right, and ours was as fast or faster on W1, W4 and W5. Muse is far easier to follow: a browser task shows in the chat the moment it starts, as one card whose status changes in place, and its preview opens beside the chat. Ours shows the browser only through a card the agent pastes at the end of its answer. On this run that card was missing in two of five chats, because every chat started through AnythingLLM's developer API shares one browser tab per workspace (bug 1). When the card does show, it says nothing for up to 30 s and then says the agent is still browsing after it has finished (bugs 2 and 3). Ours handled control better: taking over and handing back worked first time, and its login form says whose site it is. Muse failed to take its browser back and locked the chat.

The pinned indicator asked for earlier needs bug 1 fixed first. Until the server keeps one tab per chat, no client can tell which chat a browser belongs to.

## Probe results

Times are wall-clock from send to the end of the answer, from the page clock; Muse's are accurate to about 10 s. "First sight" is when anything of the browser first showed in the chat.

| Probe | Muse | AnywhereLLM |
| --- | --- | --- |
| W1 Read | About 95 s. :+1: on the question at once; status "Browsing site" under the avatar at 35 s; a Browser card "Checking site" at about 60 s, then "Completed" with a thumbnail and Open preview; an interim message, the answer, and a link card for the page. | 35 s. Status lines `Running browse`, `Running browser-act` and the agent's own narration ("Now opening its comments page"). The card came last, as text: `[Browser: Hacker News: did not load]` (no CORS on :8445). In AnythingLLM's UI the same card was blank for 30 s after the page loaded. |
| W2 Navigate | Under 30 s. Card with thumbnail, the year, the two pages. | 40 s. Right year and page list. No card at all: the tab was W1's, so `browse` gave none (bug 1). |
| W3 Fill | About 45 s. Status "Filling form"; the card went Working, then Completed with a thumbnail. Noted that the topping is "Extra Cheese". | 77 s. Seven `browser-act` calls, each shown as the same `Running browser-act`. Right values, noted "Extra Cheese", said "the browser tab is showing it live" and "you can take over the tab", with no card or link to do it with. |
| W4 Handoff | Reply under 10 s, no new card: the W3 card turned "Waiting for you". Open preview, then Take control: 2 clicks. The header said "You're in control" with Stop and Done. Done failed twice ("Couldn't release browser control. Try again."), the follow-up failed ("Message failed to send"), and the chat locked: "Conversation controls unavailable". | Handoff 11 s, with a card. Tapping it opened the take-over view in a new tab, already reading "You have the browser" in amber with the agent's reason: 1 click. "Hand back to the agent" worked at once: 1 click. The follow-up took 17 s and read the field right. |
| W5 Login wall | About 40 s to open the page; it judged no login was needed. Asked again, it showed an inline "Secure Store" card; Add opened an in-app modal with the site filled in. Cancelled. | On gitlab.com: 110 s of waiting through a Cloudflare check, then a handoff whose card read "Just a moment..." (handed back untouched). On news.ycombinator.com: 40 s to a "Log in to ycombinator.com" card. Its form, in a new tab, names the workspace, the page and who owns the site, and warns that no login exists yet. Declined with Not now; the agent is not told. |
| W6 Return | Not run. | Not run. The browser stopped as idle at 21:41:59, but the run ended before the probe. |
| W7 Narrow (500 px) | A phone layout with a bottom tab bar; the threads failed to load, so the card and preview could not be seen. | The chat and the card's description fit. The take-over view shrinks the 1280 px screen to fit, so its text is about 4 px high and taking over needs zoom. The login form fits and reads well. |

Also seen in every take-over view: Chromium's "Restore pages? Chromium didn't shut down correctly" bubble (bug 4). A view opened from one chat's card showed whatever the workspace's browser had in front: W1's view showed W3's form.

## How Muse does it

- **One card per browser task, placed when the task starts.** It shows a globe, the task's title and a status that changes in place (Checking site, Working, Completed, Waiting for you, Paused), with a thumbnail of the page once there is one. A handoff changes the existing card rather than adding one.
- **Status in words.** The step shows under the agent's avatar and in the side panel ("Browsing site", "Opening site", "Filling form"), and each task lands in the Activity list with its outcome and time.
- **A preview beside the chat.** Open preview splits the window: the chat stays on the left, and the right shows the task's title and status, a tab strip, the live browser with its own address bar, and "Take control of the browser". Taking control turns the header into "You're in control" with Stop and Done.
- **Interim messages.** A browser task answers at once ("Opening Hacker News in the live browser now, I'll bring back the details") and posts the result as a second message, so the chat is not blocked while it runs.
- **Credentials in place.** A login request is an inline card whose Add opens a modal over the chat, with the site filled in.

## Gaps

Ranked by how much a person would notice. Size is S (under a day), M (days), L (a week or more).

| # | Muse has | AnywhereLLM now | What we already have | Build | Where | Size |
| --- | --- | --- | --- | --- | --- | --- |
| G1 | A browser card in every chat that browses | A card only in the first chat of a workspace to browse, and only if the model pastes it | `browse` hands the card to a chat whose tab is new (`anythingllm/agent-skills/browse/handler.js`) | Fix bug 1; then every chat's first browse carries its card | AnythingLLM | S |
| G2 | The card's status changes in place, from the start of the task | The card's strip changes with who holds the browser, one frame late, and says "the agent is browsing" after the answer ends | `Live.frames` and `Runner.state` (`packages/browser/src/browser/live.py`, `runner.py`) | Fix bugs 2 and 3, so the strip says Working, Waiting for you, You have it, Idle and Closed as they happen | everythingllm | S |
| G3 | Status in words for each step | `Running browser-act` for every step | `agentStatus` (`lib/core/chat.dart`) drops the tool's arguments; `browser-login` already calls `this.introspect` | Have the browser skills `introspect` one short line per call ("Opening httpbin.org", "Filling Customer name", "Clicking Submit"), which AnythingLLM's own UI shows as well | everythingllm | S |
| G4 | Something in the chat as soon as the agent starts browsing | Nothing until the answer ends | `agentStatus` sees `browse` and `browser-*` calls as they start | While a running answer's status names a browser skill, show a Browser chip in the answer; replace it with the card when the card arrives | app | S |
| G5 | A preview beside the chat | The card's link opens the take-over view in a separate tab or app | `ChatController.imageFrames` already reads the live card, at about one frame a second | Open a card in a pane beside the chat that draws its live frames large, with Take over opening the view; no web view needed | app | M |
| G6 | A credentials modal in place | A login form in a separate tab, clearer about whose site it is | `/login/<id>/` (`packages/browser/src/browser/takeover.py`) | Keep the form; on Android it already opens in a Custom Tab over the app | -- | -- |
| G7 | Quick handoff on a bot check | 110 s of waiting through Cloudflare, then a card titled "Just a moment..." | `browse` and `browser-act` replies; `Runner.card` | Say in the reply when the page is a known challenge, so the agent hands over at once; title the card with the site, not the page title or address, when the title is a challenge or empty | everythingllm | S |
| G8 | A phone layout and native apps | The take-over view is unreadable at phone width | noVNC with `scaleViewport` (`packages/browser/src/browser/static/app.js`) | Below a width, turn off `scaleViewport` and let the view pan, with a zoom toggle | everythingllm | S-M |
| G9 | The chat stays usable while a browser task runs | The composer waits for the whole answer | The relay runs the answer to its end | Out of scope for the browser: Muse's interim-message pattern needs the agent to reply before its tools finish | AnythingLLM | L |

Ruled out: carrying the card in the answer's `outputs`, which the app already reads. A skill can add one (`this.super._pendingOutputs`), but AnythingLLM 1.16.2's UI draws any output type it does not know as a file download card, so a native client would show a broken card.

## Bugs

| # | Bug | Evidence | Where to look |
| --- | --- | --- | --- |
| 1 | Every chat started through the developer API shares one browser tab per workspace, and with it one card, one take-over target and one sandbox `threads/` folder. | W4's handoff card in the W3 chat opened `?tab=bw-c1a3414dfe0756b7`, W1's tab. W2 and W3 got no card because the tab was not new to "their" chat. `EphemeralAgentHandler` builds `handlerProps.invocation` as `{workspace, workspace_id}` with no `thread_id` (`/app/server/utils/agents/ephemeral.js:525` in the container), so `_lib/scope.js` gives every app chat the thread `default`. The relay posts to the same API, so the app on Linux and Android is affected too. | Upstream AnythingLLM: add `thread_id: this.#threadId` to the invocation. |
| 2 | A live card shows nothing in a browser until its second frame, and then always the one before. | In AnythingLLM's UI the W1 card's `<img>` had `naturalWidth` 0 for 30 s after the page loaded and 1280 after the first `TICK`. `push` writes each part's closing delimiter only with the next frame, and Chrome draws a part once the next delimiter arrives. A still page sends its next frame after `TICK` (30 s). | `chatimage.live.push` (`packages/chatimage/src/chatimage/live.py`): write the next `--frame` delimiter right after each part. The app's reader (`lib/adapters/image_frames.dart`) emits by `Content-Length` and is unaffected. |
| 3 | The card and the take-over view say the agent is browsing after the agent has finished. | The W1 card's strip read "the agent is browsing" after the answer ended; the view said "The agent has the browser; you're watching". | `Runner.state` (`packages/browser/src/browser/runner.py`) knows who holds the browser, not whether an op is running. |
| 4 | Chromium's "Restore pages?" bubble covers the page's top right in the take-over view. | Every view from W1 to W5; the container started at 21:05:38 on a profile left from an earlier `parity-scratch`. | `browser.driver`'s Chromium launch: `--hide-crash-restore-bubble`, or mark the profile's last exit clean before launch. |
| 5 | In the web build, the first click on Send after typing was lost, and Enter as the extension sends it did not send. | W1 to W5, every probe; a second click always sent. Not yet tried by hand, so it may be the extension's synthetic events. | The composer's Send and its `SingleActivator(LogicalKeyboardKey.enter)` (`lib/ui/chat/composer.dart`), on Flutter web. |
| 6 | Muse: Done failed twice after taking control, and the chat then refused messages until it could be "verified". Its scratch side chats also dropped out of the side chat list after a reload. | W4, 21:13-21:16 CEST; Muse's service was degraded until about 21:24. | Muse's, recorded only to read its W4 and W7 rows. |

## Shortlist

1. Bug 1, upstream in AnythingLLM. Every per-chat feature of the browser, the sandbox and any indicator depends on it.
1. Bug 2 and CORS on :8445 (item 1 of `muse-parity-server.md`), so that every client shows a card at once.
1. G3 and bug 3: say what the browser is doing in the status line and on the card.
1. G4 in the app: a Browser chip in the running answer that becomes the card.
1. G7 and bug 4: quicker handoff on a bot check, a site name on the card, no restore bubble.
1. G5 in the app: watch the card large beside the chat.
1. G8: a take-over view that works on a phone.

## Scratch chats left in place

- Muse side chats: W1 (`42ded5b4-cc75-4bdd-b519-5563ebf739a0`), W2 (`0669ac60-e80a-402c-8e9e-9ff1d3dcf98e`), W3 and W4 (`ad7c5d6a-009b-4afb-93fa-f278e990d136`, locked), W5 (`1539e049-e8f5-4e33-bf7b-a03cd6c410d4`).
- AnythingLLM: the `parity-scratch` workspace with six `[Scratch test]` chats, and its browser profile on owen.
