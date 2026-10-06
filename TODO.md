# TODO

What AnythingLLM's own web UI (v1.16.2) does that AnywhereLLM does not yet. Each row says what blocks it.

## In the developer API, not built yet

| Gap | What it needs |
| --- | --- |
| Rename a workspace | `POST /v1/workspace/{slug}/update` with `name`. |
| Delete a workspace | `AnythingLlmApi.deleteWorkspace` exists and was checked live. It needs a sidebar action behind a confirmation. |
| Delete a library folder | `DELETE /v1/document/remove-folder` from the Files pane. |
| Test what a question retrieves | `POST /v1/workspace/{slug}/vector-search`, shown with each snippet's score. |
| Export every chat | `GET /v1/system/export-chats`, saved to a file. |
| Embed widgets, users and invites | `/v1/embed/*` and `/v1/admin/*`. Users and invites matter only in multi-user mode. |

## Needs a check against a live server

| Gap | What it needs |
| --- | --- |
| Agents (`@agent`) | Send `@agent` through `/v1` stream-chat and see whether the server runs the agent or refuses it. Only then decide on the Tools menu, agent skills and MCP servers. |
| A model picker | `/v1/openai/models` appears to list workspaces, not a provider's models. If so, the model stays a free-text field in `settings.json`. |

## Needs a new dependency

| Gap | What it needs |
| --- | --- |
| Links in answers open in the browser | `url_launcher`. Links are styled but do nothing when tapped. |
| A microphone in the composer | On-device speech recognition, such as `speech_to_text`. The web UI uses the browser's. |
| Dropping files onto the chat to attach them | `desktop_drop` is already in use for Sources. Decide whether a drop on the chat attaches or adds a source. |

## Needs the private session API

The web UI's own endpoints sign in with a session token, not the developer key, and promise no compatibility. Using them adds a second way to sign in.

| Gap | Why the developer API cannot do it |
| --- | --- |
| Regenerate | No call deletes the old answer, so a resend leaves both answers in the history. |
| Edit a prompt or an answer | No call edits a stored chat. |
| Thumbs up or down | No feedback call. |
| Fork a chat from a message | No fork call. |
| Delete one message | No call deletes a stored chat. |
| Memories | Not in `/v1`. |
| Suggested chat messages | Not in `/v1`. |
| Slash-command presets on a server with a password | The list comes from `/api/system/slash-command-presets`, which answers without a session only while the server has no password. With one, the menu offers `/reset` alone; a preset typed in full still runs. |
| Make, edit or delete a slash-command preset | No `/v1` call writes presets. |
| Server text-to-speech | Not in `/v1`. |
| Text size and other UI preferences | The web UI keeps them in its own settings, not in `/v1`. |

## Out of scope

Instance administration stays in the web UI: `system/update-env` (it writes the server's `.env`), LLM, embedder and vector-database providers, Scheduled Jobs, Event Logs, Model Router, Telegram, Branding and the Community Hub.
