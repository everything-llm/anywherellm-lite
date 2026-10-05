# everything

A Linux viewer and filer for the nils research and skills libraries, and the place that holds how AnythingLLM talks to them.

## What it does

- Browses the research and skills libraries, with the findings of their last check.
- Stages markdown files into the inbox.
- Files nothing into a library. That is done in AnythingLLM, through the nils tools.

It has no server, no model and no key. It runs the `nils` command in a checkout of the nils repository, one process per read: `nils view ...` to read and `nils inbox add` to stage.

## Requirements

- Flutter 3.47 on Linux.
- A checkout of nils with `uv sync` done. The app finds it from `NILS_REPO`, else above the working directory and the executable, else in a sibling directory named `nils`.

## Run

```bash
flutter pub get
NILS_REPO=/path/to/nils flutter run -d linux
```

## Check

```bash
flutter analyze
flutter test                      # fakes the nils process
flutter test --tags live          # runs the real nils; reads only
```

## AnythingLLM

AnythingLLM holds the model and the key. It starts `nils mcp` as a child process and calls the nils tools through it.

1. Add nils to `anythingllm_mcp_servers.json` in AnythingLLM's `plugins` storage directory:

   ```json
   {
     "mcpServers": {
       "nils": {
         "command": "uv",
         "args": ["run", "--directory", "/path/to/nils", "nils", "mcp"],
         "env": {}
       }
     }
   }
   ```

1. Create a workspace, turn on agent mode in it, and paste the text of `storage/PROMPT.md` from the nils checkout as its system prompt.

1. Stage a file here, then ask the workspace to file it.

A commit tool writes to a library. The prompt tells the model to wait for a yes, and AnythingLLM's own tool-call confirmation is a setting of AnythingLLM. Neither this app nor nils can force a person to be asked.
