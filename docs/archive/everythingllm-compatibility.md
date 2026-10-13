# AnywhereLLM against the everythingllm repository

Findings from reading `BinaryBand/everythingllm` at commit 5444f2b (2026-10-07 17:36 +0200) against AnywhereLLM at commit e1b4d6a. That repository calls this app Nilson. Nothing was run against a server.

## The relay matches the client

`packages/relay` (`app.py`, `runs.py`, `auth.py`, `upstream.py`, `store.py`) and its README section "Nilson relay" agree with `lib/adapters/anythingllm_client.dart` on every point the client uses.

| Point | Relay | Client |
| --- | --- | --- |
| Health | `GET /health` answers `{"ok": true, "service": "everythingllm", "features": ["runs"]}`, no key | `_isRelay` checks `service` and `runs` in `features`, sends no key, does not remember a 5xx |
| Mount | `/everythingllm/` on AnythingLLM's https :3001, prefix stripped or not | `relayPath` is `/everythingllm` on the connection's address |
| Key | The caller's developer key, checked with `GET /api/v1/auth`; refused is 403 `No valid api key found.`, unreachable is 502 | Sends the same key; reads `error` from the body |
| Start | `POST /v1/runs` with `workspace`, `thread`, `clientId`, `body`; `body` needs a `message` or `reset: true`; 201 with the run, 200 for a `clientId` already used, 409 for a busy thread | Sends those four fields and a fresh `clientId` per message; reads `id` |
| Events | `GET /v1/runs/{id}/events`: `chunk` with each `stream-chat` chunk unchanged, then `done` `{}`, `failed` `{"error"}` or `cancelled` `{}`; ids from 1; `Last-Event-ID` resumes; `: ping` every 15 s | Reads `chunk` through `chatEventsOf`, ends on `done` or `cancelled`, fails on `failed` with its `error`, resumes with `Last-Event-ID`, gives up on 45 s of silence |
| Cancel | `POST /v1/runs/{id}/cancel`; a finished run is left as it is | `stopChat` posts it once the id is known |
| Restart | Running runs end `failed` with "The relay restarted during the answer." | Shows that error; the chat is read again on the next open |

The relay forwards `stream-chat` errors and `abort` chunks as `failed` instead of passing them on, which the client already treats as a failed answer.

The routes on :3001 and :8445 are the machine's own, listed in `packages/hostctl/src/hostctl/apps.toml`. They must pass each part of a stream on unbuffered, for the relay's events and the live cards.

Two relay features the client does not use:

- `reset: true` bodies. The client clears a chat with AnythingLLM's own `stream-chat`, which still works.
- `GET /v1/runs?status=running`. The client could use it to show, after a restart, that a chat is still being answered, where it now waits for the next open to read the chat again.

## Cards and live cards match

`packages/chatimage` and `packages/browser/src/browser/live.py` serve what `lib/adapters/image_frames.dart` and `loadableImage` expect:

- A card is `[![title](https://<host>:8445/_cards/<name>.png?v=<hash>)](<page>)`.
- A live card is `multipart/x-mixed-replace; boundary=frame`, each part with its own `Content-Type` and `Content-Length`, ending with `--frame--`. The browser's card pushes JPEG, the others PNG.
- Live cards are on the server's own host: `:8445/_live/run/`, `/_live/research/`, `/_live/agents/` and `/_live/browser/`. Sandbox pages are on `:8447`. `loadableImage` allows any port on the connected host.
- The browser's login request card, `/_live/browser/login/<id>.png`, links to a form in the take-over view. It is a live card like the others, and its link opens in the in-app browser.

## Notifications the app does not read

The server posts to one ntfy topic, `NTFY_URL` and `NTFY_TOKEN` in `~/.config/everythingllm/relay.env` on the server. The app has no setting for that topic and no ntfy client.

| Sender | Title | Tags | Click |
| --- | --- | --- | --- |
| Relay, when a run ends (a reset is not notified) | `Answer ready` or `Answer failed` | `run=<run id>,workspace=<slug>,thread=<thread>` | -- |
| research-runner, when a deep-research run started from a workspace's chat ends | `Research ready` or `Research failed` | `run=dr-...,workspace=<slug>,thread=<numeric thread id>` | The report's URL, when there is one |

Each body is the question's first 120 characters.

A research run's `thread` is AnythingLLM's numeric thread id, not the slug that `/api/v1` gives the app. The server's README expects the app to find the chat by the run id in the live card it drew (`/_live/research/<run id>.png`). A gateway client's research run and a scheduled job's notify no one.

The repository's `docs/TODO.md` plans push through UnifiedPush in place of ntfy: a VAPID key pair of the relay's own, a `POST /push` route that stores the app's endpoint in `relay.db`, the same payloads, and no `NTFY_*` settings. The app would need the `unifiedpush` Flutter package and a distributor on each device.

## What everythingllm deploys over

`packages/hostctl/src/hostctl/sync.py` (`uv run hostctl deploy`) makes the repository the source of truth for part of AnythingLLM's settings, through AnythingLLM's API. Its deploy overwrites a change made anywhere else:

| Setting | What a deploy does | The proposed desktop Settings |
| --- | --- | --- |
| Default system prompt | Sets it to the EverythingLLM block, `anythingllm/system-prompt.md` wrapped in `<everythingllm version="<hash>">` | Default system prompt would be replaced |
| System Prompt Variable `everythingllm_version` | Sets it to the repository's prompt version | Editing it would be replaced |
| Scheduled jobs | Matched by name; replaces name, cron, tools and prompt, keeps on or off | Scheduled jobs: edits to the repository's jobs would be replaced; switching them and new jobs survive |
| Custom skills | Code and manifests from the repository; keeps the on-off switch and setup values from the live copy | Agent skills: switching and configuring survive |
| MCP servers | Writes `storage/plugins/anythingllm_mcp_servers.json` | Agent skills: switching a server off only stops its process (`toggleServerStatus`), which AnythingLLM starts again on its next restart or reload; deleting one removes it from the file, and the next deploy puts it back. Keeping one off means `anythingllm.autoStart: false` in the repository's file |

A deploy leaves a workspace's own system prompt alone, so Files' `PROMPT.md` edits survive it. The repository's prompt goes into a workspace as the EverythingLLM block only when the agent runs the `update-prompt` skill there. The skill replaces the block and keeps the text around it; a prompt without a block keeps its text after the block, under `Your own instructions:`. The block asks the model to say once when its version is behind `{everythingllm_version}`.

The setup checklist (`packages/hostctl/src/hostctl/machine.py`, `reranker_off`) expects `AGENT_SKILL_RERANKER_ENABLED=false` in AnythingLLM's `.env`, because the reranker scored only the last message with an English-only model and dropped tools from follow-ups. Settings' Server settings as JSON page writes `AgentSkillRerankerEnabled` and can switch it back on, which the checklist then reports.

The repository leaves the rest of AnythingLLM's settings (providers and keys, workspaces, slash command presets, which built-in skills are off) to AnythingLLM's UI, so the app can own those.
