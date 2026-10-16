# What the full Settings design can reach on AnythingLLM

Findings from reading AnythingLLM v1.16.2's server source (`server/endpoints/`, tag `v1.16.2`) on 2026-10-07, for the proposed desktop Settings on the retired Design canvas (`DesktopSettings.dc.html`). Nothing was run against a server. Route paths below are relative to `/api`.

## Two ways in

| Credential | Middleware | What it opens |
| --- | --- | --- |
| Developer key, `Authorization: Bearer <key>` | `validApiKey` | The 63 routes under `/v1` |
| Web login, the JWT from `POST /request-token` with the server password | `validatedRequest` | The web UI's own routes, outside `/v1` |

The app already holds both: it signs in with the server password for slash-command presets, feedback, deleting exchanges and making its own key. On a server without a password, `validatedRequest` lets every request through, so the web routes need no login there.

In single-user mode, `flexUserRoleValid` lets every role check pass, so any web route marked admin-only is open to the web login. Routes marked `isSingleUserMode` (scheduled jobs, Telegram) refuse a multi-user server. Routes marked `strictMultiUserRoleValid` (users, invites, the admin key list) exist only in multi-user mode.

## What the developer key reaches

`POST /v1/system/update-env` writes any of the 217 keys in `KEY_MAPPING` (`server/utils/helpers/updateENV.js`), except `AuthToken` and `JWTSecret`, which need the force flag the route never passes. `GET /v1/system` reads them back, with secrets as booleans. Together they cover every provider choice and its fields:

- the chat model: `LLMProvider` and each provider's key, base path, model and token limit;
- the embedder: `EmbeddingEngine`, `EmbeddingModelPref`, `EmbeddingBasePath`, `EmbeddingModelMaxChunkLength` and the embedder keys;
- the vector database: `VectorDB` and each database's endpoint, key and names;
- image generation: `ImageGenerationProvider` and its fields;
- speech: `TextToSpeechProvider`, `SpeechToTextProvider` and their `TTS*` and `STT*` fields;
- transcription: `WhisperProvider`, `WhisperModelPref` and the generic OpenAI fields;
- the agent's search keys and SearXNG address (`Agent*ApiKey`, `AgentSearXNGApiUrl`), its tool-call limit and reranker (`AgentSkillMaxToolCalls`, `AgentSkillRerankerEnabled`, `AgentSkillRerankerTopN`);
- the model router in use (`ModelRouterId`), but not the routers themselves;
- telemetry (`DisableTelemetry`).

The rest of the server's settings live in the `system_settings` table, not in `.env`. The developer key reaches them through `POST /v1/admin/preferences` only, and that route answers 401 unless the server is in multi-user mode. On a single-user server, the developer key cannot change the text splitter, the agent's skills, its search provider, the default system prompt, or any other `system_settings` field.

No `/v1` route lists a provider's models. `GET /v1/openai/models` lists the workspaces. The web UI's model lists come from `POST /system/custom-models`, which takes the web login.

## Section by section

For a single-user server with a password, as the home server is.

| Section | Developer key alone | With the web login | Routes |
| --- | --- | --- | --- |
| Connection, Appearance, Chat | -- | -- | Kept on the device; `GET /v1/auth` checks the key |
| Chat model | Read and write everything | Adds the model list | `GET /v1/system`, `POST /v1/system/update-env`, `POST /system/custom-models` |
| Embedder | Read and write everything | Adds the model list | As for the chat model; changing it deletes every vector |
| Vector database | Read and write everything, and the vector count | -- | `update-env` `VectorDB`, `GET /v1/system/vector-count` |
| Text splitter | Nothing | Read and write | `GET /admin/system-preferences-for?labels=text_splitter_chunk_size,text_splitter_chunk_overlap`, `POST /admin/system-preferences` |
| Image generation | Read and write everything | -- | `update-env` |
| Voice and speech | Read and write everything | -- | `update-env` |
| Transcription | Read and write everything | -- | `update-env` |
| Model router | Choose an existing router | List, make, edit and delete routers and their rules | `update-env` `ModelRouterId`; `/model-routers`, `/model-routers/:id/rules/*` |
| Agent skills: built in, file system, Gmail, Calendar, Outlook, SQL | Nothing | Read and write | `/admin/system-preferences` labels `default_agent_skills`, `disabled_agent_skills`, `disabled_filesystem_skills`, `disabled_create_files_skills`, `disabled_gmail_skills`, `gmail_agent_config` and the like; `POST /system/validate-sql-connection` |
| Agent skills: web search | Keys and SearXNG address only | Adds the provider choice | `update-env`; `/admin/system-preferences` label `agent_search_provider` |
| Agent skills: custom skills | Nothing | Switch on and off, configure, delete | `/experimental/agent-plugins/:hubId/toggle`, `/config`, `DELETE /experimental/agent-plugins/:hubId` |
| Agent skills: MCP servers | Nothing | List, switch servers and single tools, delete, reload | `/mcp-servers/list`, `/toggle`, `/toggle-tool`, `/delete`, `/force-reload`; adding a server means editing its config file on the server |
| Agent flows | Nothing | List, read, save, switch, delete | `/agent-flows/*` |
| Workspace chats | List, 20 a page, and export | Delete one, or all with id `-1` | `POST /v1/admin/workspace-chats` (no multi-user check), `GET /v1/system/export-chats`, `DELETE /system/workspace-chats/:id` |
| Default system prompt | Nothing | Read and write | `GET` and `POST /system/default-system-prompt` |
| Prompt variables | Nothing | List, add, edit, delete | `/system/prompt-variables`, `/system/prompt-variables/:id` |
| Chat embeds | Everything: list, make, switch, change mode, delete, read chats | -- | `/v1/embed`, `/v1/embed/new`, `/v1/embed/:uuid`, `/v1/embed/:uuid/chats` |
| Scheduled jobs | Nothing | Everything, including run now and each run's result | `/scheduled-jobs/*`; refused in multi-user mode |
| Event logs | Nothing | List and clear | `POST` and `DELETE /system/event-logs` |
| Developer API | Nothing | List, make, delete | `/system/api-keys`, `/system/generate-api-key`, `DELETE /system/api-key/:id` |
| AnythingLLM Mobile | Nothing | List, rename, delete, and the connection details | `/mobile/devices`, `/mobile/update/:id`, `DELETE /mobile/:id`, `/mobile/connect-info`; a device registers itself from the mobile app |
| Browser extension | Nothing | List, make, delete keys | `/browser-extension/api-keys`, `/new`, `/:id` |
| Telegram | Nothing | Connect, disconnect, status, approve and revoke users | `/telegram/*`; refused in multi-user mode |
| Community Hub | Nothing | Hub key, browse, import | `/community-hub/*` |
| Security: password | Nothing | Change it, or turn it off | `POST /system/update-password` with `usePassword` and `newPassword`; refused in multi-user mode |
| Security: multi-user mode | Nothing | Turn it on | `POST /system/enable-multi-user` |
| Privacy and data | Read it, and switch telemetry | -- | `GET /v1/system`, `update-env` `DisableTelemetry` |

## How far each credential gets

| Credential | Sections it covers |
| --- | --- |
| Developer key alone | Whole: vector database, image generation, voice and speech, transcription, chat embeds, privacy. In part: chat model and embedder without their model lists, workspace chats without deleting, the agent's search keys, choosing a model router. That is 6 of the 23 server sections whole and 5 in part; the other 3 sections live on the device. |
| Developer key and web login | Every section on the canvas. |
| Neither | Adding an MCP server (a file on the server), registering a mobile device (done from the mobile app), and Branding and Interface, which change only the web UI and were left off the canvas. |

The app's Settings builds the three device sections and the sections the developer key reaches: chat model, embedder, vector database (shown, never switched), image generation, voice and speech, transcription, workspace chats (list and export), chat embeds and privacy, plus the server's `.env` settings as JSON. It builds none of the sections that need the web login.

## Multi-user servers

A multi-user server turns this around. The developer key reaches `system_settings` through `/v1/admin/preferences`, and users and invites through `/v1/admin/*`. The web routes need a user's own login, which AnywhereLLM cannot make: it signs in with the instance password only. When the server sets `SIMPLE_SSO_ENABLED`, `GET /v1/users/:id/issue-auth-token` lets the developer key issue a temporary login for a user, which is a way into the web routes without that user's password. Scheduled jobs, Telegram and the password route refuse a multi-user server whatever the login.

## Cautions for building it

- Changing `EmbeddingEngine`, `EmbeddingModelPref` or `AzureOpenAiEmbeddingModelPref` deletes every vector, and changing `VectorDB` deletes the old database's. Both already ask first in the app for the embedder; the vector database would need the same.
- Changing the password through `/system/update-password` rotates `JWTSecret`, which voids every login token, the app's own included. The app would have to sign in again with the new password at once.
- Turning on multi-user mode ends the single shared password; AnywhereLLM would then lose its web-login features until it can sign in with a user name.
- `POST /admin/system-preferences` accepts any field in `SystemSettings.supportedFields` and answers `success: true` without checking values, so the app has to send only what it means to change.
