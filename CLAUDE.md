# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Nilson is a Flutter Linux desktop chat client for an AnythingLLM server. It shows workspaces and their chats (AnythingLLM threads), streams answers, and manages each workspace's files in a Sources panel. It keeps the server address and API key in the system keyring and its other preferences in a JSON file. It calls AnythingLLM's developer API directly; there is no backend of its own.

## Commands

```bash
flutter pub get
flutter run -d linux
flutter analyze
flutter test                                   # whole suite; fakes the server and the keyring
flutter test test/ui/shell_test.dart           # one file
flutter test --plain-name 'a new server starts afresh'   # one test by name
flutter build linux --debug                    # -> build/linux/x64/debug/bundle/nilson
```

The Linux build needs `libsecret-1-dev`. Saving a key at run time needs a running, unlocked secret service such as gnome-keyring.

## Naming

- The product is **Nilson**: window title, wordmark, binary `nilson`, application ID `local.nilson.nilson`. The Dart package and the repository folder are still `everything`, so imports are `package:everything/...`.
- The `Nils*` UI-kit classes (`NilsApp`, `NilsButton`, `NilsSwitch`, `NilsBadge`, ...) are names left from an earlier version. They are not a backend reference.
- `flutter_secure_storage` keys its keyring entry by the application ID (`<APPLICATION_ID>.secureStorage`). Changing `APPLICATION_ID` in `linux/CMakeLists.txt` orphans any saved key.

## Architecture

Imports run `ui -> core <- adapters`. `lib/main.dart` is the only file that knows both sides. `test/layers_test.dart` enforces this with substring checks on import targets:

| Layer | May not import |
| --- | --- |
| `lib/core` | Flutter, `dart:io`, `dart:ui`, `http`, `flutter_secure_storage`, `file_selector`, `desktop_drop`, `ui`, `adapters` |
| `lib/adapters` | Flutter, `dart:ui`, `file_selector`, `desktop_drop`, `ui` |
| `lib/ui` | `dart:io`, `http`, `flutter_secure_storage`, `adapters` |

**Core** holds the ports (`core/ports.dart`: `AnythingLlmApi`, `SettingsStore`, `PrefsStore`), the server models (`core/server_models.dart`: `Workspace`, `Thread`, `ChatMessage`, `WorkspaceDoc`, `DocEntry`), and the pure logic: `core/chat.dart` (`ChatEvent`, `ChatMode`, `defaultTitle`), `core/sources.dart` (`mergeSources`), `core/prefs.dart` (`Prefs`, `OffDoc`) and `core/upload.dart`. Every failure is an `ApiException(message, {status})`. `NotConfigured` is the subtype thrown when no server is set up. To run calls at once, use `Future.wait` on futures that catch their own errors: the record `.wait` wraps errors in `ParallelWaitError`, which breaks the `on ApiException` handlers.

**The connection** lives in one shared `ConnectionHolder`, built in `main.dart`. `HttpAnythingLlmApi` reads it on every call, so a saved connection takes effect without a restart. `SettingsController` is the only writer, through `load`, `save` and `clear`, which notify listeners. `ChatController` listens and starts afresh when the connection changes; `SessionHost` builds it before reading the keyring, so reading a saved connection is what loads the workspaces. `verify(Connection)` takes an explicit connection so Settings can test one before saving; `SettingsController.connect` verifies first and saves only on success.

**Adapters:**

- `adapters/anythingllm_client.dart` maps HTTP failures to plain-language `ApiException`s. No message may contain the key; a test asserts this, and `Connection.toString` omits it.
- `adapters/anythingllm_stream.dart` turns a `stream-chat` response (server-sent `data:` lines) into `TextChunk`s and one closing `ChatDone`. An `error` chunk fails the stream. Cancelling the subscription is how Stop ends an answer.
- `adapters/keyring_settings_store.dart` stores the address and key as one JSON keyring entry.
- `adapters/json_prefs_store.dart` stores `Prefs` in `$XDG_CONFIG_HOME/nilson/prefs.json` (default `~/.config`), written to a temp file and renamed.

**AnythingLLM API facts the client relies on:**

- `GET /v1/workspaces` gives each workspace's threads with their names but no documents. `GET /v1/workspace/{slug}` gives documents, and threads without names, as a one-item `workspace` array. Thread names therefore come from the list call; document counts cost one call per workspace.
- A chat is a thread: `thread/new`, `thread/{t}/update`, `DELETE thread/{t}` (empty body), `thread/{t}/chats` for history, `thread/{t}/stream-chat` for answers. The final stream chunk has `close: true` and the `sources`; a citation is matched to a file by its `title`.
- `mode` is `query` (documents only) or `chat` (general knowledge too), sent per message from the local Answers preference. The workspace's `chatMode` on the server is never written.
- There is no per-document switch. Switching a file off is `update-embeddings` with `deletes`, and the file is remembered in `Prefs.switchedOff` so Sources keeps listing it. An upload is `document/upload`, then `update-embeddings` with `adds` of each returned `location`.
- `"Unknown"` is a server placeholder, read as absent. An upload can answer HTTP 200 with `success: false`.

**UI:**

- `ui/app_scope.dart` is an `InheritedWidget` that never notifies. It holds `ShellController` (sidebar drawer, Sources, Settings open), `SettingsController`, `PrefsController`, `ChatController` and `SourcesController`. Widgets wrap the controller they read in a `ListenableBuilder`, and `AppScope.of` is safe in `initState`.
- There are no routes. `ui/shell.dart` lays out `Sidebar | ChatView | SourcesPanel` and draws `SettingsDialog` over them. Below 820 px the sidebar is a drawer; below 1120 px Sources is a drawer. Esc and Back close Settings, then the drawers.
- `ChatController` keeps the workspaces, each workspace's threads, the turns of each opened chat and the one running answer (`_Running`: its turn, its thread, its stream). A `Turn` is itself a `ChangeNotifier`: a streamed chunk notifies only that turn, so only its answer rebuilds. A chat not yet asked anything is a draft held only in the controller; its first message creates the thread, and the first answer renames it with `defaultTitle` unless the person renamed it.
- `SourcesController` follows `ChatController.activeSlug`, merges the embedded documents with the switched-off ones, and owns the undo toast (6 s) and the citation flash (1.8 s).
- `main.dart`'s `SessionHost` awaits the keyring and prefs reads, then loads the chat, or opens Settings when nothing is saved.

## Tests

- `test/support/rig.dart`: `Rig` builds every controller over the fakes; `start()` loads them as the app does.
- `test/support/pump.dart`: `pumpApp(tester, {llm, prefsStore, connection, size, sourcesOpen})` builds the whole shell. `connection` defaults to `sampleConnection`; pass `null` for no server.
- `test/support/fake_api.dart`: `FakeAnythingLlm` keeps `FakeWorkspace`s (threads and docs), `histories` and a document `library` in memory, and records calls in `calls` as `name` or `name:arg`. `errors['methodName']` fails a method. `streamChat` answers `answer` and `cited`, or with `hold` set, whatever the test adds to `chat`. `planningServer()` is the mockup's data.
- A streaming answer's caret blinks forever, so `pumpAndSettle` times out while one runs; pump a fixed duration instead.
- `test/ui/responsive_test.dart` pumps the chat, the open drawers, Settings, a draft and the no-key banner at 1400, 1000, 780, 500 and 360 px wide, with long unbroken strings, and fails on any overflow. 360x480 is the window's minimum size (`linux/runner/my_application.cc`).

## Conventions

- Dependencies in `pubspec.yaml` are pinned by series (`">=1.6.0 <1.7.0"`). Moving to a newer series is a deliberate edit.
- Doc comments state what a thing is or does, in plain sentences, with `[name]` references. Match that density in new code.
