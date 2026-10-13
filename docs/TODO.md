# TODO

What AnythingLLM's own web UI (v1.16.2) does that AnywhereLLM does not yet. Each row says what blocks it.

## In the developer API, not built yet

| Gap | What it needs |
| --- | --- |
| Generate or edit an image | `POST /v1/openai/images/generations`, multipart with `prompt`, optional `size` and optional `image_references` to edit. It answers a base64 PNG, and only when the server has an image provider set up. |
| Chats that are in no chat thread | `GET /v1/workspace/{slug}/chats` answers `history`: the chats sent outside any thread, such as the web UI's default workspace chat. Every workspace on the server checked on 2026-10-06 answered an empty list, so this waits until someone uses the default chat. |
| Settings when a workspace is made | `POST /v1/workspace/new` takes `similarityThreshold`, `openAiTemp`, `openAiHistory`, `openAiPrompt`, `queryRefusalResponse` and `topN`. Today they are set afterwards in `settings.json`. |
| Edit a stored answer's text | The web UI edits one answer in place. The app's Edit replaces a question and everything after it; `update-chat`, which rewrites one exchange's text, is not used. |

## Local, no server needed

| Gap | Note |
| --- | --- |
| Render HTML in answers | The web UI's Customization > Chat preference. A local setting; spellcheck, following a streaming answer, sending dictation when talking stops and reading answers aloud are built. |
| Telling a web page from an upload named `url-...` | `docType` reads the stored name alone, so an upload such as `URL-list.md`, stored as `url-list.md-<uuid>.json`, shows `WEB`. A web page's name can end in `.md` or `.html` too, so the name cannot settle it. The document's metadata `chunkSource` (`link://...`) can, but a switched-off file keeps only its path, title and word count in `prefs.json`. |

## Needs the private session API

The web UI's own endpoints sign in with a session token, not the developer key, and promise no compatibility. The app signs in to them with the server's password when one is saved, for the presets, Retry and Edit that replace the old exchange, thumbs up or down, the saved memories, the Upcoming jobs and making its own key. The gaps below would use the same sign-in.

| Gap | Why the developer API cannot do it |
| --- | --- |
| A model picker | `GET /v1/openai/models` lists the workspaces, not a provider's models (settled against v1.16.2's source on 2026-10-07). The web UI lists a provider's models with `POST /api/system/custom-models` (`provider`, `apiKey`, `basePath`), which takes the web login. Until then the model is a free-text field: in the workspace's Chat model picker, on Settings' AI provider pages and in Server settings as JSON and `settings.json`. |
| Fork a chat from a message | No fork call. |
| Delete one message | `DELETE /system/workspace-chats/:id` deletes one stored chat, but the app deletes exchanges only as Edit and Retry do, from an id on. |
| Reset Vector Database | Not in `/v1`. Detaching every document is the nearest equivalent. |
| Default system prompt for new workspaces | Not in `/v1`. `workspace/new` takes `openAiPrompt`, so the app can set a prompt when it makes a workspace. |
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
