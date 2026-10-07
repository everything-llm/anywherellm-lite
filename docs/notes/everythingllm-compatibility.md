# AnywhereLLM against the everythingllm repository

Findings from reading `BinaryBand/everythingllm` at commit d874127 (2026-10-07 10:42 +0200) against AnywhereLLM at commit 238c2e1. That repository calls this app Nilson. Nothing was run against a server.

## The relay matches the client

`packages/relay` (`app.py`, `runs.py`, `auth.py`, `upstream.py`, `store.py`) and its README section "Nilson relay" agree with `lib/adapters/anythingllm_client.dart` on every point the client uses.

| Point | Relay | Client |
| --- | --- | --- |
| Health | `GET /health` answers `{"ok": true, "service": "everythingllm", "features": ["runs"]}`, no key | `_isRelay` checks `service` and `runs` in `features`, sends no key, does not remember a 5xx |
| Mount | `/everythingllm/` on AnythingLLM's :3001, prefix stripped or not | `relayPath` is `/everythingllm` on the connection's address |
| Key | The caller's developer key, checked with `GET /api/v1/auth`; refused is 403 `No valid api key found.`, unreachable is 502 | Sends the same key; reads `error` from the body |
| Start | `POST /v1/runs` with `workspace`, `thread`, `clientId`, `body`; `body` needs a `message` or `reset: true`; 201 with the run, 200 for a `clientId` already used, 409 for a busy thread | Sends those four fields and a fresh `clientId` per message; reads `id` |
| Events | `GET /v1/runs/{id}/events`: `chunk` with each `stream-chat` chunk unchanged, then `done` `{}`, `failed` `{"error"}` or `cancelled` `{}`; ids from 1; `Last-Event-ID` resumes; `: ping` every 15 s | Reads `chunk` through `chatEventsOf`, ends on `done` or `cancelled`, fails on `failed` with its `error`, resumes with `Last-Event-ID`, gives up on 45 s of silence |
| Cancel | `POST /v1/runs/{id}/cancel`; a finished run is left as it is | `stopChat` posts it once the id is known |
| Restart | Running runs end `failed` with "The relay restarted during the answer." | Shows that error; the chat is read again on the next open |

The relay forwards `stream-chat` errors and `abort` chunks as `failed` instead of passing them on, which the client already treats as a failed answer.

Two relay features the client does not use:

- `reset: true` bodies. The client clears a chat with AnythingLLM's own `stream-chat`, which still works.
- `GET /v1/runs?status=running`. The client could use it to show, after a restart, that a chat is still being answered, where it now waits for the next open to read the chat again.

## Cards and live cards match

`packages/chatimage` and `packages/browser/src/browser/live.py` serve what `lib/adapters/image_frames.dart` and `loadableImage` expect:

- A card is `[![title](https://<host>:8445/_cards/<name>.png?v=<hash>)](<page>)`.
- A live card is `multipart/x-mixed-replace; boundary=frame`, each part with its own `Content-Type` and `Content-Length`, ending with `--frame--`. The browser's card pushes JPEG, the others PNG.
- Live cards are on the server's own host: `:8445/_live/run/`, `/_live/research/`, `/_live/agents/` and `/_live/browser/`. Sandbox pages are on `:8447`. `loadableImage` allows any port on the connected host.
- New on 2026-10-07: the browser's login request card, `/_live/browser/login/<id>.png`, linking to a form in the take-over view. It is a live card like the others, and its link opens in the in-app browser.

## What everythingllm deploys over

`packages/hostctl/src/hostctl/sync.py` (`uv run hostctl sync`) makes the repository the source of truth for part of AnythingLLM's settings, through AnythingLLM's API. Its deploy overwrites a change made anywhere else:

| Setting | What a deploy does | AnywhereLLM today | The proposed desktop Settings |
| --- | --- | --- | --- |
| Every workspace's system prompt, but `agents-*` | Sets it from `anythingllm/system-prompt.md` | Files edits a workspace's `PROMPT.md`; the next deploy replaces it | -- |
| Default system prompt | Sets it from the same file | -- | Default system prompt would be replaced |
| Scheduled jobs | Matched by name; replaces name, cron, tools and prompt, keeps on or off | -- | Scheduled jobs: edits to the repository's jobs would be replaced; switching them and new jobs survive |
| Slash command presets | Matched by command; presets made only in the UI are left alone | Reads presets only | -- |
| Custom skills | Code and manifests from the repository; keeps the on-off switch and setup values from the live copy | -- | Agent skills: switching and configuring survive |
| MCP servers | Writes `storage/plugins/anythingllm_mcp_servers.json` | -- | Agent skills: switching a server off only stops its process (`toggleServerStatus`), which AnythingLLM starts again on its next restart or reload; deleting one removes it from the file, and the next deploy puts it back. Keeping one off means `anythingllm.autoStart: false` in the repository's file |

The repository's README says the rest of AnythingLLM's settings (providers and keys, workspaces, which built-in skills are off) are set through AnythingLLM's UI, so the app can own those.

## Planned on the relay side

`docs/TODO.md` there plans push notifications for this app through UnifiedPush: the relay would get its own VAPID keys and a `POST /push` route that stores the app's endpoint, replacing its ntfy settings. On the app side that needs the `unifiedpush` Flutter package and a distributor on each device. Nothing of it exists yet.
