# AnywhereLLM

A lightweight chat client for an AnythingLLM server, for Android phones. Ask questions in a workspace and get answers drawn from the files you add to it.

**This is the `lite-stock` branch**, a build for plain, unmodified AnythingLLM: it talks to AnythingLLM's own developer API only, with none of the toolkit (anywherellm-bridge) or suite features of `master` (no Memory, Upcoming, skill pages or agent's browser). It installs beside Lite as `local.anywherellm.lite.stock`, labelled **Lite (stock)**, version `1.19.3-stock`.

## What it does

The app talks only to the AnythingLLM server you set up in Settings, through AnythingLLM's own API, over https.

| Part | What it does |
| --- | --- |
| Drawer | Switches workspaces, searches chats, starts a new chat, and lists the open workspace's chats, pinned ones first. **Settings** sits at its foot. |
| Chat | Shows the open chat. Answers stream in, and **Stop** ends one early. Chips under an answer name the files and pages it used; tap one to see the passages read or the file in Documents. Attach photos or files to a message, dictate it, and have answers read aloud. |
| Documents | Lists the open workspace's files. Add a file, a link or pasted text. A switch takes a file out of answers without forgetting it. The trash removes a file, with a few seconds to undo. |
| Workspace pages | The workspace's documents, its instructions, and **Answer from**: whether answers may use tools such as web search, general knowledge and the files, or the files only, and which chat model answers, which AnythingLLM's own web page changes. |
| Settings | Holds the server address, the developer API key the app gets from the server, and the server's password, which a QR code can fill in. It also shows the server's AI providers and switches its chat model. A connection is saved only once the server accepts it. |

Until a server is saved, the app opens with Settings showing. Other apps can share links, text and files into AnywhereLLM.

**How the Documents switch works.** AnythingLLM has no per-file switch, so turning a file off takes it out of the workspace on the server. The app remembers it, so it stays listed and can be turned on again. Removing a file takes it out of the workspace; the file stays in AnythingLLM's document library.

## Where things are kept

| What | Where |
| --- | --- |
| Server address, API key and password | One entry encrypted with the Android Keystore, through `flutter_secure_storage`. No error message shows the key or the password. |
| The switched-off files, pins and other preferences | `prefs.json` in the app's own storage. Nothing secret. |
| Workspaces, chats and files | The AnythingLLM server. |

## Requirements

- Flutter 3.47 and the Android SDK.
- An AnythingLLM server reachable over https. A multi-user server also needs an API key created under Settings, Developer API in AnythingLLM.

## Run

```bash
flutter pub get
flutter run -d <android-device>     # a phone over adb, or an emulator
flutter build apk --debug           # -> build/app/outputs/flutter-apk/app-debug.apk
```

Settings opens on the first run. Enter the server address (for example `https://host.example.ts.net:3001`) and the server's password, or leave the password empty if the server has none, then press **Sign in**. The app makes its own developer API key, named `AnywhereLLM`, on the server. A multi-user server asks for a key instead, and **Paste a key** takes a key you made.

A release build (`flutter build apk --release`) needs `android/key.properties`, which names the signing key.

## Check

```bash
flutter analyze
flutter test        # fakes the server, the keyring and the preferences file
```
