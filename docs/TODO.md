# TODO

What AnythingLLM's own web UI (v1.16.2) does that AnywhereLLM does not yet. Each row says what blocks it.

## In the developer API, not built yet

| Gap | What it needs |
| --- | --- |
| Generate or edit an image | `POST /v1/openai/images/generations`, multipart with `prompt`, optional `size` and optional `image_references` to edit. It answers a base64 PNG, and only when the server has an image provider set up. |
| Chats that are in no chat thread | `GET /v1/workspace/{slug}/chats` answers `history`: the chats sent outside any thread, such as the web UI's default workspace chat. Every workspace on the server checked on 2026-10-06 answered an empty list, so this waits until someone uses the default chat. |
| Settings when a workspace is made | `POST /v1/workspace/new` takes `similarityThreshold`, `openAiTemp`, `openAiHistory`, `queryRefusalResponse` and `topN` besides the `openAiPrompt` New workspace sends. Today they are set afterwards on the workspace's Answer from page. |
| Edit a stored answer's text | The web UI edits one answer in place. The app's Edit replaces a question and everything after it; `update-chat`, which rewrites one exchange's text, is not used. |

## Local, no server needed

| Gap | Note |
| --- | --- |
| Render HTML in answers | The web UI's Customization > Chat preference. A local setting; spellcheck, following a streaming answer, sending dictation when talking stops and reading answers aloud are built. |

## Needs the private session API

The web UI's own endpoints sign in with a session token, not the developer key, and promise no compatibility. The app never signs in to them: it reaches saved memories and scheduled jobs through the toolkit's bridge, and leaves presets, ratings and deleting exchanges alone. Each gap below needs that sign-in, or a bridge rule that passes the route.

| Gap | Why the developer API cannot do it |
| --- | --- |
| A model picker | `GET /v1/openai/models` lists the workspaces, not a provider's models (settled against v1.16.2's source on 2026-10-07). The web UI lists a provider's models with `POST /api/system/custom-models` (`provider`, `apiKey`, `basePath`), which takes the web login; a bridge rule `POST /system/custom-models` would pass it. Until then the model is a free-text field: in the workspace's Chat model picker, on Settings' AI provider pages and in Server settings as JSON and `settings.json`. |
| Fork a chat from a message | No fork call. |
| Delete one message | `DELETE /system/workspace-chats/:id` deletes one stored chat, but the app deletes exchanges only as Edit and Retry do, from an id on. |
| Reset Vector Database | Not in `/v1`. Detaching every document is the nearest equivalent. |
| Default system prompt for new workspaces | Not in `/v1`. New workspace sets a prompt for the one workspace it makes, through `workspace/new`'s `openAiPrompt`. |
| Custom system prompt variables | Adding, editing and deleting them is not in `/v1`. The server fills the built-in ones on every answer. |
| Clear Chats | Not in `/v1`. Listing and exporting every chat are on Settings' Workspace chats page. |
| Suggested chat messages | Not in `/v1`. |
| Make, edit or delete a slash-command preset | No `/v1` call writes presets. |

## Dropped, to revisit

| Feature | Why it was dropped |
| --- | --- |
| An app-wide **Only answer from my documents** switch | The web UI has none: each workspace's `chatMode` decides, and the Answer from chooser sets it. The switch sent `mode: query` with every message and was on by default. `prefs.json`'s `groundedOnly` is now ignored, so an install that had it on answers in each workspace's own mode after upgrading, often Agent, with no notice. Bringing it back means sending `mode` again, which overrides the workspace's mode. |

## Out of scope

Instance administration beyond what Settings writes to the server's `.env` stays in the web UI: switching the vector database (it deletes every vector), the server's password and signing secret, making and editing Scheduled Jobs without the toolkit (Upcoming changes them only where the toolkit's bridge passes their routes, and lists them read-only where it passes only the reads), a job's tools, Event Logs, Model Router, Telegram, Branding, the Community Hub, Developer API keys, multi-user mode and password protection, the Browser Extension and AnythingLLM Mobile pairing, and the web UI's display language (the app has no translations).

Since the app was simplified to AnywhereLLM Lite, a phone chat client rather than an admin console, these stay in the web UI as well: the agent's skills, flows, app integrations and MCP servers; users and invites; signing in to a multi-user server (such a server takes a pasted key); and the server's own text-to-speech, since answers are read aloud on the device.

## Considered, not decided

| Idea | Note |
| --- | --- |
| Push notifications from a server | UnifiedPush and the apps-v2 server were removed. Nothing sends a push to the app now: its two notifications, a running answer and a ready answer, are its own. A sender needs a way to hand it the phone's endpoint, a key to encrypt for, and a trigger such as an AnythingLLM scheduled job. apps-lean, a skill with no process, has none of these. The deleted `PushController`, `UnifiedPusher` and `PushEvents.kt` are in git history (the commit before the purge). |
| Fold the companion mechanism into the toolkit | The toolkit is the only companion left, yet `Companion`, `CompanionApi`, `CompanionClient`, `CompanionWatch` and the `companions` map in `Connection`, `Pairing` and the keyring entry still serve several. Folding them in is churn and changes what the keyring stores, so wait until it is clear that apps-lean needs no companion. |
| A machine for the agent | A second server beside the sandbox, `machine_mcp` in anythingllm-mcp (outside this repo): one persistent rootless podman container with systemd and root inside, wide public internet, no LAN and tailnet-only hosting. It would give the agent background tasks, installable network tools and served files, which the sandbox's runs and jobs cannot. Shelved on 2026-10-15 before any code. Settled: the sandbox stays untouched, no sudo (`diot` cannot open `/dev/kvm`, so no VM), container root mapped to a subuid range, an IP-level gateway that drops private ranges, `100.64/10` and the host, and a tagged Tailscale node. Open: whether gVisor runs systemd and tailscale, whether the rootless gateway filter works, and a setup and approval path without a terminal. |
| Edit AnythingLLM's native agent memory | AnythingLLM's `rag-memory` skill has two actions, `search` and `store`. `store` embeds the text into the workspace's vector namespace as a document titled `agent-memory.txt` with a random `docId` it never returns, and adds no row to the workspace's documents, so the Documents list and `update-embeddings` cannot reach it. The agent has no way to rewrite or delete a stored memory. The wish is agent tools to add, rewrite and delete them, exposed through the toolkit. A rewrite is a delete of the old vectors plus a store, and a delete needs the vector database client (`deleteDocumentFromNamespace` by `docId`) or a bridge route that reaches it; no `/v1` or `/api` route found so far does. Open: how a memory is found again (the vectors carry only the `agent-memory.txt` title and the text), and whether the tools live in a skill inside AnythingLLM or behind the bridge. |
| In-app feedback | Two readings, not yet chosen. Rating an answer: AnythingLLM's `POST /workspace/:slug/chat-feedback/:chatId` takes `{feedback}` and needs the web login, so it would go through the toolkit's bridge with a new `BRIDGE_ALLOW` rule such as `POST /workspace/*/chat-feedback/*`; the chat id is on every history entry, and on a chat or query answer's closing chunk, but not on an agent answer's. Feedback about the app: the app has no backend, so it can only open a mail or issue link. |
| Several chats answering at once in one workspace | The app lets one answer run per workspace and holds a second chat's field with `Another chat in this workspace is still answering...`; chats of other workspaces answer meanwhile. The recorded reason is that AnythingLLM gives an agent run no thread of its own, but in 1.16.2 the developer API's agent path (`EphemeralAgentHandler`) is given `threadId`, so recheck whether this is a server limit or only the app's guard before building. The rest of the work is in `ChatController`: `_runs` is keyed by workspace, and `busy`, `stop`, the queued send and the ready dots all read that. |
| Native tabs for companions | A companion whose `/health` declares a tab (`title`, `icon` and a declarative screen: lists, rows and actions as JSON) gets a native tab in the bar, with no Dart in the companion. It needs a small UI spec the app renders and keeps compatible, so wait for a companion that wants a tab. The apps-v2 Apps tab was removed with the apps-v2 server and is in git history. The bar fits about five tabs and Chats and Settings take two, so extra tabs need a cap or a place under More. A web-view tab (`tab: {title, icon, page}` shown in `AppView`) is the cheaper first step. |

## apps-lean: open from the stress test

- Custom apps are slow: 2 to 7 minutes from request to page.
- Kanban: the agent adds example cards nobody asked for.
- Timeline figure: labels are cut at 10 characters.

## Needs a server route

| Gap | Note |
| --- | --- |
| Library and Activity | Built and tested against `FakeToolkit`, hidden until `/health` offers `library` and `activity`, which `bridgeFeatures` never derives. AnythingLLM has no route that lists the agent's apps or files or what it did, and apps-lean keeps its apps as files with no listing route. |
| A task that runs once | The prototype's New task offers Once. AnythingLLM's scheduled jobs have no one-shot job, and a dated cron runs again every year, so the form leaves Once out. |
| A task's workspace | The prototype's New task picks a workspace. AnythingLLM's scheduled jobs belong to none. |

## For the toolkit's owner

- anythingllm-mcp's `toolkit` server still calls the toolkit's `/jobs`, which the bridge removed.
- The installer page (the toolkit's `gui` branch) predates the bridge, so it does not write `BRIDGE_ALLOW`; only `install` does.
- The installer bundles the toolkit (decided 2026-10-15): it ships a `uv` binary pinned by series and the toolkit's wheel, built in CI, and runs `uv tool install` itself, so the user never sees uv. Settled: the installer owns `UV_TOOL_DIR`, `UV_TOOL_BIN_DIR` and `UV_PYTHON_INSTALL_DIR`, so it never touches a uv the user has and uninstall deletes one folder; Python is always the installer's own copy at a pinned version (`UV_PYTHON_PREFERENCE=only-managed`), never one found on the machine; the toolkit is called by absolute path, and the service unit carries that path. Open: a restricted network can block the Python download; the toolkit's dependencies still come from PyPI; publishing the toolkit to PyPI is unchecked; updating the toolkit becomes part of the installer's release.
- The installer ships uv's `LICENSE-MIT` beside the bundled `uv` binary. uv is licensed under MIT or Apache-2.0, and its release archives carry no licence file, so the installer must add it. Whether the binary's third-party crate notices must ship too is unchecked.

## Lite prototype: not built yet

- apps-lean card: the app draws a quote whose first line links to an app's page as a tappable card (`appCardOf`), and a paragraph that opens with the link is drawn as one too, but the skill still writes a sentence with a link in it. The skill's `card.js` and README rule need the `> [**Title**](<page>)` shape.
- Add the toolkit, Step 1: `uv run anythingllm-toolkit gui` is a stand-in until the installer ships the bundled toolkit.
- Guide figures draw whole as they grow in. The prototype animates each element in turn.
- Demos and Vault in the prototype are prototype-only and need no app work.
