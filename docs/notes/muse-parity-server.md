# Server issues from the AnywhereLLM browser run

These came out of a run on 2026-10-07 that put AnywhereLLM's web build (Chrome, served from `http://localhost:8765`) beside muse.ai. The app was signed in to AnythingLLM on the home server (owen) at `https://<server>:3001`, where `<server>` is owen's tailnet name. Every chat ran in a `parity-scratch` workspace in Agent mode (`automatic`), with the main agent workspace's prompt and `glm-5.3-flash`. Each item below belongs to the server stack, not to the app, and they are in the order to fix them. Size is S (under a day), M (days) or L (a week or more).

## 1. The card host on :8445 cannot be read from a browser page (S)

The agent's cards never showed in Chrome. That covers the run-code chart, the live browser card and the deep-research progress card. The app draws each one as its alt text.

- A3: the chart card `GET https://<server>:8445/_cards/<id>.png?v=<hash>` answered 503 to Chrome, at about 15:21 CEST.
- A7: the live card `GET https://<server>:8445/_live/browser/bw-<id>.jpg` answered 503 to Chrome, at about 15:27 CEST.
- From a shell, the same live address answered 200 `multipart/x-mixed-replace`, with no `Access-Control-Allow-Origin` even when an `Origin` header was sent.

The app fetches a card with a bare `GET`: no key, no cookie, no custom header. That is a simple CORS request, so no preflight is needed.

What to change:

- Send `Access-Control-Allow-Origin` on `_cards/` and `_live/`. Because the request carries no credentials, `*` is enough.
- Find out why Chrome got a 503 when the shell got a 200. Check the card host's log at the two times above.
- An alternative for files such as the chart: report them in the agent's `outputs`, as `{type, payload: {filename, storageFilename, fileSize}}`. The app already fetches those through `GET /api/v1/document/generated-files/{storageFilename}`, and AnythingLLM's CORS already allows that. On this run the chart answer carried no `outputs`.

## 2. The relay sends no CORS headers (S)

A browser page cannot use the everythingllm relay. The web app therefore treats the server as having no relay, and posts answers to AnythingLLM's own `stream-chat`. An answer then ends when the tab closes, instead of running to the end and being saved.

Checked on 2026-10-07 with `Origin: http://localhost:8765`:

| Request | Answer |
| --- | --- |
| `GET /everythingllm/health` | 200 JSON, no `Access-Control-Allow-Origin` |
| `OPTIONS /everythingllm/v1/runs` (preflight for `POST` with `authorization, content-type`) | 403, no CORS headers |
| `OPTIONS /api/v1/auth` (AnythingLLM, same preflight) | 204, `Access-Control-Allow-Origin: http://localhost:8765`, methods and headers allowed |

What to change: answer CORS on every relay route the way AnythingLLM's `cors` does.

- Reflect the origin.
- Answer a preflight with 204 before the key is checked.
- Allow the headers `authorization`, `content-type` and `last-event-id`, and the methods `GET` and `POST`.

The events stream (`GET /everythingllm/v1/runs/{id}/events`) needs the same headers.

## 3. An agent answer's closing chunk has no chatId (S)

In `automatic` mode every message runs through AnythingLLM's agent path. In `server/utils/chats/apiChatHandler.js` (`streamChat`), that path ends with a `finalizeResponseStream` chunk that has `textResponse`, `outputs`, `sources`, `close` and `metrics`, but no `chatId`. The plain chat path's closing chunk does carry `chatId: chat.id`. The exchange is saved, and `GET /api/v1/workspace/{slug}/thread/{t}/chats` lists it with its `chatId`. The relay hands chunks back unchanged, so a relay run has the same gap.

Without the id, the app cannot mark the answer, edit the question, or have Retry delete the old exchange until the chat is read again. The app now reads the chat's history after each answer to find the id, which costs one extra request per answer.

What to change: add `chatId` to the agent path's closing chunk, either as a patch to the deployed AnythingLLM or reported upstream.

## 4. A document attached in Agent mode reaches the model as an image (M)

A10 attached a 45-row CSV to a message in `parity-scratch`. It failed twice with `The agent model failed to respond: 400 图片输入格式/解析错误`, which means "image input format/parse error".

The app sends the file in `stream-chat`'s `attachments` as `{name, mime: "application/anythingllm-document", contentString: "data:text/csv;base64,..."}`. This is the shape AnythingLLM reads in as a document for that message. The agent path appears to pass every attachment to the model as an image part.

What to change:

- In the agent path, parse a `application/anythingllm-document` attachment to text, as the chat path does.
- Check which chunk type carries an agent model failure. The app showed this one as answer text, not as a failed answer, so it probably arrived as `textResponse` rather than as an `error` chunk.

## 5. Deep research does not post back into the chat (M)

A9 started research run `dr-8338e2fd`. Its report was published to the research site, and nothing came back into the chat it was asked from. The only view of its progress was the live card, which item 1 blocks.

What to change: when a run finishes, add its summary and a link to the report to the chat that started it.

## 6. No image-generation tool (M)

A6 asked for a watercolor image. The agent answered that the workspace has no image-generation tool.

What to change: add one whose result comes back as an agent `outputs` entry (`imageGenerationCard`). The app already draws those.

## 7. APIs the app needs for its own gaps (M each)

Each of these blocks a feature that Muse has and AnywhereLLM cannot build from AnythingLLM's `/api/v1`:

| API | For | Seen on this run |
| --- | --- | --- |
| List and read the workspace sandbox (`/project`, `/public`) | Opening files and pages the agent made | A4 wrote `/project/pomodoro/index.html`, and nothing in the app can open it |
| List scheduled jobs | A view of reminders and jobs | A5's job exists only on the server |
| List and delete memories | A memory view | A8: one memory, no way to see it, and the agent has no delete tool |
| Full-text search over chats | Search beyond chat names | C6: the app filters names only |

The proposal is to put them under `/everythingllm/v1/`, with the developer key and the CORS from item 2.

## Left on the server from the run

- The workspace `parity-scratch` and its chats.
- The one-off job "scratch test reminder - delete me", for Thursday 2026-10-08 09:00 CEST. It deletes itself after it runs.
- `/project/pomodoro/index.html` in `parity-scratch`'s sandbox.
- Research run `dr-8338e2fd` on the research site.
