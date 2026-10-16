# Notes on docs/design.md

Original: `docs/design.md`.

## The retired Design canvas

The app's look was first mirrored in a Claude Design canvas, `VwYwfCQ2jLNQsYfojqfiGo`, titled AnywhereLLM. Claude Code built it by hand from `lib/ui` at commit 238c2e1 on 2026-10-07, without comparing it to the running app pixel for pixel. The owner's quieter restyle of the main chat board was built into the app on 2026-10-08.

On 2026-10-16 the owner unpinned it and moved design work to the Lite prototype, `XTJJTtc2x8aN4zB2fVPsBT`, which the Lite app is built from. The Artifact tool has no archive action, so the canvas stays at its URL, unedited.

Its desktop boards (`Main`, `Dark`, `DesktopSettings`, `Components`) describe an app Lite no longer is. Its Phone page held phone boards for Settings, Documents, sheets and the browser take-over.

## The Server settings trim

Two boards were added to the canvas on 2026-10-16, `PhoneServerBuilt` and `PhoneServerTrimmed`, the last edit it received. They propose that Lite stop being an admin console. The trim cuts the provider pages (Chat model, Document search model, Document storage, Image generation, Transcription, Voice and speech), Workspace chats and its export, Website chat widgets and Server settings as JSON. It keeps the same values as read-only lines, Privacy and data, and one link to AnythingLLM's web page.

The trim is not drawn in the Lite prototype and not built in the app.
