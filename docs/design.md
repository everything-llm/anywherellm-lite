# The design source

The app's look is drawn in the AnywhereLLM Lite prototype at <https://claude.ai/artifact/XTJJTtc2x8aN4zB2fVPsBT>. The owner proposes style changes there, and the app is built from it.

The earlier Design canvas at <https://claude.ai/artifact/VwYwfCQ2jLNQsYfojqfiGo> is retired. Do not read it or edit it.

## Who can read it

The prototype is private to the owner's claude.ai account. Only Claude Code, signed in as the owner, can read it, through its Artifact tool: `read` with the URL saves the whole page to a file. Cline, a web fetch, curl and a headless browser all get a sign-in page or a refusal.

An agent without that tool does not guess at design changes. It stops and asks the owner to have Claude Code in this repository read the prototype and apply the changes.

Requests that work, said to Claude Code:

- "Read the Lite prototype and apply my changes to the app."
- "Draw this proposal in the Lite prototype."

The prototype is one HTML page: a 390 by 844 phone screen, its colour tokens as CSS variables on `:root` with the dark values under `prefers-color-scheme` and `data-theme`, and its screens, sheets and guides drawn by the script below them. Other sessions edit it too, so read it afresh before building from an earlier copy.

The style rules the prototype and the app's guides follow are in the Mobile Design pager at <https://claude.ai/artifact/NxTpZ7bciKv3AKtBzSC53v>.

## How the prototype maps to the code

| In the prototype | In the code |
| --- | --- |
| CSS variable `--name` under `:root` and its dark overrides | The `Tokens` field of the same name in `lib/ui/tokens.dart`, `Tokens.light` or `Tokens.dark`; `oklch(L C H / A)` is `oklch(L, C, H, A)` |
| `--sans`, `--mono`, `font-size` and line height | `lib/ui/type.dart` and the size passed at each call |
| Radii, row heights, page padding | `Sizes` in `lib/ui/layout.dart` |
| `.hd` chat header, `.q` and `.a` turns, `.chip` citations | `lib/ui/chat/chat_view.dart`, `lib/ui/chat/message_list.dart`, `lib/ui/chat/answer_body.dart` |
| `.comp` composer | `lib/ui/chat/composer.dart` |
| `.hd2` page header, `.card`, `.rowb`, `.grp` | `lib/ui/widgets/phone_page.dart`, `lib/ui/settings/rows.dart` |
| `.sheet`, `.scrim` | `lib/ui/widgets/sheet.dart` |
| `.how` guides | `lib/ui/settings/walkthrough.dart`, `lib/ui/settings/guide_figures.dart` |
| Settings pages | `lib/ui/settings/settings_dialog.dart` (the frame and the list), `settings_pages.dart` (the pages), and a file per page in `lib/ui/settings/` |
| Documents sheet | `lib/ui/sources/sources_panel.dart` |
| Buttons, fields, segmented control, switch, badge | `lib/ui/widgets/buttons.dart`, `fields.dart`, `segmented.dart`, `controls.dart`, `basics.dart` |
| Icons, as inline SVG paths | `lib/ui/icons.dart`, the same paths |

Where the prototype is silent, `lib/ui` is the source of truth. A screen the prototype draws that the app does not build is listed in `docs/TODO.md`.
