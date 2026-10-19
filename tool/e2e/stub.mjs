// A scripted model for the e2e, run inside the throwaway AnythingLLM's container with its own Node:
// `node stub.mjs PORT`. AnythingLLM reaches it as a generic OpenAI provider for both chat and
// embeddings, so an answer and a document's vectors come out the same on every run, offline.
//
//   GET  /v1/models             the one model, `e2e-model`
//   POST /v1/chat/completions   `E2E answer to: <the last user message>`, streamed when asked
//   POST /v1/embeddings         a hashed bag of words in 64 numbers, scaled to length 1
//   GET  /page.html             a page for AnythingLLM's collector to read as a link
import { createServer } from "node:http";

const port = Number(process.argv[2] ?? 8901);
const model = "e2e-model";

/** What the model answers to [question]; the e2e checks look for this. */
const answerTo = (question) => `E2E answer to: ${question}`;

/** The text of a message's content, which is a string or a list of parts. */
const textOf = (content) =>
  typeof content === "string" ? content : (content ?? []).filter((p) => p.type === "text").map((p) => p.text).join(" ");

/** 64 numbers for [text]: each word adds to the slot its hash picks, then the whole is scaled to length 1. */
function embed(text) {
  const v = new Array(64).fill(0);
  for (const word of text.toLowerCase().match(/[a-z0-9]+/g) ?? []) {
    let h = 2166136261;
    for (const c of word) h = Math.imul(h ^ c.charCodeAt(0), 16777619);
    v[(h >>> 0) % 64] += 1;
  }
  const length = Math.hypot(...v) || 1;
  return v.map((x) => x / length);
}

const json = (res, status, body) => {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(body));
};

function chat(res, body) {
  const users = (body.messages ?? []).filter((m) => m.role === "user");
  const text = answerTo(textOf(users.at(-1)?.content).trim());
  const usage = { prompt_tokens: 10, completion_tokens: text.split(" ").length, total_tokens: 10 + text.split(" ").length };
  const created = Math.floor(Date.now() / 1000);
  if (!body.stream) {
    return json(res, 200, {
      id: "e2e", object: "chat.completion", created, model,
      choices: [{ index: 0, message: { role: "assistant", content: text }, finish_reason: "stop" }], usage,
    });
  }
  res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" });
  const chunk = (delta, finish = null, extra = {}) =>
    res.write(`data: ${JSON.stringify({ id: "e2e", object: "chat.completion.chunk", created, model, choices: [{ index: 0, delta, finish_reason: finish }], ...extra })}\n\n`);
  chunk({ role: "assistant", content: "" });
  for (const piece of text.match(/\S+\s*/g) ?? []) chunk({ content: piece });
  chunk({}, "stop", { usage });
  res.end("data: [DONE]\n\n");
}

createServer((req, res) => {
  let raw = "";
  req.on("data", (d) => (raw += d)).on("end", () => {
    const body = raw ? JSON.parse(raw) : {};
    const path = req.url.split("?")[0];
    if (req.method === "GET" && path === "/v1/models") return json(res, 200, { object: "list", data: [{ id: model, object: "model", owned_by: "e2e" }] });
    if (req.method === "POST" && path === "/v1/chat/completions") return chat(res, body);
    if (req.method === "POST" && path === "/v1/embeddings") {
      const inputs = Array.isArray(body.input) ? body.input : [body.input ?? ""];
      return json(res, 200, { object: "list", model, data: inputs.map((t, index) => ({ object: "embedding", index, embedding: embed(String(t)) })), usage: { prompt_tokens: 0, total_tokens: 0 } });
    }
    if (req.method === "GET" && path === "/page.html") {
      res.writeHead(200, { "Content-Type": "text/html" });
      return res.end("<!doctype html><title>E2E page</title><h1>E2E page</h1><p>The e2e page says the harbour opens at dawn.</p>");
    }
    json(res, 404, { error: { message: `no route ${req.method} ${path}` } });
  });
}).listen(port, "127.0.0.1", () => console.log(`stub on :${port}`));
