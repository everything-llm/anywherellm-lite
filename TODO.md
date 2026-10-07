# TODO

What AnythingLLM's own web UI (v1.16.2) does that AnywhereLLM does not yet. Each row says what blocks it.

## Defects to fix

| Defect | Fix | Where |
| --- | --- | --- |
| Attaching a file in the composer, then saving or forgetting the server password in Settings, silently clears the attachment though the server on screen did not change. | Track the chat on screen by the connection without its password, so saving or forgetting a password is the same server. | `_chatOnScreen` in `lib/ui/chat/composer.dart` (compare `_scope.settings.connection?.withPassword(null)`). |

## In the developer API, not built yet

| Gap | What it needs |
| --- | --- |
| Users and invites | `/v1/admin/*`. They matter only in multi-user mode. |
| Generate or edit an image | `POST /v1/openai/images/generations`, multipart with `prompt`, optional `size` and optional `image_references` to edit. It answers a base64 PNG, and only when the server has an image provider set up. |
| Chats that are in no chat thread | `GET /v1/workspace/{slug}/chats` answers `history`: the chats sent outside any thread, such as the web UI's default workspace chat. Every workspace on the server checked on 2026-10-06 answered an empty list, so this waits until someone uses the default chat. |
| Large libraries a page at a time | `GET /v1/documents/folder/{name}` with `offset` and `limit`. The library is read in one call today. |
| Settings when a workspace is made | `POST /v1/workspace/new` takes `similarityThreshold`, `openAiTemp`, `openAiHistory`, `openAiPrompt`, `queryRefusalResponse` and `topN`. Today they are set afterwards in `settings.json`. |

## Needs a check against a live server

| Gap | What it needs |
| --- | --- |
| Agent tools menu, skills, flows, integrations and MCP servers | Agents run through `/v1` `stream-chat` in a workspace's Agent mode or with `@agent` (checked 2026-10-06). Turning skills, agent flows, app integrations (Gmail, Google Calendar, Outlook) and MCP servers on or off is not in `/v1`. |
| A model picker | `/v1/openai/models` appears to list workspaces, not a provider's models. The web UI lists a provider's models with `POST /api/system/custom-models` (`provider`, `apiKey`, `basePath`), which takes the web login; until it is checked, the model is a free-text field in Settings' Chat model card, `system.json` and `settings.json`. |
| Telling a web page from an upload named `url-...` | `docType` reads the stored name alone, so an upload such as `URL-list.md`, stored as `url-list.md-<uuid>.json`, shows `WEB`. A web page's name can end in `.md` or `.html` too, so the name cannot settle it. The document's metadata `chunkSource` (`link://...`) can, but a switched-off file keeps only its path, title and word count in `prefs.json`. |

## Local, no server needed

| Gap | Note |
| --- | --- |
| Send a dictated message on its own | The web UI's auto-submit speech. Dictation fills the message and waits for Send. |
| Read every answer aloud as it arrives | The web UI's auto-speak. Read aloud is a button on each answer, on Android only. |
| Spellcheck, auto-scroll and HTML in answers | The web UI's Customization > Chat preferences. Each is a local setting. |

## Needs a new dependency

| Gap | What it needs |
| --- | --- |
| A microphone on Linux | `speech_to_text` has no Linux implementation, so only Android has one. Linux needs another recogniser. |
| Read aloud on Linux | `flutter_tts` has no Linux implementation. Linux needs another speech engine, such as speech-dispatcher. |
| Dropping files onto the chat to attach them | `desktop_drop` is already in use for Sources. Decide whether a drop on the chat attaches or adds a source. |

## Needs the private session API

The web UI's own endpoints sign in with a session token, not the developer key, and promise no compatibility. The app signs in to them with the server's password when one is saved, for the presets, Retry and Edit that replace the old exchange, and thumbs up or down. The gaps below would use the same sign-in.

| Gap | Why the developer API cannot do it |
| --- | --- |
| Edit a stored answer's text | `update-chat` rewrites one exchange's text in place. Edit replaces a question and everything after it instead. |
| Fork a chat from a message | No fork call. |
| Delete one message | No call deletes a stored chat. |
| Memories | Not in `/v1`. |
| Reset Vector Database | Not in `/v1`. Detaching every document is the nearest equivalent. |
| Default system prompt for new workspaces | Not in `/v1`. `workspace/new` takes `openAiPrompt`, so the app can set a prompt when it makes a workspace. |
| Custom system prompt variables | Adding, editing and deleting them is not in `/v1`. The server fills the built-in ones on every answer. |
| Workspace Chats across the server, and Clear Chats | Not in `/v1`. Export is in Files under `/settings`. |
| Suggested chat messages | Not in `/v1`. |
| Make, edit or delete a slash-command preset | No `/v1` call writes presets. |
| Server text-to-speech | Not in `/v1`. |

## Dropped, to revisit

| Feature | Why it was dropped |
| --- | --- |
| An app-wide **Only answer from my documents** switch | The web UI has none: each workspace's `chatMode` decides, and the Chat mode chooser in Sources sets it. The switch sent `mode: query` with every message and was on by default. `prefs.json`'s `groundedOnly` is now ignored, so an install that had it on answers in each workspace's own mode after upgrading, often Agent, with no notice. Bringing it back means sending `mode` again, which overrides the workspace's mode. |

## Out of scope

Instance administration beyond `system.json` stays in the web UI: switching the vector database (it deletes every vector), the server's password and signing secret, Scheduled Jobs, Event Logs, Model Router, Telegram, Branding, the Community Hub, Developer API keys, multi-user mode and password protection, the Browser Extension and AnythingLLM Mobile pairing, and the web UI's display language (the app has no translations).
