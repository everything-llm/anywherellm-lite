# What a /reset command can do on AnythingLLM

Findings from reading AnythingLLM 1.16.2's server source (`/app/server` in the `systemd-anythingllm` container on owen) and this repository's history on 2026-10-16. Nothing was run against a server.

## What the server does

| Request | Result |
| --- | --- |
| `stream-chat` with `{"message": "/reset"}` | Reaches the model as text. The `/v1` handler runs `grepAllSlashCommands`, which swaps only the server's presets (its own comment says it does not support them), and never checks `VALID_COMMANDS` |
| `stream-chat` with `{"reset": true}` and no message | Marks the thread's chats `include: false`, writes one `textResponse` chunk, `Chat history was reset!`, and ends |
| `stream-chat` with `{"reset": true, "message": "..."}` | Resets first, then answers the message with an empty history |

- The reset route accepts an empty message only when `reset` is true. Without it, the thread route answers 400 `Message is empty`.
- The web UI's `/reset` (`VALID_COMMANDS`, `commands/reset.js`) is a different path and takes the web login. The app never uses it.
- The reset touches rows where `workspaceId`, `thread_id` and `api_session_id: null` match. `thread_id` is the chat's own, so other chats of the workspace keep their history.
- Nothing is deleted. Rows keep `include: false`, and no `/v1` or app call sets it back.
- `include: false` hides the exchanges everywhere: `recentChatHistory` (the model's context, chat and query modes), the agent's history (`ephemeral.js`), and `GET /v1/workspace/{slug}/thread/{t}/chats`, which filters `include: true`. The web UI hides them too.
- The closing chunk carries no `chatId`, and no new exchange is made.

## What the app had

Commits `51cfdd2` and `5ea14f1` (2026-10-13) removed it. The pieces, recoverable with `git show 5ea14f1 51cfdd2`:

- `AnythingLlmApi.resetChat(slug, thread)`: a `stream-chat` with `{'reset': true}` drained to its end.
- `ChatController._reset`: emptied the thread's turns, tracked `_clearingIn` so `busy` held the composer, and cleared a draft without calling the server.
- `core/commands.dart` (`SlashCommand`, `withBuiltIns`, `resetsChat`) and a `SlashMenu` in the composer that listed `/reset` and the server's presets.

The removal was a decision, not a bug. The presets came from `GET /api/system/slash-command-presets`, which takes the web login, and the commit says New chat replaces clearing one. `CLAUDE.md` still records that `/reset` sent as text reaches the model.

## What exists now

- The composer's slash picker lists local shortcuts (`PromptShortcut`, 1.5.0). It sends prompts, so a `/reset` entry would be the first built-in that acts instead.
- Retry and Edit leave the old exchange on the server. After a reset those exchanges are hidden along with the rest.
- `ChatController._newest` records the newest `chatId` the server had saved, to find a waited-for answer. After a reset every history read is empty, so it must be cleared with the turns.

## Open points

- The app's chat shows reset exchanges as gone, and so does the web UI. A person who resets by accident cannot get them back from the app.
- Whether the closing `textResponse` should show as a note in the chat or not at all.
- A reset while an answer runs in that workspace: an agent answer may be saved after the rows are marked, and would then show. `busy` already holds the composer while an answer runs, which covers a reset sent from the app.

## Not checked

- A live call. The route is read from source only. A scratch workspace and thread would show the closing chunk, the 400 without `reset`, and the history read after.
