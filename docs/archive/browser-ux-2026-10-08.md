# The in-chat browser's widgets compared with Muse's

Run on 2026-10-08, 12:50-13:18 CEST, in the user's own Chrome through the Claude in Chrome extension, by the protocol in `docs/protocols/browser-parity-process.md` with its measures turned to the widgets. AnywhereLLM: commit `7c680c8`, `flutter build web`, served from `http://localhost:8765`, signed in to owen at `https://<server>:3001`, so answers went straight to `stream-chat`. Every AnywhereLLM chat ran in a `parity-scratch` workspace made afresh for the run, in Agent mode with the server's default prompt and `glm-5.3`, on a browser profile wiped with `hostctl browser-reset` before the first probe. Muse: muse.ai, each probe in a new side chat. W6, W7 and the width, theme, keyboard and saved-login probes were not run; the user stopped the run once the findings below were in.

## Verdict

Since the first run, everythingllm gives every chat its own browser tab and the app shows a Browser chip from the first step, so ours is now as quick to show that a browser is at work: the chip came at 8-12 s, Muse's card at 10-24 s. What ours lacks is the picture and the words. Muse's card has a live thumbnail from about 20 s and a status that changes in place (`Opening Wikipedia homepage`, `Working`, `Paused`, `Completed`), and the same card follows a handoff. Ours has no picture until the model pastes a card at the end of its answer, and in the web build never, because the tab's live card deliberately sends no CORS header. Once the answer ends, the panel's words stop following the browser: it says "The card says who has the browser" over a card that did not load, and still asks for a login the person has already declined. Control is now good on both sides: taking over and handing back took one click each in ours and in Muse's, and Muse's Done worked this time.

The model caused three of the worst moments, not the app: it answered a browsing question from memory and pasted a card with an invented title, pasted a tab's card as "the safe way" to give a login, and linked a login card to its own picture.

## Probe results

Times are wall-clock from send to the end of the answer, from the page clock. "First sight" is when anything of the browser first showed in the chat.

| Probe | Muse | AnywhereLLM |
| --- | --- | --- |
| W1 Read | 32 s. Avatar status `Browsing HN` at 8 s; card `Reading page` with thumbnail and Open browser by 24 s, above an interim message; then `Completed` with the task's title and Open preview. | 38 s. Chip `Browser · Opening news.ycombinator.com` and the header's Browser with a pulsing dot at 12 s. One click on the chip opened the panel: steps, no picture. The card came last, as `[Browser: Hacker News: did not load]`. |
| W2 Navigate | 34 s. Card `Opening Wikipedia homepage` at 10 s, `Working` with a thumbnail at 21 s. | 30 s. Chip at 8 s; everythingllm's own step lines arrived (`Filling in Search Wikipedia`). The chat got its own tab and card (bug 1 of the first run no longer shows). |
| U2 Second task, same chat | 16-20 s. A new card for the new task, placed with its turn; the first stays with its own. | 16 s. No tool was called: the model answered from memory (11 lines; the article says 12) and pasted W2's tab card titled "Gothenburg tram network - Wikipedia". The panel then labelled W2's steps "The last answer's steps". |
| W3 Fill and submit | 50 s. Card `Opening form page` at 10 s, `Submitting the form` with a thumbnail at 21 s. | 95 s, eight steps (`Filling in Customer name:`, `Ticking Extra Cheese`, `Clicking Submit order`), one held for 25 s. Both read the echo right. |
| U3 Leave mid-run | Other chats stay usable; the running chat's row shows nothing until it ends, then sorts first. | The running chat's row shows nothing; every other chat's composer says "Another chat is still answering...". Coming back resumed the chip and all the steps. |
| W4 Handoff | 20 s, two messages, no new card: W3's card became `Completed · Form page ready for ...`. While its card was off screen, a bar pinned under the avatar showed the thumbnail, `Browser · Working` and a red Stop task. Open preview, a "Connecting to browser" placeholder for 3 s, then Take control: 2 clicks. The card turned `Paused`; Done worked first time. Follow-up under 10 s, and the preview's header took the new task's title. | 20 s; chip `Handing the browser to you`. Take over in the panel: 1 click to the take-over view, which said "You have the browser" with the agent's reason. Hand back: 1 click, then "The agent has the browser but isn't using it now". Follow-up 20 s, ending with `Used the browser · 1 step`. Nothing in the app said the browser was waiting for the person. |
| W5 Login wall | 30 s; judged no login was needed. Asked again, a compact Secure Store card with Add, which opens a modal with the site filled in. Cancel leaves the card as it was. | 18 s. The model listed the saved logins, then pasted the tab's card as "the safe way to hand me one", which opens the take-over view. Asked again, the login card at 20 s, drawn inline and in the panel with Open the login form. After Not now the card turned red, `declined`, within 10 s, but the panel still said "The agent is asking you for a login." |
| U4 Stop mid-browse | Finished five pages in 33 s, before Stop could be pressed. Stop sits in the composer while a task runs. | Stopped after four steps; the chip became `Used the browser · 4 steps` and the answer shows no mark that it was stopped. The agent called `browse` once more, 6 s after Stop. |
| U8 Saved login (partial) | Not run: its Secure store would not load ("Unable to load saved credentials"). | 62 s to a login card for the practice site, after 30 s on one unchanged step while the page timed out. The model linked the card to its own picture (bug 3). The login was declined; the sign-in was not run. |

## How Muse does it

| Widget | What it does |
| --- | --- |
| Browser card | One card per browser task, placed with the turn that started it: a globe (green once done), `Browser`, then status and task title (`Completed · Fetch HN #1 story de...`), a live thumbnail, and one button that reads Open browser while the task runs and Open preview after. A handoff or a follow-up changes the same card. |
| Avatar status | A pill under the avatar with an icon and the step in a few words (`Browsing HN`, `Extracting details`, `Opening form`, `Muse is working`). |
| Pinned bar | While the card is scrolled away and the task runs: thumbnail, `Browser · Working`, red Stop task. |
| Preview | Two thirds of the window, the chat narrowed beside it: task title, `Completed · httpbin.org`, Take control of the browser, a tab strip, then a real browser frame with its address bar. A placeholder with a spinner while it connects. In control: "You're in control", Done, close. |
| Interim message | The agent answers at once ("On it -- opening the form...") and posts the result as a second message. |
| Credentials | A compact Secure Store card with Add; the modal has the site filled in, the password hidden behind a toggle, and a save switch. |
| Side chats | Named from the task ("Submit httpbin form test"), with an unread dot when one finished elsewhere. |

## Gaps

App first. Size is S (under a day), M (days), L (a week or more).

| # | Muse has | AnywhereLLM now | What we already have | Build | Where | Size |
| --- | --- | --- | --- | --- | --- | --- |
| G1 | A thumbnail from about 20 s into a task | No picture until the model pastes a card at the end, if it does | `CardImage` follows a live card; everythingllm already keys a tab by chat; `browserCard` finds a chat's earlier card | A card address the app can build from the workspace and the chat, such as `/_live/browser/chat/<workspace>/<thread>.jpg` redirecting to the tab's card; the app draws it in the chip and the panel from the first step | everythingllm, app | S, S |
| G2 | The status in words, changed in place, after the task too | The chip's words stop with the answer; after it, the panel's `about` line points at the card's picture | `Runner.state` knows who holds the browser and whether it is busy; the login form knows waiting, saved and declined | A small JSON state beside each card (holder, busy, page title, address; for a login: waiting, saved, declined) that the panel and chip read while shown, and that sets the panel's line and buttons | everythingllm, app | S, S-M |
| G3 | A pinned bar with the picture and Stop while the card is out of view | The header's Browser with a pulsing dot | `_BrowserButton`, `BrowserStateBuilder`, the composer's Stop | While the running answer's chip is scrolled away: a bar under the header with the step, Stop and a tap to the panel; with G1, the picture | app | S |
| G4 | Task titles that tell steps apart | `Opening news.ycombinator.com` twice for two pages; `Filling in Customer name:` | `browserStep` (`lib/core/browser.dart`) has the address | Add the path when the host repeats; drop a trailing colon from an element's name; show a step's seconds once it has run 10 s | app | S |
| G5 | A live card in a web client | The tab's card is never drawn in the web build | `chatimage.live.push(cors=...)`; the relay checks the developer key with `/api/v1/auth` | Send `Access-Control-Allow-Origin` on a tab's card only to a request that carries the developer key, and have `answerImage` send it to the card host. The key would then go to a second port of the same host | everythingllm, app | M, S |
| G6 | Other chats usable while one browses | Built on 2026-10-08: a chat of another workspace takes a message while one answers; a chat of the same workspace waits, since its agent runs share one browser tab until AnythingLLM's `ephemeral.js` sends `thread_id` (bug 1 of the first run) | The relay runs one answer per chat, not per app | `ChatController` holds a running answer per workspace, at most 3 in a browser | app | L |
| G7 | A credentials modal over the chat | A separate form, clearer about whose site it is, with 2FA and "Ask me before each use" | `/login/<id>/` | Keep the form | -- | -- |

Ruled out for the web build: a CORS header on every tab card. everythingllm leaves it off on purpose, because a tab may be signed in somewhere and any page that learned the card's address could read its screenshots (`packages/browser/src/browser/live.py`).

## Bugs

| # | Bug | Evidence | Where to look |
| --- | --- | --- | --- |
| 1 | The panel labels an older answer's steps "The last answer's steps". | U2: the newest answer took no steps, and the panel showed W2's three under that heading. `used` is the newest turn with steps, not the newest answer. | `BrowserPanel._build` (`lib/ui/chat/browser_panel.dart`): say which answer, or show steps only for the newest. |
| 2 | The panel's words do not follow the browser after the answer ends. | W1 to W4: "The card says who has the browser." over `[... did not load]`. W5: "The agent is asking you for a login." and Open the login form after the card itself turned `declined`. | `BrowserPanel` `about`; fixed for good by G2. Until then, word it by what the app knows and say nothing about a card that did not load. |
| 3 | A login card linked to its own picture is not seen as the browser's. | U8: `[![Log in to ...](.../login/lr-1822....png)](.../login/lr-1822....png)`. The answer kept its step chip, the panel showed no login card, and a tap would open the PNG, not the form. | `browserCards` (`lib/core/browser.dart`): when a card's link is its own image, take the page as the image's address without `.png` or `.jpg`. |
| 4 | A stopped answer looks finished. | U4: after Stop, only Copy, Retry and the step chip. `Turn.stopped` is set but never drawn. | `message_list.dart`, beside the `error` boxes: a quiet "Stopped" line. |
| 5 | Half a card's Markdown shows while it streams. | W5 follow-up: `Card: [![Log` as text for a moment before the card drew. | `answer_body.dart` while `turn.streaming`: hold back an unclosed `[![` at the end of the text. |
| 6 | The agent keeps going after Stop on a direct answer. | U4: Stop at 13:14:07; `browse` called at 13:14:13 (`journalctl --user -u anythingllm`). | AnythingLLM's `stream-chat` does not abort the agent when the client goes. Through the relay, Stop posts a cancel. |
| 7 | The take-over view shows every chat's tab. | W4: the view's Chromium tab strip had W1's, W2's and W3's tabs, so taking over one chat lets the person switch to another's. | everythingllm's take-over view: show only the chat's tab, or one window per chat. |
| 8 | The model pastes cards it did not get from a tool. | U2: no tool call (`attempting to call` count 0) and a card with an invented title. W5: a tab's card offered as the way to give a login, though its reasoning said to call `browser-login` with `ask`. | everythingllm's default prompt: a card comes only from a tool's reply, unchanged, and a login is asked for only with `browser-login` `ask`. |

The first run's bugs: 1, one tab per workspace, no longer shows, though AnythingLLM's `ephemeral.js` still sends no `thread_id`; 2, the late first frame, could not be judged without a drawn tab card; 3, "browsing" after the agent finished, is fixed, since the view now says "isn't using it now"; 4, Chromium's restore bubble, did not show on a fresh profile; 5 was the harness (see the process note); 6, Muse's failed Done, did not recur.

## Visual quirks

| Where | Quirk |
| --- | --- |
| Sidebar | Every chat is named from its first words, so seven scratch chats read `[Scratch test] Use your live brow...`. Muse names a chat from its task. |
| Answer | A card that did not load reads `[Browser: Hacker News: did not load]`, brackets and all, beside a link icon. |
| Panel | Open the login form and Take over are both primary buttons of the same weight. |
| Panel | On a new chat the panel stays open saying "The agent has not shown this chat's browser yet.", and the header has no Browser button, so only its close button hides it. |
| Steps | An element's name keeps its label's colon: `Filling in Telephone:`. |
| Footer | `glm-5.3 · 26.0 s` against 38 s on the clock, since it counts only the last generation. |

## Shortlist

1. G1 and bug 3: a card the app can find from the first step, and lenient card links. This brings the picture into the chip and panel on Linux and Android.
1. G2 and bug 2: state in words in the panel and chip, after the answer too.
1. Bugs 1, 4 and 5 and G4: small fixes to the panel, a stopped answer, streaming cards and step names, all in the app.
1. G3: the pinned bar with Stop.
1. Bug 8: the prompt rule on cards, in everythingllm.
1. Bug 7: one chat's tab in its take-over view.
1. G5: tab cards in the web build, behind the developer key.
1. G6: answers in more than one chat of a workspace at once, once AnythingLLM keys an agent run's browser by chat.

## Scratch chats left in place

- Muse side chats: W1 (`53aa31a6-f488-4512-a0a0-1022a8bfcbb0`), W2 and U2 (`39ed6150-f5ec-427c-926c-aeab50d3feee`), W3 and W4 (`d609ed89-b7ab-4957-a0f0-29e75bae2a34`), W5 (`695fe243-e3a2-4725-83f6-5ad1707996f9`), U4 (`0a593ebc-bffb-4ca5-9c93-97fdb7709ddb`). Nothing was saved in Muse's Secure store.
- AnythingLLM: the `parity-scratch` workspace with seven `[Scratch test]` chats (threads 120-126), and its browser profile on owen. Both login requests were declined; no login was saved.
- GIFs of each probe in `~/Downloads` (`w1-read-app.gif` to `u4-stop-muse.gif`).
