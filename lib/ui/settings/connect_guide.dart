import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/phone_page.dart';
import '../widgets/rise.dart';
import '../widgets/side_scroll.dart';
import '../widgets/tappable.dart';
import 'guide_figures.dart';
import 'rows.dart';

/// One screen of the guide: a [kicker] over a picture, a block of code or a numbered list, and
/// what it [says], whose words between asterisks are in the accent; a [hero] screen says it
/// large, over [sub].
class GuideStep {
  const GuideStep(
    this.kicker,
    this.says, {
    this.hero = false,
    this.sub,
    this.art,
    this.code,
    this.lines = const [],
  });

  final String kicker;
  final String says;
  final bool hero;
  final String? sub;
  final GuideArt? art;

  /// Lines of a terminal: a line starting `#` is a comment, one starting `~` is muted output
  /// shown without its `~`, and words between `[` and `]` are marked.
  final List<String>? code;

  /// A numbered list, each a name over a detail in the mono face.
  final List<(String, String)> lines;
}

/// How connecting works: one idea a screen, from the key and the address to the pairing code
/// and the add-ons.
const connectSteps = [
  GuideStep(
    'Getting connected',
    'Your phone, *your* AnythingLLM.',
    hero: true,
    sub: 'Bring two things: where the server is, and a key it trusts.',
    art: GuideArt.hero,
  ),
  GuideStep(
    'Step 1 · A key',
    'In AnythingLLM\'s web page, open Settings, Developer API, and Generate New API Key. '
        'It is all the app signs in with.',
    art: GuideArt.key,
  ),
  GuideStep(
    'Step 2 · An address',
    'Where the phone finds the server. Use the tool you already know.',
    lines: [
      ('Same Wi-Fi', 'http://192.168.1.20:3001'),
      ('Tailscale', 'https://box.tail1234.ts.net'),
      ('Cloudflare Tunnel', 'https://ai.example.com'),
      ('Your own proxy', 'Caddy or nginx, with https'),
    ],
  ),
  GuideStep(
    'Why https away from home',
    'The key goes with every request. On your own network plain http is fine. Across the '
        'internet it would travel in the clear, so the app asks for https.',
    art: GuideArt.safe,
  ),
  GuideStep(
    'Step 3 · Scan',
    'If the toolkit runs on the server, its pair command prints a code holding the address '
        'and a key. Scan it and you are in.',
    code: [
      '# on the server',
      '\$ anythingllm-toolkit pair',
      '~  Scan this with the phone:',
      '  ▇▇▇ ▇ ▇▇ ▇▇▇',
      '  ▇ ▇ ▇▇ ▇ ▇ ▇',
      '  ▇▇▇ ▇ ▇▇ ▇▇▇',
      '',
      'anywherellm://connect',
      '  ?url=[https://ai.example.com]',
      '  &key=…&toolkit=…',
    ],
  ),
  GuideStep(
    'Optional · Add-ons',
    'The apps server and the toolkit add Apps, Memory and Upcoming. Each can have an address '
        'of its own. Without them, the rest works.',
    art: GuideArt.addOns,
  ),
  GuideStep(
    'Ready',
    'Scan the code, or type the address and key.\n\n*That is all.*',
  ),
];

/// The guide to connecting, over the whole window: Previous, its title and which screen of
/// how many, and Close; a mark for each screen, which goes to it; the screens, swiped or
/// stepped with the arrow keys; and a button for the next screen, on the last [end], which
/// [onEnd] does, with [endAbout] under it.
class ConnectGuide extends StatefulWidget {
  const ConnectGuide({
    super.key,
    required this.onClose,
    required this.end,
    required this.endAbout,
    required this.onEnd,
  });

  final VoidCallback onClose;
  final String end;
  final String endAbout;
  final VoidCallback onEnd;

  @override
  State<ConnectGuide> createState() => _ConnectGuideState();
}

class _ConnectGuideState extends State<ConnectGuide> {
  final _pages = PageController();
  int _at = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int to) {
    final next = to.clamp(0, connectSteps.length - 1);
    if (next == _at) return;
    _pages.animateToPage(
      next,
      duration: motion(context, const Duration(milliseconds: 280)),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    const steps = connectSteps;
    final last = _at == steps.length - 1;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _go(_at + 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(_at - 1),
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Focus(
        autofocus: true,
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          label: 'How connecting works',
          child: ColoredBox(
            color: t.bg,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PhonePageHeader(
                    back: 'Previous screen',
                    onBack: _at == 0 ? null : () => _go(_at - 1),
                    heading: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            'How connecting works',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Type.sans(
                              16,
                              weight: FontWeight.w600,
                              color: t.ink,
                            ),
                          ),
                        ),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            '${_at + 1} of ${steps.length}',
                            style: Type.sans(12.5, color: t.muted).copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    action: IconBtn(
                      'close',
                      tooltip: 'Close',
                      box: 48,
                      filled: true,
                      size: IconSize.small,
                      onPressed: widget.onClose,
                    ),
                  ),
                  _Marks(steps: steps, at: _at, onTap: _go),
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: steps.length,
                      onPageChanged: (page) => setState(() => _at = page),
                      itemBuilder: (context, page) =>
                          _Screen(steps[page], key: ValueKey(page)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Go(
                          label: last
                              ? widget.end
                              : _at == 0
                              ? 'Begin'
                              : 'Continue',
                          about: last
                              ? widget.endAbout
                              : 'next · ${steps[_at + 1].kicker.toLowerCase()}',
                          onTap: last ? widget.onEnd : () => _go(_at + 1),
                        ),
                        if (_at < 2)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              'Swipe, or use the arrow keys',
                              textAlign: TextAlign.center,
                              style: Type.sans(12, color: t.muted),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A mark for each screen: those seen in the accent, faded, the one shown in the accent.
class _Marks extends StatelessWidget {
  const _Marks({required this.steps, required this.at, required this.onTap});

  final List<GuideStep> steps;
  final int at;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 4,
        children: [
          for (final (n, step) in steps.indexed)
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 28),
                child: Tappable(
                  label: 'Screen ${n + 1}: ${step.kicker}',
                  selected: n == at,
                  onTap: () => onTap(n),
                  child: SizedBox(
                    height: 24,
                    child: Center(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: n > at
                              ? t.line
                              : t.accent.withValues(alpha: n == at ? 1 : 0.45),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One screen, centred in its room, scrolling when it is taller.
class _Screen extends StatelessWidget {
  const _Screen(this.step, {super.key});

  final GuideStep step;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final height = MediaQuery.sizeOf(context).height;
    final short = height < 680;
    final says = Type.sans(
      step.hero ? (short ? 30 : 36) : 20,
      weight: FontWeight.w500,
      color: t.ink2,
      height: step.hero ? 1.1 : 1.3,
      letterSpacing: step.hero ? -1 : -0.2,
    );
    final art = step.art;
    final code = step.code;
    return LayoutBuilder(
      builder: (context, room) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: room.maxHeight - 24),
          child: Rise(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                _Padded(SectionLabel(step.kicker, header: false)),
                if (art != null)
                  GuideFigure(
                    art,
                    maxHeight:
                        MediaQuery.sizeOf(context).height *
                        (short ? 0.24 : 0.3),
                  ),
                if (code != null) _Code(code),
                _Padded(
                  Text.rich(
                    TextSpan(children: _accented(step.says, t), style: says),
                  ),
                ),
                if (step.sub case final sub?)
                  _Padded(
                    Text(
                      sub,
                      style: Type.sans(16, color: t.muted, height: 1.5),
                    ),
                  ),
                if (step.lines.isNotEmpty) _Lines(step.lines),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [text] with the words between asterisks bold in the accent.
  static List<TextSpan> _accented(String text, Tokens t) => [
    for (final (n, part) in text.split('*').indexed)
      n.isOdd
          ? TextSpan(
              text: part,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation('wght', 700)],
                color: t.accent,
              ),
            )
          : TextSpan(text: part),
  ];
}

/// Words set 8 px in from the cards' edges.
class _Padded extends StatelessWidget {
  const _Padded(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: child);
}

/// What a terminal shows, in a card that scrolls sideways when it is wider.
class _Code extends StatelessWidget {
  const _Code(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final plain = Type.mono(12.5, color: t.ink2, height: 1.65);
    return Container(
      decoration: cardDecoration(t),
      child: SideScroll(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Text.rich(
          TextSpan(
            style: plain,
            children: [
              for (final (n, line) in lines.indexed) ...[
                if (n > 0) const TextSpan(text: '\n'),
                ..._line(line, t),
              ],
            ],
          ),
          softWrap: false,
        ),
      ),
    );
  }

  static final _brackets = RegExp(r'[\[\]]');

  /// [line] muted when it is a comment or output, or else with words between brackets marked.
  static List<TextSpan> _line(String line, Tokens t) {
    if (line.startsWith('#') || line.startsWith('~')) {
      return [
        TextSpan(
          text: line.startsWith('~') ? line.substring(1) : line,
          style: TextStyle(color: t.muted),
        ),
      ];
    }
    return [
      for (final (n, part) in line.split(_brackets).indexed)
        n.isOdd
            ? TextSpan(
                text: part,
                style: TextStyle(color: t.ink, backgroundColor: t.accentbg),
              )
            : TextSpan(text: part),
    ];
  }
}

/// A numbered list in a card, each a name over a detail in the mono face.
class _Lines extends StatelessWidget {
  const _Lines(this.lines);

  final List<(String, String)> lines;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return FieldCard([
      for (final (n, (name, detail)) in lines.indexed)
        Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: FieldCard.inset,
            vertical: 8,
          ),
          child: Row(
            spacing: 10,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.accentbg,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${n + 1}',
                  style: Type.sans(
                    11.5,
                    weight: FontWeight.w700,
                    color: t.accent,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      name,
                      style: Type.sans(
                        16,
                        weight: FontWeight.w500,
                        color: t.ink,
                        height: 1.3,
                      ),
                    ),
                    Text(
                      detail,
                      style: Type.mono(11.5, color: t.muted, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ]);
  }
}

/// The guide's main button, on the accent: what it does over where it goes, and an arrow.
class _Go extends StatelessWidget {
  const _Go({required this.label, required this.about, required this.onTap});

  final String label;
  final String about;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: '$label, $about',
      onTap: onTap,
      color: t.accent,
      radius: BorderRadius.circular(Sizes.control),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    Text(
                      label,
                      style: Type.sans(
                        17,
                        weight: FontWeight.w600,
                        color: t.onaccent,
                      ),
                    ),
                    Text(
                      about,
                      style: Type.sans(
                        12.5,
                        color: t.onaccent.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              AppIcon('chevron', color: t.onaccent),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet underlined link to a guide, centred, such as How connecting works.
class GuideLink extends StatelessWidget {
  const GuideLink(this.label, {super.key, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Center(
      child: Tappable(
        label: label,
        onTap: onTap,
        radius: BorderRadius.circular(Sizes.small),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: Type.sans(14, color: t.muted).copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: t.line,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
