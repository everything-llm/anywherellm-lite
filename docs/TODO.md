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

The web UI's own endpoints sign in with a session token, not the developer key, and promise no compatibility. The app never signs in to them: it reaches saved memories and scheduled jobs through the toolkit, and leaves presets, ratings and deleting exchanges alone. Each gap below needs that sign-in, or a toolkit route that makes the call for it.

| Gap | Why the developer API cannot do it |
| --- | --- |
| A model picker | `GET /v1/openai/models` lists the workspaces, not a provider's models (settled against v1.16.2's source on 2026-10-07). The web UI lists a provider's models with `POST /api/system/custom-models` (`provider`, `apiKey`, `basePath`), which takes the web login. Until then the model is a free-text field: in the workspace's Chat model picker, on Settings' AI provider pages and in Server settings as JSON and `settings.json`. |
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

Instance administration beyond what Settings writes to the server's `.env` stays in the web UI: switching the vector database (it deletes every vector), the server's password and signing secret, making and editing Scheduled Jobs (the app lists them read-only in Upcoming), Event Logs, Model Router, Telegram, Branding, the Community Hub, Developer API keys, multi-user mode and password protection, the Browser Extension and AnythingLLM Mobile pairing, and the web UI's display language (the app has no translations).

Since the app was simplified to AnywhereLLM Lite, a phone chat client rather than an admin console, these stay in the web UI as well: the agent's skills, flows, app integrations and MCP servers; users and invites; signing in to a multi-user server (such a server takes a pasted key); and the server's own text-to-speech, since answers are read aloud on the device.

## apps-lean: open from the stress test

- Custom apps are slow: 2 to 7 minutes from request to page.
- Kanban: the agent adds example cards nobody asked for.
- Timeline figure: labels are cut at 10 characters.

## Lite prototype: not built yet

- Confirm the prototype's welcome wording removal of "Make one in AnythingLLM's web page: Settings, Developer API, Generate New API Key." under the key. The app still shows it.
- A tappable apps-lean card. The app opens a linked page already (`isAppsLeanPage`), but the card is a blockquote with a linked title only once the apps-lean skill writes that shape.
- Add the toolkit, Step 1: `uv run anythingllm-toolkit gui` is a stand-in until the installer's distribution is settled.
- Guide figures draw whole as they grow in. The prototype animates each element in turn.
- Demos and Vault in the prototype are prototype-only and need no app work.
