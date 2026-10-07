# The AnywhereLLM design canvas

The app's look is mirrored in a Claude Design canvas at <https://claude.ai/artifact/VwYwfCQ2jLNQsYfojqfiGo>, pinned in the owner's claude.ai sidebar. The owner proposes style changes there. Claude Code built it by hand from `lib/ui` at commit 238c2e1 on 2026-10-07; it was not compared with the running app pixel for pixel.

## Who can read it

The canvas is private to the owner's claude.ai account. Only Claude Code, signed in as the owner, can read it, through its Artifact tool. Cline, a web fetch, curl and a headless browser all get a sign-in page or a refusal.

An agent without that tool does not guess at design changes. It stops and asks the owner to have Claude Code in this repository read the canvas and either apply the changes or write the artboards into the repository. No copy of the canvas is in the repository until one is written that way, and a copy is current only as of the sync that wrote it.

Requests that work, said to Claude Code:

- "Read the design canvas and apply my changes to the app."
- "Sync the design canvas into `design/`." Claude Code writes each artboard as a `.dc.html` file, which another agent can then read as plain HTML and CSS.

## What it holds

| Artboard | Shows |
| --- | --- |
| `Main.dc.html`, Desktop chat, light | 1440 x 900: sidebar, chat with two answered questions, composer, Sources panel |
| `Dark.dc.html`, Desktop chat, dark | `Main.dc.html` imported with the dark theme; it has no markup of its own |
| `Phone.dc.html` | 390 x 844: a new chat's empty state, with the microphone |
| `Settings.dc.html` | 640 x 980: a single-column Settings dialog over the scrim, which the app does not draw; `DesktopSettings.dc.html` is the one built |
| `DesktopSettings.dc.html` | 1440 x 900, clickable: the full Settings over `Main.dc.html`, a 980 px dialog with 26 sections in 7 groups following AnythingLLM's own settings, from Claude Design's "Plain" mockup; each section is tagged with what it needs on the server (this device, developer key, key and password, or server password), from `docs/notes/settings-api-coverage.md`; the `page` tweak picks the section shown and `showAccess` hides the tags. The app's Settings in `lib/ui/settings/` is built from it, with the 13 pages that this device and the developer key reach |
| `Components.dc.html` | Every colour token in both themes, the type scale, buttons, fields, switches, badges, citations and alerts |

The sample data is `planningServer()` from `test/support/fake_api.dart`, plus invented answers, word counts, metrics and a server address.

## How the canvas maps to the code

| In the canvas | In the code |
| --- | --- |
| CSS variable `--name` under `.t-light` or `.t-dark` | The `Tokens` field of the same name in `lib/ui/tokens.dart`, `Tokens.light` or `Tokens.dark`; `oklch(L C H / A)` is `oklch(L, C, H, A)` |
| `font-family` and `font-size` | `lib/ui/type.dart` (`Type.sans`, `Type.serif`, `Type.mono`) and the size passed at each call |
| Panel widths 264 and 312, column 720, radii 16 and 10 | `Sizes` in `lib/ui/layout.dart` |
| Sidebar | `lib/ui/sidebar.dart`, `lib/ui/widgets/settings_button.dart` |
| Chat header, turns, citations, answer buttons | `lib/ui/chat/chat_view.dart`, `lib/ui/chat/message_list.dart`, `lib/ui/chat/answer_body.dart` |
| Composer | `lib/ui/chat/composer.dart` |
| Sources panel | `lib/ui/sources/sources_panel.dart`, `lib/ui/widgets/drop_zone.dart` |
| Settings (`DesktopSettings.dc.html`) | `lib/ui/settings/settings_dialog.dart` (the frame and the list), `settings_pages.dart` (the pages and groups), `rows.dart` (cards and rows), and a file per page in `lib/ui/settings/`; widths in `Sizes.settingsSideBySide` and `Sizes.settingsNav` |
| Buttons, fields, segmented control, switch, badge, alert | `lib/ui/widgets/buttons.dart`, `fields.dart`, `segmented.dart`, `controls.dart`, `basics.dart` |
| Icons, as inline SVG paths | `lib/ui/icons.dart`, the same paths |

Each artboard except `Dark.dc.html` carries its own copy of the colour variables, so a colour changed on one artboard is not changed on the others. When artboards disagree, ask the owner which one is meant. Where the canvas is silent, `lib/ui` is the source of truth.
