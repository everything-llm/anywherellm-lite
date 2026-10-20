# Notes on CLAUDE.md

Original: `CLAUDE.md`.

## History

1. 2026-10-19: AnywhereLLM Lite replaced the full AnywhereLLM (`local.anywherellm.anywherellm`), a separate app in the personal F-Droid repo. Its last source is the tag `archive/anywherellm-2.16.0`. Lite's Kotlin `namespace` kept the old ID.
1. 2026-10-19: the toolkit became its own repository, anywherellm-bridge, after being part of anywherellm-suite. Before the suite it was `anythingllm-toolkit`, and before the rename `anythingllm-bridge`, which is why `Companion.formerly` and `Companion.names` still accept them.
1. Push from a server, UnifiedPush and the apps-v2 server were removed. Open items are in `docs/TODO.md`.

## Provenance

1. The robin mark is the "AnywhereLLM Icon" artifact's variant C: an even line weight, an open wing gap, every straight edge on the 60 degree grid. `_place` puts it on the 1024 unit box as that artifact's master tile does, in the Lite prototype's icon colours.
1. The app's look follows the Lite prototype: colour tokens, sizes, the browser sheet's tall form, the Message the agent bar, and the trimmed Server page.
