# In-chat browser UX comparison: how it is run

How the 2026-10-07 comparison of AnywhereLLM's in-chat browser with Muse's live browser was run, so it can be repeated. It continues `docs/notes/muse-parity-process.md` and narrows it to the browser: the same two tools side by side, with probes and measures for watching, steering and handing over a browser rather than for answers.

The run used Claude Code with the Claude in Chrome extension driving the user's own Chrome, with Muse and AnythingLLM already signed in, plus read-only SSH to owen (`diot@192.168.0.29`).

## Ground rules

Agree on these with the user before the first probe.

- **Where chats go:** new chats in a scratch workspace, `parity-scratch`, and new Muse side chats. Never post in existing chats or Muse's main chat. A workspace has a browser of its own, so `parity-scratch` holds none of the user's logins. Create it if it is gone: a new workspace takes the server's default system prompt (the EverythingLLM block) and opens in Agent mode.
- **Prefix:** every prompt starts with `[Scratch test]`.
- **Allowed effects:** the agent handing the browser over and taking it back, filling a test form without submitting it, and a login request card, which is opened, filled with nothing and declined with Not now.
- **Never:** sending, posting, buying, signing in, entering any credential, or solving a CAPTCHA or bot check. When an agent hands over for one, hand the browser back untouched.
- **Saved logins:** read Muse's Settings > Secure store first and keep every probe off the sites listed there, so that Muse cannot sign in with a stored login. On 2026-10-07 that ruled out github.com.
- **Owen:** read-only. No `hostctl deploy`, restarts or `browser-reset`.
- **Quota:** note Muse's weekly figure (Settings > General > Usage) before starting. The run below started at 26%.

## Set-up

1. Build and serve the app: `flutter build web`, then `python3 -m http.server 8765 --bind 127.0.0.1 --directory build/web`. A browser page keeps its connection in local storage per origin, so the same port finds the saved connection.
1. Check the card host from a shell: `curl -s -D - -o /dev/null -H 'Origin: http://localhost:8765' https://<server>:8445/_live/browser/<id>.jpg`. Without `Access-Control-Allow-Origin`, the web build draws every card as its description, and the card's look has to be read in AnythingLLM's own UI, where an `<img>` needs no CORS.
1. Open four tabs: Muse, the web build, AnythingLLM's UI, and later the take-over view that a card opens.

## Probe set

Send each prompt word for word to a fresh Muse side chat and a fresh chat in `parity-scratch`, in parallel tabs. W4 follows W3 in the same chats, and W6 reuses the W2 chats.

| Probe | Prompt | What it measures |
| --- | --- | --- |
| W1 Read | `[Scratch test] Use your live browser (not search) to open https://news.ycombinator.com, then open the comments page of the current #1 story, and tell me its title, points, and the gist of the top comment. Read only: don't log in, vote or post.` | Time until the browser can first be seen; what shows while it works |
| W2 Navigate | `[Scratch test] Use your live browser (not search) to go to https://en.wikipedia.org, search there for "Stockholm Metro", open the article, and tell me the year the first line opened. Then list the pages you went through, in order. Read only.` | Whether each step can be followed; whether a second chat gets a card of its own |
| W3 Fill | `[Scratch test] Use your live browser to open https://httpbin.org/forms/post and fill in the form with made-up values: customer name "Scratch Test", telephone "000", email "scratch@example.com", size Medium, topping Cheese, comments "scratch test - do not submit". Do NOT submit the form. Tell me when it's filled.` | Whether actions show as they happen; what the status line says |
| W4 Handoff | `[Scratch test] Hand me the browser so I can check the form myself. I'll tell you when I'm done.` Take over, scroll, hand back, then `[Scratch test] I'm done. Take the browser back and read me what's in the delivery instructions field.` | Clicks to take over and hand back; how clear it is who has the browser |
| W5 Login wall | `[Scratch test] Use your live browser to open https://news.ycombinator.com/login. Don't sign in yourself. If a login would be needed, ask me for one the safe way your tools provide, never in the chat.` | The login request card and its form; Muse's equivalent |
| W6 Return | After the browser has stopped (20 minutes unused and unwatched), reload the W2 chat and send `[Scratch test] What page is your browser on right now?` | What a stopped browser looks like, and whether the card or its link goes stale |
| W7 Narrow | Resize the window to its narrowest (`resize_window`; Chrome stops at 500 px) and load the chat, the take-over view and the login form in the active tab | Use at phone width |

A site behind a bot check (gitlab.com's sign-in page sits behind Cloudflare) makes W5 a handoff for the check instead of a login request. Keep W5 on a site without one.

Record for each probe:

| Measure | How |
| --- | --- |
| Wall-clock time | `new Date().toISOString()` in the page right after sending, and again when the answer ends. The app's footer time counts only the last generation |
| Time to first sight | When anything of the browser (a card, a thumbnail, a status naming the browser) first shows in the chat |
| Visible while working | What the chat shows during the run: status lines, cards, interim messages |
| Who has it | What the chat, the card and the view say about who controls the browser, before and after the answer ends |
| Clicks | Clicks from the chat to watching, to taking over, and to handing back |
| Failures | Error toasts, lost messages, stale states |

## Driving the surfaces

### Muse

- **New side chat:** the `+` beside "Side chats". `find` returns a "New side chat" button that does nothing in the main chat; click the `+` by coordinates instead and check that the URL becomes `/thread/new`.
- **Preview:** "Open preview" on a Browser card opens a pane beside the chat. "Take control of the browser" in its header gives it to you; the header then reads "You're in control" with Stop and Done. `find` reaches Done as "Hand browser control back to the assistant".
- **Status:** the agent's current step shows under its avatar ("Browsing site", "Filling form") and in the side panel. The side panel's Activity list names each browser task with its outcome.
- **When it breaks:** "Message failed to send", "Something went wrong" and "Conversation controls unavailable" mean Muse's service is degraded. Do not retry in a loop: run the app's side, and come back to Muse later.

### AnywhereLLM's web build

- **Sending:** click Send. Enter, as the extension sends it, did not send, and the first click on Send after typing was often lost; click again and check that "Answering..." shows.
- **New chat:** "New chat" under the workspace in the sidebar.
- **Cards:** a card link opens the take-over view in a new tab. Close every take-over view and every page showing a live card before W6: a watched browser is never stopped as idle.

### Background tabs

Screenshots of a tab that is not in front come back stale. For W7, load each surface in turn in the one narrow tab.

## Evidence on owen

All read-only.

| What | How |
| --- | --- |
| Browser container | `podman ps --format '{{.Names}} {{.Status}}' \| grep browser`, and `journalctl --user -u browser-runner` for starts and idle stops |
| Tool calls and their arguments | `journalctl --user -u anythingllm -o cat` around the probe, `@agent is attempting to call` |
| AnythingLLM's own code | `podman exec systemd-anythingllm sh -c "grep ... /app/server/utils/agents/ephemeral.js"` |

## Cleanup

1. Hand the browser back in every view that still says you have it. A Muse browser left in "You're in control" may refuse Done; note it for the user.
1. Decline any waiting login request with Not now.
1. Leave the scratch chats in both tools and list them in the report.
1. Leave `parity-scratch` and its browser profile for the user to remove: delete the workspace in the app, and wipe the profile with `uv run hostctl browser-reset parity-scratch` on owen.
1. Stop the local server, restore the window size and close the tabs the session opened.

## Writing up

The report has five parts: a probe table (both tools side by side, with times), how Muse does it, a gap table (Muse pattern, AnywhereLLM now, the piece we already have, build, where, size S/M/L), a numbered bug table with evidence, and a ranked shortlist. It goes in this repository's `docs/notes/`. Leave out anything seen in Muse's main chat, memory or Activity list that is not a scratch probe's. Lint both files with the `mdlint` skill.
