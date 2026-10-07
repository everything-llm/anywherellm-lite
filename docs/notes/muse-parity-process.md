# Muse parity testing: how it was run

How the Muse versus AnythingLLM comparison of 2026-10-07 was run, so it can be repeated. The findings are in `docs/muse-parity.md` in the everythingllm repository on owen (`diot@192.168.0.29:/home/diot/dev/everythingllm`). The run used Claude Code with the Claude in Chrome extension driving the user's own Chrome, with both sites already signed in, plus read-only SSH to owen.

## Ground rules

Agree on these with the user before the first probe.

- **Where chats go:** new threads in AnythingLLM's "AnythingLLM" workspace (slug `algorithms`) and new Muse side chats. Never post in existing threads or Muse's main chat.
- **Prefix:** every prompt starts with `[Scratch test]`, which makes the threads easy to find and delete, and tells both agents it is a test.
- **Allowed effects:** one scheduled reminder and one artifact per tool, each deleted afterwards.
- **Never:** sending, posting, buying, connecting accounts, OAuth grants, or entering credentials. Stop and ask if an agent asks for one.
- **Owen:** read-only. No `hostctl deploy`, `units` or restarts; leave `research-runner` and `agents-runner` alone while a run is going.
- **Quota:** Muse's free plan has a weekly limit (Settings > General > Usage). Note the figure before starting; one full run of 11 probes cost a visible share of it.

## Probe set

Send each prompt, word for word, to a fresh Muse side chat and a fresh AnythingLLM thread. Run the two tools in parallel tabs.

| Probe | Prompt | What it measures |
| --- | --- | --- |
| Tools | `[Scratch test] Without taking any actions: list every tool, connector and capability you have, grouped by category (research, browsing, code, files, media generation, scheduling, memory, messaging, purchases, artifacts). For each, say in one line what it does and any limits.` | Tool inventory; in AnythingLLM, whether the reranker hides installed tools |
| News | `[Scratch test] What were the three biggest tech news stories of the past 48 hours? Cite each with a source link and its publication date.` | Search, citations, wall-clock time |
| Code | `[Scratch test] Run code to simulate 10,000 rolls of two six-sided dice with seed 42, plot the distribution of the sums as a bar chart, and show me the chart plus a table of exact counts.` | Sandbox, inline charts, unprompted publishing |
| Artifact | `[Scratch test] Build me a small interactive web page artifact: a Pomodoro timer with start, pause and reset, 25/5 minute cycles. Keep it private, don't share or publish it anywhere.` | Interactive artifacts, private hosting |
| Reminder | `[Scratch test] Schedule a one-off reminder for tomorrow at 09:00 Stockholm time with the text 'scratch test reminder - delete me'. It's only a test; I'll ask you to delete it right after.` (AnythingLLM also needs `You have my OK to create it.`) Follow with a request to delete it. | One-off scheduling, time zones, delete support |
| Image | `[Scratch test] Generate an image: a red fox reading a newspaper in a Stockholm cafe, watercolor style. Then describe in one line what you made.` | Image generation |
| Browser | `[Scratch test] Use your live browser (not search) to open https://news.ycombinator.com, then open the comments page of the current #1 story, and tell me its title, points, and the gist of the top comment. Read only: don't log in, vote or post.` | Live browser, cards |
| Memory | `[Scratch test] Without saving anything new: how is your memory organised (files, categories, how you decide what to save, how I can view, edit or delete it)? Give the category names and how many facts are in each, not the facts themselves.` | Memory model and management |
| Deep research | `[Scratch test] Please run a quick deep research: compare self-hosted SearXNG, Brave Search API and Tavily as the web-search backend for a personal AI agent in 2026, on cost, result quality, rate limits and privacy. A short cited report is enough.` | Long jobs, post-back to the chat |
| File | Attach `scratch-expenses.csv` (below), then `[Scratch test] This is fake test data. Summarise September spending by category, flag the biggest single expense, and suggest one budget cut.` | Upload handling, arithmetic |
| Multi-step | `[Scratch test] Plan this coming Saturday in Stockholm for me: check the forecast, check my calendar for conflicts, find two things to do that fit the weather, and give me a timed itinerary. Don't book, send or create anything.` | Connectors (calendar), planning, memory of the home city |

The CSV is fake: 45 rows of `date,category,amount_sek` for September 2026, made with `random.seed(7)` over five categories plus one 9800 SEK rent row. The right totals are rent 9800.00, groceries 5768.09, restaurants 5600.45, utilities 4649.33, transport 3022.41, total 28840.28. Regenerate it and check the totals before comparing answers.

Before the probes, map Muse's surface without changing anything: the left rail (Chat, Search, Feed, Ideas, Goals, Library), the side panel tabs (Activity, Approvals, Upcoming, Identity), and Settings (Connectors, Wallet, Secure store, Permissions, Messaging channels, Devices). In AnythingLLM, read Settings > Agent Skills and Settings > Scheduled Jobs.

## Driving the two sites

### Muse

- **New side chat:** the "New side chat" button, found with `find`. The message box sits near the bottom center; click it, type, press Enter.
- **Slow loads:** a page shows skeletons for 10-15 s after a navigation. Wait before reading it.
- **Permission denied:** once an artifact or live-browser preview is on the page, screenshots and `get_page_text` fail with "Permission denied", because those render in opaque-origin iframes. Navigating the tab to the same thread URL clears it until the next preview.
- **Reading replies:** `get_page_text` or `document.querySelector('main').innerText` both work. The side panel's Activity list gives each task's outcome and time, which helps with timing.
- **Library:** artifacts open in an iframe the extension cannot read. The library's "More options" menu did not respond to automation; asking Muse in the artifact's own side chat to delete it worked.

### AnythingLLM

- **New thread:** the sidebar's "New Thread" button. The sidebar scrolls as threads are added, so a click by coordinates can land on the workspace's default chat (`*New Thread`) instead. Re-run `find` before each click, and check that the URL changed to `/workspace/algorithms/t/<id>`.
- **Reading replies:** `get_page_text` hides the user's prompt and card images while the agent runs; the footer (`glm-5.3-flash · 43.2s ...`) appears when it ends. That footer time counts only the last generation, so note wall-clock time yourself.
- **Confirm dialogs:** deleting a scheduled job calls `window.confirm`, which freezes the extension. Override it first with `window.confirm = () => true` in `javascript_tool`, then click.
- **Attachments:** use `file_upload` on the hidden file input found with `find`; it accepts files from the session's scratchpad.

## Evidence on owen

All read-only.

| What | How |
| --- | --- |
| Agent tool calls and the tool list the reranker kept | `journalctl --user -u anythingllm --since -5min` |
| Research runs | `journalctl --user -u research-runner`, run ids `dr-...` |
| Scheduled jobs and their runs, memories, skill config | SQLite opened read-only from Python: `sqlite3.connect("file:/srv/anythingllm/storage/anythingllm.db?mode=ro", uri=True)`; tables `scheduled_jobs`, `scheduled_job_runs`, `memories`, `system_settings`. owen has no `sqlite3` binary |
| Pages and files the agent wrote | `~/.local/share/everythingllm/sandbox/public/<workspace>/` and `.../workspaces/<workspace>/project/` |
| Health | `uv run hostctl health` in the repo |
| Container time zone | `podman exec systemd-anythingllm date` (the container is `systemd-anythingllm`; it runs in UTC) |

`system_settings` holds connector API keys. Read them only inside a script that uses them, never print them.

To test a Google Apps Script bridge without AnythingLLM, POST `{"key": ..., "action": "version"}` to `https://script.google.com/macros/s/<deploymentId>/exec` from a script that reads the key from `system_settings`. Google's HTML "Access Denied" page means the deployment's access is not "Anyone" or the project is gone; a JSON `Unauthorized` means the key is wrong.

## Cleanup

1. Delete each tool's test reminder: Muse in its chat; AnythingLLM in Settings > Scheduled Jobs, since its agent has no delete tool.
1. Delete Muse's artifact through its side chat.
1. Remove what AnythingLLM wrote under `sandbox/public/algorithms/` and `workspaces/algorithms/project/`. Look at the files before removing them.
1. Decide with the user about the deep-research entry on the research site (`delete-entry`).
1. Leave the scratch threads and side chats for the user, and list them in the report.
1. Close the browser tabs the session opened.

## Writing up

The report has four parts: a probe table (both tools side by side, with timings), what Muse does well, a gap table (Muse feature, AnythingLLM status, closest repo piece, build, size S/M/L), and a numbered bug table with evidence and where to look. It goes in the everythingllm repo's `docs/`, linted with the `mdlint` skill, and left uncommitted. Leave personal data seen in Muse's main chat and memory out of it.
