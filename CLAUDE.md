# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Nilson is a Flutter Linux desktop front end for an AnythingLLM server. It lists workspaces and documents, uploads files, and keeps the server address and API key in the system keyring. It calls AnythingLLM's developer API directly; there is no backend of its own and no chat.

## Commands

```bash
flutter pub get
flutter run -d linux
flutter analyze
flutter test                                   # whole suite; fakes the server and the keyring
flutter test test/ui/upload_test.dart          # one file
flutter test --plain-name 'a new server starts afresh'   # one test by name
flutter build linux --debug                    # -> build/linux/x64/debug/bundle/nilson
```

The Linux build needs `libsecret-1-dev`. Saving a key at run time needs a running, unlocked secret service such as gnome-keyring.

## Naming

- The product is **Nilson**: window title, wordmark, binary `nilson`, application ID `local.nilson.nilson`. The Dart package and the repository folder are still `everything`, so imports are `package:everything/...`.
- The `Nils*` UI-kit classes (`NilsApp`, `NilsButton`, `NilsCard`, `NilsRow`, ...) are names left from an earlier version. They are not a backend reference.
- `flutter_secure_storage` keys its keyring entry by the application ID (`<APPLICATION_ID>.secureStorage`). Changing `APPLICATION_ID` in `linux/CMakeLists.txt` orphans any saved key.

## Architecture

Imports run `ui -> core <- adapters`. `lib/main.dart` is the only file that knows both sides. `test/layers_test.dart` enforces this with substring checks on import targets:

| Layer | May not import |
| --- | --- |
| `lib/core` | Flutter, `dart:io`, `dart:ui`, `http`, `flutter_secure_storage`, `file_selector`, `desktop_drop`, `ui`, `adapters` |
| `lib/adapters` | Flutter, `dart:ui`, `file_selector`, `desktop_drop`, `ui` |
| `lib/ui` | `dart:io`, `http`, `flutter_secure_storage`, `adapters` |

**Core** holds the ports (`core/ports.dart`: `AnythingLlmApi`, `SettingsStore`), the server models (`core/server_models.dart`), and the use cases (`core/documents.dart`, `core/upload.dart`). Every failure is an `ApiException(message, {status})`. `NotConfigured` is the subtype thrown when no server is set up. Use `both()` from `core/futures.dart` to run two calls at once. The record `.wait` wraps errors in `ParallelWaitError`, which breaks the `on ApiException` handlers.

**The connection** lives in one shared `ConnectionHolder`, built in `main.dart`. `HttpAnythingLlmApi` reads it on every call, so a saved connection takes effect without a restart. `SettingsController` is the only writer, through `load`, `save` and `clear`, which notify listeners. `UploadController` resets its state when the holder's connection changes. `verify(Connection)` takes an explicit connection so Settings can test one before saving.

**Adapters:**

- `adapters/anythingllm_client.dart` maps HTTP failures to plain-language `ApiException`s. No message may contain the key; a test asserts this, and `Connection.toString` omits it.
- `adapters/keyring_settings_store.dart` stores the address and key as one JSON keyring entry.

**AnythingLLM API facts the client relies on:**

- `GET /v1/workspace/{slug}` answers `workspace` as a one-item array.
- `GET /v1/document/{docName}` strips `pageContent`, and no route returns document text. The document page therefore shows metadata only.
- Which workspaces hold a document comes from each workspace's `documents[].docpath`, not `pinnedWorkspaces`. That costs one call per workspace.
- `published` is a locale string, shown as given. `"Unknown"` is a server placeholder, read as absent.
- An upload can answer HTTP 200 with `success: false`.

**UI:**

- `ui/app_scope.dart` is an `InheritedWidget` that never notifies. Widgets wrap the controller they read in a `ListenableBuilder`, and `AppScope.of` is safe in `initState`.
- Navigation is a sealed `AppRoute` in `ui/state/nav_controller.dart`. `navEntries` feeds both the sidebar and the phone tab bar. `pageFor` in `ui/pages/router.dart` is an exhaustive switch, and it wraps every route whose `needsServer` is true in `ConnectionGate`, which points to Settings until a server is set up.
- The gate keys its child by the connection, so pages rebuild against a new server. The shell keys each page by its route, so every visit refetches.
- Pages load through `LoadPage` (`ui/pages/page_frame.dart`), which caches its future and shows the error message on failure. Long lists use `LoadPage.slivers` with `SliverListSection` so only visible rows build. `LibraryList` is the searchable, grouped list with one facet filter.
- `main.dart`'s `SessionHost` awaits the keyring read. It then opens on Workspaces, or on Settings when nothing is saved.

## Tests

- `test/support/pump.dart`: `pumpApp(tester, {llm, store, connection, size, route})` builds the whole shell. Without `connection`, no server is set up and section pages show the gate.
- `test/support/fake_api.dart`: `FakeAnythingLlm` answers from its `*Value` fields. It records calls in `calls` as `name` or `name:arg`, and fails a method when `errors['methodName']` is set. `sampleConnection`, `sampleDoc` and `documentServer()` are shared fixtures.
- `test/ui/responsive_test.dart` pumps every route at 1400, 780, 500 and 360 px wide, with long unbroken strings, and fails on any overflow. 360x480 is the window's minimum size (`linux/runner/my_application.cc`). Add new routes to its map.

## Conventions

- Dependencies in `pubspec.yaml` are pinned by series (`">=1.6.0 <1.7.0"`). Moving to a newer series is a deliberate edit.
- Doc comments state what a thing is or does, in plain sentences, with `[name]` references. Match that density in new code.
