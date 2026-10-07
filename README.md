# AnywhereLLM

A lightweight chat client for an AnythingLLM server, for Linux, Android and Chrome. Ask questions in a workspace and get answers drawn from the files you add to it.

## What it does

The app talks only to the AnythingLLM server you set up in Settings, through AnythingLLM's developer API.

| Part | What it does |
| --- | --- |
| Sidebar | Lists your workspaces and how many files each holds. The open workspace lists its chats. Make a workspace with **+**, start a chat with **New chat**, and rename (pencil, or double-click) or delete (trash) the open chat. |
| Chat | Shows the open chat. Enter sends and Shift+Enter starts a new line. Answers stream in, and **Stop** ends one early. Numbered chips under an answer name the files it used; click one to find the file in Sources. Only one answer runs at a time. |
| Sources | Lists the open workspace's files. Drop files on the panel, or click it to browse; they are uploaded and added to the workspace. **Chat mode** under the heading sets how the workspace answers: **Agent** may use tools such as web search, **Chat** answers from general knowledge and the files, and **Query** answers only from the files. A switch takes a file out of answers without forgetting it. The trash removes a file, with a few seconds to undo. |
| Settings | Holds the server address, the developer API key the app gets from the server, and the server's password. A connection is saved only once the server accepts it. |

Until a server is saved, the app opens with Settings showing, and the composer points there.

**How the Sources switch works.** AnythingLLM has no per-file switch, so turning a file off takes it out of the workspace on the server. The app remembers it, so it stays listed and can be turned on again. Removing a file takes it out of the workspace; the file stays in AnythingLLM's document library.

## Where things are kept

| What | Where |
| --- | --- |
| Server address, API key and password | One entry in the system keyring, through `flutter_secure_storage`. In Chrome it is the page's local storage, encrypted with a key kept beside it. No error message shows the key or the password. |
| The switched-off files | `~/.config/anywherellm/prefs.json`, or under `$XDG_CONFIG_HOME` when set. In Chrome, the page's local storage. Nothing secret. |
| Workspaces, chats and files | The AnythingLLM server. |

If the keyring cannot be read or written, the app still starts, uses what you entered for that run, and says so in Settings.

## Requirements

- Flutter 3.47.
- `libsecret-1-dev`, for building: `sudo apt install libsecret-1-dev`.
- A running, unlocked secret service, such as gnome-keyring, for saving the key.
- An AnythingLLM server. A multi-user server also needs an API key created under Settings, Developer API in AnythingLLM.

## Run

```bash
flutter pub get
flutter run -d linux
flutter run -d chrome
```

In Chrome the server must allow requests from the page's origin; AnythingLLM does. Serve a built app (`flutter build web`, then `build/web`) over https or from localhost, since the browser keeps the key only there.

Settings opens on the first run. Enter the server address (for example `https://host.example.ts.net:3001`) and the server's password, or leave the password empty if the server has none, then press **Sign in**. The app makes its own developer API key, named `AnywhereLLM`, on the server. A multi-user server asks for a key instead, and **Paste a key** takes a key you made.

## Install on Linux

A release build installs into your home folder, so it needs no `sudo`. It keeps the saved server and preferences that `flutter run -d linux` uses, since both have the application ID `local.anywherellm.anywherellm`.

The build takes the working tree as it is, uncommitted changes included. To build the last commit alone, build it in a separate worktree:

```bash
git worktree add ../anywherellm-release HEAD &&   # or a tag
cd ../anywherellm-release &&
flutter pub get
```

If `../anywherellm-release` is left from an earlier install, remove it first with `git worktree remove ../anywherellm-release`.

Then quit AnywhereLLM if it is running, and from the folder you build in, build the app and copy it into place. The commands stop at the first failure, and the old install is replaced only once the new one is built and copied:

```bash
(
set -e
arch=$(uname -m | sed 's/^x86_64$/x64/; s/^aarch64$/arm64/')
flutter build linux --release
mkdir -p ~/.local/opt ~/.local/bin ~/.local/share/applications
rm -rf ~/.local/opt/anywherellm.new
cp -r "build/linux/$arch/release/bundle" ~/.local/opt/anywherellm.new
cp assets/icon/icon.png ~/.local/opt/anywherellm.new/icon.png
rm -rf ~/.local/opt/anywherellm
mv ~/.local/opt/anywherellm.new ~/.local/opt/anywherellm
ln -sf ~/.local/opt/anywherellm/anywherellm ~/.local/bin/anywherellm
cat > ~/.local/share/applications/local.anywherellm.anywherellm.desktop <<EOF
[Desktop Entry]
Type=Application
Name=AnywhereLLM
Comment=Chat with an AnythingLLM server
Exec="$HOME/.local/opt/anywherellm/anywherellm"
Icon=$HOME/.local/opt/anywherellm/icon.png
Terminal=false
Categories=Network;Chat;
StartupWMClass=local.anywherellm.anywherellm
EOF
)
```

AnywhereLLM then shows in the app launcher. The desktop file is named after the application ID so the open window groups under its launcher icon. Run the same commands again to update it.

`anywherellm` starts it from a terminal when `~/.local/bin` is on your `PATH`. On Debian and Ubuntu, `~/.profile` adds that folder at login only if it already exists, so log in again after the first install.

Do not run the installed app while `flutter run -d linux` runs. Both write the whole preferences file, so whichever saves last undoes the other's changes.

Remove the worktree once the app is installed, if you made one: `git worktree remove ../anywherellm-release`.

To uninstall:

```bash
rm -rf ~/.local/opt/anywherellm ~/.local/opt/anywherellm.new ~/.local/bin/anywherellm ~/.local/share/applications/local.anywherellm.anywherellm.desktop
```

Uninstalling leaves the saved server in the keyring and the preferences in `anywherellm` under `$XDG_CONFIG_HOME`, or in `~/.config/anywherellm` when it is not set.

## Check

```bash
flutter analyze
flutter test        # fakes the server, the keyring and the preferences file
```
