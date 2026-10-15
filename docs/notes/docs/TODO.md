# Notes on docs/TODO.md: a machine for the agent

Evidence and reasoning behind the TODO row "A machine for the agent", from the discussion of 2026-10-15. The idea is shelved; nothing was built or changed on owen.

## The question

Could the sandbox of `anythingllm-mcp` (owen:`~/dev/anythingllm-mcp`, branch `roles`) always run, to handle background tasks and hosting?

## What the sandbox does today

- **The server is not a daemon.** systemd starts one process per connection through a socket unit and it exits afterwards. That stays.
- **A job** (`sandbox_start`) is a detached rootless podman container with no time limit by default. Podman is its only record, so a job outlives the server process. An ended job is removed after a day.
- **Four gaps for hosting:** no inbound path (the network is `none` or the internal one behind the egress proxy), no restart after a crash or reboot, the day-long clean-up, and a job holds its workspace so the agent cannot edit files while it runs.

## How the idea changed

1. **A `service` kind in `sandbox_mcp`.** A job-like container that restarts (a Quadlet unit from a fixed template), with five tools, `/work` read-only, and reachability granted by the person through `access approve`. Private first (tailnet only), public through Caddy later. Rootless podman cannot publish a port from an internal network, so a forwarder container on both networks was needed.
1. **A separate machine.** The user asked for more freedom: a full but underpowered remote personal computer, with wide internet, installable network tools and no reach into the rest of owen. That moves the safety boundary from what the agent may do inside to what the machine can reach and break from outside. Systemd inside the machine replaces the service tools, and a tagged Tailscale node replaces the forwarder. The user chose a new tool set beside the sandbox, so the sandbox is untouched and the agent has two models to choose from.

## Settled

| Decision | Reason |
| --- | --- |
| A new `machine_mcp` package, not a change to `sandbox_mcp` | The trust model differs. Servers may not import each other, and the shared-security-code argument for one server no longer held. Cost: more tools for the agent to choose among |
| Rootless podman only, no VM, no sudo | `diot` cannot open `/dev/kvm`, and installing qemu needs root. Software emulation without KVM is roughly 10 to 50 times slower |
| Container root mapped to a subuid range (`--uidmap 0:1:65536`) | A mount-level escape lands as a nobody, not as `diot`. Not yet verified on owen |
| An IP-level gateway container that drops RFC 1918, link-local, `100.64/10`, host loopback and IPv6 private ranges | The egress proxy only handles HTTP, so ssh and tailscale cannot pass it. The filter must live where the machine's root cannot edit it. Not yet tested rootless with pasta (`--no-map-gw`) |
| Tailscale as a tagged, ephemeral node (`tag:sandbox`) with an ACL, no Funnel | The ACL is enforced outside the machine. The user creates the auth key, so the agent never holds a credential |
| Open public internet, a malware-blocking resolver, logging, a bandwidth cap and a kill switch | Wide access was asked for. DNS filtering is a tripwire, since the agent can connect to an IP directly |
| The panel was skipped | The user declined it |

## Rejected

- **Hosting in the sandbox's service kind.** Superseded by the machine.
- **A third-party whitelist.** Microsoft publishes endpoint and IP lists for its own services, and the Azure ranges include anyone's rented VMs. Popularity lists such as Tranco rank traffic, not safety. A reputable site is still an exfiltration channel (GitHub, pastebin, Discord webhooks, cloud storage). Not checked against current offerings.
- **Blocking the agent from setting up a VPN.** True under the HTTP-only proxy, where a tunnel would bypass the control. Under the IP-level fence the tunnel is the intended path, so the objection fell away.
- **A separate host user.** It needs sudo. With the uid mapping, most of its benefit remains.
- **A VM now.** It needs the `kvm` group, so sudo. It stays the stronger later option.
- **QEMU without KVM.** Works, too slow to use.
- **Public hosting first.** LAN exposure is worse than the tailnet, so tailnet only.

## Checked on owen, 2026-10-15 (read only)

- Podman 5.4.2 rootless, crun, netavark, `pasta` installed, cgroup v2.
- The user's cgroup controllers are `cpu memory pids`. No I/O controller, so no disk-I/O limit.
- `/dev/net/tun` is world-writable. `/dev/kvm` is root:kvm, and `diot` is not in the group.
- Subuid range `diot:100000:65536`. Root filesystem is ext4 with 308 GB free, so no per-container disk quota.
- 4 cores (i5-6500T), 15 GB RAM. Tailscale is installed and owen is `100.89.16.22`. Linger is on. qemu and incus are not installed.

## Risks the fence does not cover

- **Internet abuse from the home IP.** Scanning, spam or mining would be attributed to the user.
- **Prompt injection.** A page the agent reads can steer a root agent with internet access. Keep no secrets in the machine, and keep exports on the destination flow.
- **Shared kernel.** A kernel or runtime bug in rootless podman is the residual escape path. gVisor (`runsc`, a downloaded binary registered as an OCI runtime) would narrow it, at the cost of compatibility.
- **`AGENT_AUTO_APPROVED_SKILLS`** is on for testing. It should be off for the machine tools before they go live.

## Ease of use

A host needs rootless podman 5 with `pasta`, a subuid range of 65536 or more, cgroup v2 with `cpu`, `memory` and `pids` delegated, and linger. Over plain ssh, enabling linger may need an admin. A `setup` command would check these, print the exact fix for any that is missing, then pull the image, create the networks and gateway, write the units and start the machine. After that comes one reload of AnythingLLM's MCP servers. Tailscale hosting stays manual: the ACL tag and the auth key. Approvals are terminal-only today, which misses the no-terminal bar for Muse users, so a later step would put setup on the toolkit's installer page and a kill switch, snapshot and restore on a Lite settings page.

## Open

- Does gVisor run systemd, apt and tailscale rootless on owen?
- Does the private-range filter work in a rootless gateway with pasta?
- Is a hard disk quota possible through an ext4 image mounted with `fuse2fs`?
- Whether the CLI comes first or the installer and Lite pages ship with it.

## Edit AnythingLLM's native agent memory

Requested on 2026-10-15 as "RAG memory deletion, adding, and rewriting ... expose those tools in toolkit", and clarified the same day: AnythingLLM has a native memory skill and the user wants the agent to be able to change it.

Read from AnythingLLM 1.16.2's source (`/app/server/utils/agents/aibitat/plugins/memory.js`, skill name `rag-memory`):

- **Actions:** `search` runs a similarity search in the workspace's vector namespace (`workspace.topN`, or 4). `store` calls `addDocumentToNamespace` with a fresh `docId`, the title `agent-memory.txt`, the author `@agent` and the text as `pageContent`.
- **No handle:** the `docId` is not returned to the agent or saved anywhere the app can list, and no `workspace_documents` row is made. The Documents sheet and `update-embeddings` therefore never see these memories.
- **Gap:** there is no delete or rewrite action. A rewrite would be a delete of the old vectors plus a store.

Two ways to build it, neither tried:

| Route | Shape | Catch |
| --- | --- | --- |
| A skill inside AnythingLLM | Like the lean skills: it would call the vector database client directly | The lean skills ship as Hub zips and have only what AnythingLLM hands a skill; whether that includes the vector client is unchecked |
| A route behind the bridge | The toolkit passes an internal `/api` route and an MCP role wraps it, as chat and schedule do | No `/v1` or `/api` route found so far deletes vectors by `docId`; saved memories (`/memories`) are a different store |

Not this: AnythingLLM's saved memories (the Memory page in Lite, `/memories`) can already be changed through the bridge, and anythingllm-mcp's own `memory` server already has remember, update and forget.

## In-app feedback

Requested on 2026-10-15 without saying which kind. Read from AnythingLLM 1.16.2's source: `POST /workspace/:slug/chat-feedback/:chatId` (`endpoints/workspaces.js`) takes `{feedback}`, is behind `validatedRequest`, and answers 404 unless the chat belongs to the workspace and user, so the developer key cannot call it. Through the bridge it needs one rule. The app's CLAUDE.md already records that an answer cannot be rated for this reason.

## Several chats answering at once in one workspace

Requested on 2026-10-15. The app's guard is `_runs`, one `_Running` per workspace. Its recorded reason is that AnythingLLM gives an agent run no thread of its own. Source of 1.16.2 says otherwise for both paths: `WorkspaceAgentInvocation.new` stores `thread_id`, and `apiChatHandler.js` builds an `EphemeralAgentHandler` with `threadId: thread?.id`. Whether two agent runs in one workspace share state (a browser profile in browser-lean is kept per workspace, and the sandbox holds a workspace's folder) was not checked, and it decides whether the limit belongs to the server, the skills or only the app.
