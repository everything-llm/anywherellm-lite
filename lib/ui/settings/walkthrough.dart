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

/// One screen of a walk-through: a [kicker], what it [says], whose words between asterisks are
/// in the accent, then [sub], then a picture, a block of code or a list. A [hero] screen says it
/// largest, any other in the smaller size a longer sentence takes.
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

  /// A list, each a name over a detail, whose words between backticks are code.
  final List<(String, String)> lines;
}

/// How connecting works: the two things to bring, where the key comes from, and the address.
const connectSteps = [
  GuideStep(
    'Getting connected',
    'Your phone, *your* AnythingLLM.',
    hero: true,
    sub: 'You need two things: the server\'s address and a key.',
    art: GuideArt.hero,
  ),
  GuideStep(
    'The key',
    'In AnythingLLM\'s web page: Settings, Developer API, Generate New API Key.',
    art: GuideArt.key,
  ),
  GuideStep(
    'The address',
    'The one you open AnythingLLM at in a browser. Away from your home network or '
        'Tailscale, it starts https.',
    lines: [
      ('At home', '`http://192.168.1.20:3001`'),
      ('Tailscale', '`https://box.tail1234.ts.net`'),
      ('Your own domain', '`https://ai.example.com`'),
    ],
  ),
];

/// Add the toolkit: what it adds, then installing it, adding it to an AnythingLLM and scanning
/// the code its installer shows.
const toolkitSteps = [
  GuideStep(
    'The toolkit',
    'Add *Memory* and *Upcoming*.',
    hero: true,
    sub:
        'A free add-on for the computer AnythingLLM runs on. Memory is what every chat '
        'knows about you; Upcoming is the agent\'s scheduled jobs.',
    art: GuideArt.kit,
  ),
  GuideStep(
    'Step 1 · Install',
    'On that computer, run this and open the address it prints.',
    code: [
      '\$ uv run anythingllm-toolkit gui',
      '~  Open this address in the browser:',
      '  [http://127.0.0.1:8470/?token=…]',
    ],
  ),
  GuideStep(
    'Step 2 · Add it',
    'Pick your AnythingLLM and choose Add the toolkit.',
    art: GuideArt.pick,
  ),
  GuideStep(
    'Step 3 · Scan',
    'Scan the code the page shows. Memory then appears here.',
    sub: 'If the page says your phone can\'t reach it yet, copy the fix it shows.',
    art: GuideArt.pair,
  ),
];

/// A walk-through over the whole window, as the Mobile Design pager draws one: Previous, its
/// [title] and which of the [steps] of how many, and Close; a mark for each screen, which goes
/// to it; the screens, swiped or stepped with the arrow keys; and a button for the next screen,
/// on the last [end], which [onEnd] does, with [endAbout] under it.
class Walkthrough extends StatefulWidget {
  const Walkthrough({
    super.key,
    required this.title,
    required this.steps,
    required this.onClose,
    required this.end,
    required this.endAbout,
    required this.onEnd,
    this.initial = 0,
  });

  final String title;
  final List<GuideStep> steps;
  final VoidCallback onClose;
  final String end;
  final String endAbout;
  final VoidCallback onEnd;

  /// The screen it opens on, counted from 0.
  final int initial;

  @override
  State<Walkthrough> createState() => _WalkthroughState();
}

class _WalkthroughState extends State<Walkthrough> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _at = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int to) {
    final next = to.clamp(0, widget.steps.length - 1);
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
    final steps = widget.steps;
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
          label: widget.title,
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
                            widget.title,
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 2,
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
                    height: 32,
                    child: Center(
                      child: AnimatedContainer(
                        duration: motion(
                          context,
                          const Duration(milliseconds: 250),
                        ),
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

/// One screen, centred in its room, scrolling when it is taller: its kicker, what it says and
/// the line under it, then its picture, code or list.
class _Screen extends StatelessWidget {
  const _Screen(this.step, {super.key});

  final GuideStep step;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final height = MediaQuery.sizeOf(context).height;
    final short = height < 680;
    final says = Type.sans(
      step.hero ? (short ? 32 : 38) : 20,
      weight: FontWeight.w500,
      color: t.ink2,
      height: step.hero ? 1.1 : 1.3,
      letterSpacing: step.hero ? -1 : -0.2,
    );
    final art = step.art;
    final code = step.code;
    return LayoutBuilder(
      builder: (context, room) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: room.maxHeight - 40),
          child: Rise(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                _Padded(SectionLabel(step.kicker, header: false)),
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
                if (art != null)
                  GuideFigure(art, maxHeight: height * (short ? 0.22 : 0.26)),
                if (code != null) _Code(code),
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

/// A list in a card, each a name over a detail, whose words between backticks are code.
class _Lines extends StatelessWidget {
  const _Lines(this.lines);

  final List<(String, String)> lines;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final detail = Type.sans(13, color: t.muted, height: 1.45);
    final code = Type.mono(
      12.5,
      color: t.ink2,
    ).copyWith(backgroundColor: t.hover);
    return FieldCard([
      for (final (name, about) in lines)
        Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: FieldCard.inset,
            vertical: 10,
          ),
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
              Text.rich(
                TextSpan(
                  style: detail,
                  children: [
                    for (final (n, part) in about.split('`').indexed)
                      TextSpan(text: part, style: n.isOdd ? code : null),
                  ],
                ),
              ),
            ],
          ),
        ),
    ]);
  }
}

/// The walk-through's main button, on the accent: what it does over where it goes, and an
/// arrow.
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
                        color: t.onaccent.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              AppIcon('arrow', color: t.onaccent, size: IconSize.medium),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet underlined link to a walk-through, centred, such as How connecting works.
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
