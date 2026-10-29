# The launcher icon, RX1

Shane's launcher icon RX1 (2026-10-29): a white robin with an orange breast on an indigo tile.
These are its sources; the app does not bundle them.

| File | What it is |
| --- | --- |
| `anywherellm-icon.svg` | The 1024 px master tile, gradient #4150C4 to #262E8E. The legacy launcher icons, `android/app/src/main/res/mipmap-*dpi/ic_launcher.png` (48 to 192 px, for Android 7), are rendered from it. |
| `play-icon-512.png` | The 512 px store icon, full square, no rounding or shadow. |

The Android vectors came with the same pack and are used as they came:
`mipmap-anydpi-v26/ic_launcher.xml` and `ic_launcher_round.xml` (the adaptive icon), and in
`drawable/` `ic_launcher_foreground.xml`, `ic_launcher_monochrome.xml` (the themed icon),
`ic_launcher_background.xml` (flat #343FA9; `drawable-v24/` has the gradient),
`splash_robin.xml` (the launch screen's robin on #343FA9) and `ic_notification.xml` (the pack's
`ic_stat_robin.xml`, one colour so the system tints it).
