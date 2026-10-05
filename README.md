# Nilson

A lightweight Linux front end for an AnythingLLM server: browse its workspaces and documents, and upload files to it.

## What it does

The app talks only to the AnythingLLM server you set up in Settings, through AnythingLLM's developer API.

| Section | Shows |
| --- | --- |
| Workspaces | Each workspace with its slug, chat model and thread count. Open one to list its documents. |
| Documents | Every document the server has read in, grouped by folder, with search and a folder filter. Open one to see its details and which workspaces hold it. |
| Upload | Drop or pick files to send into a folder you choose. Files of a type the server does not read are refused before they are sent. |
| Settings | The server address and API key, with a connection test. |

Until a server is set up, the app opens on Settings and the other sections point there.

**What it leaves to AnythingLLM:**

- **Chat.** There is none in this app.
- **Document text.** AnythingLLM's API does not return it, so a document page shows its details only.
- **Adding a document to a workspace.** Uploaded files land in a folder; add them to a workspace in AnythingLLM.

## Where the key lives

The address and the API key are kept together in one entry in the system keyring, through `flutter_secure_storage`. No file in the project or in `~/.config` holds them, and no error message shows the key.

If the keyring cannot be read or written, the app still starts, uses what you entered for that run, and says so on the Settings page.

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

Then open Settings, enter the server address (for example `https://host.example.ts.net:3001`) and the key, press Test connection, then Save.

## Check

```bash
flutter analyze
flutter test        # fakes the server and the keyring
```
