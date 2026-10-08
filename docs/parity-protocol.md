# Feature-parity test: AnywhereLLM in Chrome against another chat app

A runbook for an agent driving the user's own Chrome with the Claude in Chrome extension. It compares AnywhereLLM's web build with a reference app (Muse at muse.ai when this was written) by sending the same prompts to fresh scratch chats on both, and ends in a findings file at `docs/notes/<reference>-parity.md`.

## Ground rules

Agree these with the user before the first probe.

| Rule | Detail |
| --- | --- |
| Where chats go | New chats in a `parity-scratch` AnythingLLM workspace, and new side chats (or the reference app's equivalent). Never a main chat, a channel, or an existing thread. |
| Prefix | Every prompt starts with `[Scratch test]`. |
| Allowed effects | One test reminder, one artifact and one research run per side. Nothing is deleted by the agent; cleanup lists them for the user. |
| Never | Sending, posting, buying, connecting accounts, OAuth grants, approving an approval request, invites, settings changes, or typing a password, key or token. Stop and ask if an agent asks for one. |
| Sign-in | The user signs in to AnywhereLLM themselves. |
| Quota | Read the reference app's usage meter before and after. One full run cost Muse's free plan about 2% of a week. |
| Personal data | The reference app's main chat, memory and identity pages hold the user's data. Read only scratch chats, and keep personal data out of the findings. |

## Setup

1. Build and serve the app, each in the background:

   ```sh
   flutter build web
   python3 -m http.server 8765 --bind 127.0.0.1 -d build/web
   ```

1. Open AnywhereLLM and the reference app in **two separate Chrome windows**, side by side. Flutter does not paint a hidden tab, so with both in one window the hidden one shows stale buttons, swallows the first click, and seems not to stream.

1. Ask the user to sign in at `http://localhost:8765`, and wait for their answer.

1. Check that the AnywhereLLM window is visible: `document.visibilityState` must be `visible`. In a minimised or covered window Chrome runs no animation frames, so Flutter paints only when a screenshot forces a frame: fade-ins look stuck and clicks after a layout change can be lost. Ask the user to bring the window forward.

1. Before opening the reference app's activity or history panels, close them: they may list the outcomes of an earlier run of these probes. Read them only after this run's own probes.

1. In AnywhereLLM, create the `parity-scratch` workspace with the sidebar's +. A new workspace gets the server's default prompt, so copy the prompt of the workspace the user names (Files > workspaces > `<name>` > `PROMPT.md`) into `parity-scratch`'s `PROMPT.md` with the value-setting snippet below, save, and confirm the two `settings.json` files match (Edit as JSON). Set Agent mode in Sources.

1. Turn on Flutter's semantics tree once per page load, so controls get labelled refs for `find`. If a click on the composer then leaves `document.activeElement` on `FLUTTER-VIEW`, reload and drive by coordinates instead:

   ```js
   document.querySelector('flt-semantics-placeholder')?.click()
   ```

1. Start the extension's network log (`read_network_requests` with `clear: true`) before the first probe; it records nothing from before its first call.

1. Make the probe files in the scratchpad and keep their answers:

   ```sh
   uv run --quiet python - <<'EOF'
   import csv, random, struct, zlib
   random.seed(7)
   cats = {"groceries": (80, 450), "restaurants": (120, 600), "utilities": (300, 1200), "transport": (30, 400)}
   rows = [("2026-09-01", "rent", 9800.00)]
   for _ in range(44):
       c = random.choice(list(cats)); lo, hi = cats[c]
       rows.append((f"2026-09-{random.randint(1, 30):02d}", c, round(random.uniform(lo, hi), 2)))
   rows.sort()
   with open("scratch-expenses.csv", "w", newline="") as f:
       w = csv.writer(f); w.writerow(["date", "category", "amount_sek"]); w.writerows(rows)
   tot = {}
   for _, c, a in rows: tot[c] = round(tot.get(c, 0) + a, 2)
   print(tot, round(sum(tot.values()), 2))
   raw = b"".join(b"\x00" + bytes([0, 128, 128]) * 64 for _ in range(64))
   chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
   open("teal.png", "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
   EOF
   ```

   The right answers are rent 9800.00, utilities 8059.08, restaurants 3196.05, groceries 2895.07, transport 2523.36, total 26473.56; the biggest single expense is rent; `teal.png` is `#008080`.

## Driving AnywhereLLM

| Task | How |
| --- | --- |
| New chat | Click the sidebar's "New chat" under `parity-scratch`, then zoom on the header and confirm it reads "parity-scratch / New chat" before typing. The sidebar scrolls as chats are added, so re-find the button each time. A reload reopens the last chat, and a query in the sidebar search hides New chat; clear it with its x after C6. |
| Type | Click the composer, `type` one character, then the rest. The first keystroke after a field opens can be lost. Check a field's text with `document.activeElement.value`. |
| Send | Take a screenshot first, so the window has painted, then click the `Send` ref from `find`. Enter from automation does not send. |
| Set a long text field | Focus the field, then run the snippet below. Ctrl+C in a Flutter field does not reach the system clipboard under automation. |
| Attach a file | Run the file hook below with the file's bytes, then click the paperclip. Flutter's picker cannot be driven otherwise. |
| Read an answer | Answer text is not in the semantics tree. Read short answers from a `zoom`; read long ones from Files > workspaces > `parity-scratch` > chats, after the answer ends. |
| Timing | The answer's footer gives the model's time; note wall-clock time yourself as well. |

Set the focused Flutter text field to `text`:

```js
const t = document.activeElement;
t.value = text;
t.selectionStart = t.selectionEnd = t.value.length;
t.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertText'}));
```

Hand the next file picker a file instead of opening it (`b64` is the file in base64, from `base64 -w0 <file>`):

```js
if (!window.__hooked) {
  const orig = HTMLInputElement.prototype.click;
  HTMLInputElement.prototype.click = function () {
    if (this.type === 'file' && window.__pending) {
      const dt = new DataTransfer();
      for (const f of window.__pending) dt.items.add(f);
      this.files = dt.files;
      window.__pending = null;
      setTimeout(() => this.dispatchEvent(new Event('change', {bubbles: true})), 50);
      return;
    }
    return orig.call(this);
  };
  window.__hooked = true;
}
const bin = atob(b64);
window.__pending = [new File([Uint8Array.from(bin, c => c.charCodeAt(0))], name, {type})];
```

## Driving Muse

| Task | How |
| --- | --- |
| New side chat | The + beside "Side chats" (`find` "New side chat"). Pages show skeletons for 10-15 s after a navigation. |
| Send | Click the message box, `type`, press Enter. |
| Attach a file | `file_upload` on the hidden `input[type=file]` found with `find`. |
| Read an answer | `document.body.innerText` from the last occurrence of the prompt onward, in `javascript_tool`. Never `get_page_text`: it returns the main chat too. |
| Open Settings | Ctrl+, (the menu item did not respond to a click). |
| Preview iframes | Artifact and live-browser previews render in opaque iframes; reload the thread URL if screenshots fail. |

## Probes

Send each prompt word for word to both sides, each in a fresh chat unless the probe builds on the last. Alternate which side goes first. Run one side at a time when timings matter; running both at once is faster but makes the slower app's timing coarse.

Client probes measure the app:

| # | Prompt or action | Look for |
| --- | --- | --- |
| C1 | `[Scratch test] Reply with a heading, a 3-row table, a bullet list, a short Python code block and the quadratic formula in LaTeX.` | Tables, code highlighting and copy, math rendering |
| C2 | `[Scratch test] Write about 1500 words on the history of paper.` Press Stop after about 5 s of text. | Streaming, Stop, the partial answer, a stopped marker, the chat's title |
| C3 | In C2's chat: `[Scratch test] Summarise your previous answer in one sentence.` Then Edit it and send, then Retry the last answer. Reload the page and reopen the chat. | Context, Edit and Retry, and whether the server kept what the screen dropped |
| C4 | Attach `teal.png`: `[Scratch test] What colour is this image?` | Attachment preview before and after sending, vision |
| C5 | Hover a finished answer and a sent message; open each menu. | Every per-message action |
| C6 | Search for a word that is only in C2's answer, such as `Gutenberg` or `Cai Lun`. | Full-text against title-only search |
| C7 | Note any quirk seen along the way: field sizes, tooltips, scrolling, fonts, tables. | Visual quirks |

Agent probes measure what a person gets through each app:

| # | Prompt | Look for |
| --- | --- | --- |
| A1 | `[Scratch test] Without taking any actions: list every tool, connector and capability you have, grouped by category (research, browsing, code, files, media generation, scheduling, memory, messaging, purchases, artifacts). For each, say in one line what it does and any limits.` | Tool inventory |
| A2 | `[Scratch test] What were the three biggest tech news stories of the past 48 hours? Cite each with a source link and its publication date.` | Status lines, citations |
| A3 | `[Scratch test] Run code to simulate 10,000 rolls of two six-sided dice with seed 42, plot the distribution of the sums as a bar chart, and show me the chart plus a table of exact counts.` | Inline chart, generated files; check the counts against numpy below |
| A4 | `[Scratch test] Build me a small interactive web page artifact: a Pomodoro timer with start, pause and reset, 25/5 minute cycles. Keep it private, don't share or publish it anywhere.` | How a made page is shown and opened |
| A5 | `[Scratch test] Schedule a one-off reminder for tomorrow at 09:00 Stockholm time with the text 'scratch test reminder - delete me'. It's only a test.` Add `You have my OK to create it.` only if asked. | Scheduling, where the job can be seen |
| A6 | `[Scratch test] Generate an image: a red fox reading a newspaper in a Stockholm cafe, watercolor style. Then describe in one line what you made.` | Image output |
| A7 | `[Scratch test] Use your live browser (not search) to open https://news.ycombinator.com, then open the comments page of the current #1 story, and tell me its title, points, and the gist of the top comment. Read only: don't log in, vote or post.` | Live browser, live cards; both sides should agree |
| A8 | `[Scratch test] Without saving anything new: how is your memory organised (files, categories, how you decide what to save, how I can view, edit or delete it)? Give the category names and how many facts are in each, not the facts themselves.` | Memory model and its view |
| A9 | `[Scratch test] Please run a quick deep research: compare self-hosted SearXNG, Brave Search API and Tavily as the web-search backend for a personal AI agent in 2026, on cost, result quality, rate limits and privacy. A short cited report is enough.` | Long jobs and how the result comes back |
| A10 | Attach `scratch-expenses.csv`: `[Scratch test] This is fake test data. Summarise September spending by category, flag the biggest single expense, and suggest one budget cut.` | Document upload, arithmetic against the totals above |
| A11 | `[Scratch test] Plan this coming Saturday in Stockholm for me: check the forecast, check my calendar for conflicts, find two things to do that fit the weather, and give me a timed itinerary. Don't book, send or create anything.` | Connectors, planning |

Seed 42 has two valid answers for A3, depending on whether the dice are drawn together or in turn:

```sh
uv run --quiet --with numpy python -c "
import numpy as np, collections as c
g = np.random.default_rng(42); print(sorted(c.Counter(g.integers(1, 7, (10000, 2)).sum(1).tolist()).items()))
g = np.random.default_rng(42); a = g.integers(1, 7, 10000); b = g.integers(1, 7, 10000); print(sorted(c.Counter((a + b).tolist()).items()))"
```

## Recording

Write each probe's raw observations to a scratchpad log as it runs, before any verdict: time sent, time ended, what showed on each side, and the screenshot path. Tag every finding with its owner:

| Tag | Meaning |
| --- | --- |
| app | AnywhereLLM's own code; give the file and function to look at. |
| server | AnythingLLM, the everythingllm host or the model; the app sent the right thing. |
| harness | Caused by automation: hidden tabs, synthetic keys, the clipboard. Confirm by hand before reporting as a bug. |

For an image or card that shows as `[alt: host]`, read the network log for its status, then check the host's CORS from the shell:

```sh
curl -s -D - -o /dev/null -H 'Origin: http://localhost:8765' '<image url>' | grep -i 'HTTP\|access-control'
```

The extension's network log does not record streaming `fetch` calls; open DevTools for a stream that fails.

## Findings file

`docs/notes/<reference>-parity.md`, with these parts in order:

1. The run: date, time, AnywhereLLM commit, server address, model, workspace setup.
1. A verdict in a few sentences.
1. The probe table: each probe, both sides, with times.
1. What the reference app does well.
1. A gap table: the reference app's feature, AnywhereLLM now, the closest piece in the repo, what to build, size S/M/L.
1. A numbered bug table: what happens, evidence, where to look.
1. A visual-quirks table.
1. The process: what worked, what went wrong, and the change it makes to this runbook. Make that change here too.
1. What was left on each server for the user to remove.

Run the `mdlint` skill over the file. Leave it uncommitted.

## Cleanup

1. Stop the http server and close the tabs and windows the run opened.
1. List for the user, without deleting: the `parity-scratch` workspace and its chats, the scratch side chats, each side's reminder, artifact and research run, and any sandbox files the agent wrote.
