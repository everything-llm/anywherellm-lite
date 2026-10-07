# AnywhereLLM

A lightweight Linux chat client for an AnythingLLM server. Ask questions in a workspace and get answers drawn from the files you add to it.

## What it does

The app talks only to the AnythingLLM server you set up in Settings, through AnythingLLM's developer API.

| Part | What it does |
| --- | --- |
| Sidebar | Lists your workspaces and how many files each holds. The open workspace lists its chats. Make a workspace with **+**, start a chat with **New chat**, and rename (pencil, or double-click) or delete (trash) the open chat. |
| Chat | Shows the open chat. Enter sends and Shift+Enter starts a new line. Answers stream in, and **Stop** ends one early. Numbered chips under an answer name the files it used; click one to find the file in Sources. Only one answer runs at a time. |
| Sources | Lists the open workspace's files. Drop files on the panel, or click it to browse; they are uploaded and added to the workspace. **Chat mode** under the heading sets how the workspace answers: **Agent** may use tools such as web search, **Chat** answers from general knowledge and the files, and **Query** answers only from the files. A switch takes a file out of answers without forgetting it. The trash removes a file, with a few seconds to undo. |
| Settings | Holds the server address and API key. A key is saved only once the server accepts it. |

Until a key is saved, the app opens with Settings showing, and the composer points there.

**How the Sources switch works.** AnythingLLM has no per-file switch, so turning a file off takes it out of the workspace on the server. The app remembers it, so it stays listed and can be turned on again. Removing a file takes it out of the workspace; the file stays in AnythingLLM's document library.

## Where things are kept

| What | Where |
| --- | --- |
| Server address and API key | One entry in the system keyring, through `flutter_secure_storage`. No error message shows the key. |
| The switched-off files | `~/.config/anywherellm/prefs.json`, or under `$XDG_CONFIG_HOME` when set. Nothing secret. |
| Workspaces, chats and files | The AnythingLLM server. |

If the keyring cannot be read or written, the app still starts, uses what you entered for that run, and says so in Settings.

## Requirements

- Flutter 3.47 on Linux.
- `libsecret-1-dev`, for building: `sudo apt install libsecret-1-dev`.
- A running, unlocked secret service, such as gnome-keyring, for saving the key.
- An AnythingLLM server and an API key created under Settings, Developer API in AnythingLLM.

## Run

```bash
flutter pub get
flutter run -d linux
```

Settings opens on the first run. Enter the server address (for example `https://host.example.ts.net:3001`) and the key, then press Save key.

## Check

```bash
flutter analyze
flutter test        # fakes the server, the keyring and the preferences file
```
