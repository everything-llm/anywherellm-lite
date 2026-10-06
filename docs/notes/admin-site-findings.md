# AnythingLLM admin site compared with AnywhereLLM

Findings from reading the web UI's instance settings and one workspace's settings (`career`) on the home server, AnythingLLM v1.16.2, single-user mode with a password, on 2026-10-06. Nothing was changed on the server. The comparison is against branch `feat/web-ui-gaps` at commit 611095a.

## Agent mode is overridden by the app

Every workspace checked is set to chat mode Agent. In that mode the model calls tools on its own when the provider supports native tool calling; otherwise the person types `@agent`.

The workspace system prompt depends on those tools:

- web search and web scraping;
- Deep Research, which answers with a progress card and publishes a report later;
- a code sandbox with `/work`, `/project`, `/shared` and `/public`;
- site publishing and Zola site builds;
- podcasts;
- Gmail;
- server audit tools.

The prompt also asks the model to paste any `Card:` line a tool returns as Markdown, so that it shows as a large clickable card.

AnywhereLLM sends `mode` with every message: `query` when the Answers preference is "documents only", otherwise `chat`. It never sends the workspace's own mode. The developer API takes the message's `mode` over the workspace's `chatMode`, so a message from AnywhereLLM most likely runs without tools. The live check below confirmed it.

What a live check must settle:

| Question | Why it matters |
| --- | --- |
| Does `stream-chat` accept `mode: "automatic"`, or does leaving `mode` out apply the workspace's Agent mode? | Decides what the app sends. |
| Does an agent answer carry its text in each chunk's `textResponse`, which is all the parser reads apart from `abort`, `close` and `error`, or in other fields, such as tool-call status messages? | The stream parser in `adapters/anythingllm_stream.dart` would show nothing for text it does not read. |
| Does the final chunk still carry `sources` and `close: true`? | Citations and the end of an answer depend on it. |
| Does an `@agent` message behave differently from automatic tool use through the API? | The prompt mentions `@agent` as a fallback. |
| Does an answer carry `outputs` (files an agent made) that `document/generated-files/{name}` serves? | Already a TODO.md row. |

The check sends one message to a scratch workspace and deletes the workspace afterwards. It needs the user's approval because it writes to the server.

## What the live check found

Checked on 2026-10-06 in a scratch workspace with the server's default prompt, then deleted. The app now sends no `mode` and handles the agent stream; see `CLAUDE.md`.

| Question | Answer |
| --- | --- |
| What does the server use when `mode` is left out? | The workspace's `chatMode`. With no `mode` and with `automatic` the agent searched the web; with `chat` it answered without tools; `query` refused for want of documents. |
| Does `@agent` work through `/v1`? | Yes, in any mode. |
| Which chunks carry tool status? | `agentThought`, in `thought`, such as `` @agent is executing `web-browsing` tool {...} `` and `@agent: I found 47 results`. |
| Which chunks carry the answer? | `textResponseChunk` pieces stream what the agent writes before and between tools; one `textResponse` chunk with `close: true` has the whole answer; `finalizeResponseStream` repeats it with the `sources`, `thoughts`, `outputs` and `metrics`. |
| Do headers come within the 15 s `timeout`? | Yes, in under 100 ms. The first text took 8 to 10 s, and a whole answer 17 to 23 s. |
| What are agent sources? | The web results the tool read, 40 to 61 per answer, each with `title`, `text`, `chunkSource` and `score`. |
| How are agent turns stored? | Like any other: the history has the whole answer text and the sources. `outputs` was empty for a web search. |

## Workspace settings

| Web UI setting | Server column | AnywhereLLM today |
| --- | --- | --- |
| Workspace name | `name` | Rename in the sidebar. |
| Suggested chat messages | not in `/v1` | Missing. Needs the private session API. |
| Delete workspace | `DELETE /v1/workspace/{slug}` | Delete in the sidebar, after a confirmation. |
| Workspace LLM provider and model | `chatProvider`, `chatModel` | Free text in `settings.json`. |
| Chat mode: Agent, Chat, Query | `chatMode` | Read, never written; each message overrides it with `mode`. See above. |
| Chat history | `openAiHistory` | `settings.json`. |
| System prompt, with View History | `openAiPrompt` | `PROMPT.md`. The prompt history is not in `/v1`. |
| Query mode refusal response | `queryRefusalResponse` | `settings.json`. |
| LLM temperature | `openAiTemp` | `settings.json`. |
| Vector database identifier and Vector Count | none | Missing. `/v1/system/vector-count` gives the whole server's count only. |
| Search preference: Default or Accuracy Optimized | `vectorSearchMode` | `settings.json`. |
| Max context snippets | `topN` | `settings.json`. |
| Document similarity threshold | `similarityThreshold` | `settings.json`. |
| Reset Vector Database | not in `/v1` | Missing. Detaching every document is the nearest `/v1` equivalent. |
| Workspace agent LLM provider | `agentProvider`, `agentModel` | Free text in `settings.json`. |

Every writable column is reachable through `settings.json`, but as raw JSON with no form, no choices and no explanation of each value.

## Instance settings

| Web UI page | What it holds | Reachable through `/v1` |
| --- | --- | --- |
| AI Providers: LLM, Vector Database, Embedder, Text Splitter and Chunking, Voice and Speech, Transcription, Model Router | Server-wide providers | Only through `system/update-env`, which TODO.md keeps out of scope. `models.json` in Files shows the provider and model keys read-only. |
| AI Providers: Image Generation | The provider for `/img` | No provider is set on this server, so image generation through `/v1/openai/images/generations` would fail here. |
| Admin: Workspace Chats | Every chat on the server in one table, with Export and Clear Chats | Export is in Files under `/settings`. Clearing every chat is not in `/v1`. |
| Admin: Default System Prompt | The prompt new workspaces start with | Not in `/v1`. `workspace/new` takes `openAiPrompt`, so the app can set a prompt when it creates a workspace. |
| Agent Skills | Built-in skills, app integrations (Gmail, Google Calendar, Outlook), custom skills, agent flows, MCP servers | Not in `/v1`. Server administration. |
| Community Hub | Trending items, account, import | Out of scope. |
| Customization: UI Preferences | Theme and display language | Local preferences; the app has its own theme handling and no translations. |
| Customization: Branding and Whitelabeling | Logo and name | Out of scope. |
| Customization: Chat | Auto-submit speech, auto-speak replies, spellcheck, scrollbar, auto-scroll, render HTML in answers | Local preferences the app could add without the server. Speech input and output need new dependencies. |
| Channels: Telegram | A Telegram bot | Out of scope. |
| Tools: Chat Embed, Event Logs, Scheduled Jobs | Embeds, logs, jobs | Embeds are in `/v1/embed/*`; the rest is not in `/v1`. Out of scope. |
| Tools: Developer API | API keys | Out of scope; the app takes a key someone made here. |
| Tools: System Prompt Variables | `{time}`, `{time_24}`, `{date}`, `{datetime}`, `{datetime_24}`, `{workspace.id}`, `{workspace.name}`, plus custom ones | Not in `/v1`. The server fills them in on every answer, so a prompt edited in `PROMPT.md` can already use them; the app could list them as help next to the editor. |
| Tools: Browser Extension, AnythingLLM Mobile | Pairing other clients | Out of scope. No mobile devices are registered. |
| Security | Multi-user mode and password protection | Out of scope. Password protection is now on. |

## Effects of the password

The server now has a password, which it did not have when the slash-command menu was built.

- `GET /api/system/slash-command-presets` sits outside `/v1` and takes the web UI's session. It answered without one only while there was no password, so the app's slash menu will now list `/reset` alone. A preset typed in full still runs, because `stream-chat` expands it on the server.
- Every other feature the app uses goes through `/v1` with the developer key and is unaffected.

## Links and cards in answers

The workspace prompt asks the model for links and for `Card:` Markdown from tools, and for links to every page it publishes. A read-only look at the 19 stored answers on 2026-10-06 found no `Card:` text: the one card was a linked image, `[![title](https://<server host>:8445/...)](https://<server host>:8445/...)`, served from the AnythingLLM server's own host. Web sources name their page in `chunkSource` as `link://https://...`; 123 of 182 stored sources did.

AnywhereLLM now opens links in answers and web citations in the browser, and draws images from the server's own host only, so a card shows and an image address a model wrote cannot be fetched.

## Candidate next steps

| Step | Server writes | Depends on |
| --- | --- | --- |
| Live check of agent mode through `stream-chat`, then send the workspace's mode instead of overriding it, keeping `query` for "documents only" | One message in a scratch workspace, then its deletion | User approval |
| Handle agent stream events and `outputs` in `anythingllm_stream.dart`, if the check shows new event types | None | The live check |
| Open links in answers with `url_launcher`, and check how cards render | None | A new dependency |
| Say in the slash menu when presets cannot be listed because the server has a password | None | None |
| A form for `settings.json`: choices for chat mode, search preference and threshold, numbers with their bounds, with each setting's explanation from the web UI | Only what the person saves | Deciding whether chat mode becomes writable |
| List the system prompt variables beside the `PROMPT.md` editor | None | None |
| Local chat preferences: spellcheck, auto-scroll | None | None |
