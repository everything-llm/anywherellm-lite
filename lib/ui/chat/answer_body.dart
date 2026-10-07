import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/chat.dart';
import '../../core/ports.dart';
import '../app_scope.dart';
import '../links.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/tappable.dart';
import '../icons.dart';

/// An answer's text, drawn as Markdown and selectable. A code block and a table scroll sideways
/// rather than widen the chat, and a code block has its own Copy button. A link opens outside
/// the app. An image loads only from the AnythingLLM server's own host, on any port, as a tool's
/// card does, and only over https or the server's own scheme where plain http is allowed:
/// loading any other would send its address, which a model could have filled with what it read,
/// to that site. Any other image shows as its description, which reads as a link: a tap opens
/// the link around the image, or else the image's own address.
class AnswerBody extends StatelessWidget {
  const AnswerBody(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final body = Type.sans(15.5, color: t.ink, height: 1.65);
    final code = Type.mono(13.5, color: t.ink, height: 1.5);
    TextStyle heading(double size) =>
        Type.sans(size, weight: FontWeight.w600, color: t.ink, height: 1.35);
    final border = BorderSide(color: t.line);
    final settings = AppScope.of(context).settings;
    final server = settings.connection?.uri;
    final allowHttp = settings.allowHttp;
    final linked = linkedImages(text);
    return MarkdownBody(
      data: text,
      selectable: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      onTapLink: (_, href, _) {
        if (href != null) openLink(context, href);
      },
      imageBuilder: (uri, _, alt) => _Image(
        uri,
        alt: alt,
        server: server,
        allowHttp: allowHttp,
        linked: linked.contains(uri),
      ),
      builders: {'pre': _CodeBlockBuilder()},
      styleSheet: MarkdownStyleSheet(
        p: body,
        a: body.copyWith(
          color: t.accent,
          decoration: TextDecoration.underline,
          decorationColor: t.accent,
        ),
        code: code.copyWith(backgroundColor: t.panel2),
        h1: heading(22),
        h2: heading(19),
        h3: heading(17),
        h4: heading(15.5),
        h5: heading(15.5),
        h6: heading(15.5),
        h1Padding: const EdgeInsets.only(top: 6),
        h2Padding: const EdgeInsets.only(top: 6),
        h3Padding: const EdgeInsets.only(top: 4),
        em: body.copyWith(fontStyle: FontStyle.italic),
        strong: Type.sans(
          15.5,
          weight: FontWeight.w600,
          color: t.ink,
          height: 1.65,
        ),
        del: body.copyWith(decoration: TextDecoration.lineThrough),
        blockquote: body.copyWith(color: t.ink2),
        blockquotePadding: const EdgeInsets.only(left: 14),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: t.line, width: 3)),
        ),
        blockSpacing: 12,
        listIndent: 22,
        listBullet: body,
        tableHead: Type.sans(
          14,
          weight: FontWeight.w600,
          color: t.ink,
          height: 1.4,
        ),
        tableBody: Type.sans(14, color: t.ink, height: 1.4),
        tableBorder: TableBorder.all(color: t.line),
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        tableHeadCellsDecoration: BoxDecoration(color: t.panel2),
        horizontalRuleDecoration: BoxDecoration(border: Border(top: border)),
      ),
    );
  }
}

/// The addresses of the images in the Markdown [text] that sit inside a link.
Set<Uri> linkedImages(String text) {
  if (!text.contains('![')) return const {};
  final found = <Uri>{};
  void visit(md.Node node, {required bool inLink}) {
    if (node is! md.Element) return;
    if (node.tag == 'img' && inLink) {
      if (Uri.tryParse(node.attributes['src'] ?? '') case final uri?) {
        found.add(uri);
      }
    }
    for (final child in node.children ?? const <md.Node>[]) {
      visit(child, inLink: inLink || node.tag == 'a');
    }
  }

  final document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  for (final node in document.parse(text)) {
    visit(node, inLink: false);
  }
  return found;
}

/// An image in an answer: loaded when it is on the [server]'s host over https, or over http
/// when the [server] itself is http and [allowHttp] holds; otherwise its description. The
/// description says whether the image was not loaded or failed to load, and why it failed. It
/// opens the image's address when tapped, unless the image is [linked], where the link around
/// it takes the tap. A live
/// image, such as a run's progress card, shows each new frame as it comes, and is followed only
/// while it can be seen: not while the chat is offstage behind Files ([TickerMode]) or the app
/// is hidden, since a watched card keeps the host's browser from being stopped. Hiding is heard
/// here, not through [TickerMode], because a hidden app draws no frames to pass it down.
class _Image extends StatefulWidget {
  const _Image(
    this.uri, {
    required this.alt,
    required this.server,
    required this.allowHttp,
    required this.linked,
  });

  final Uri uri;
  final String? alt;
  final Uri? server;
  final bool allowHttp;

  /// Whether the image sits inside a link, which then takes a tap on its description.
  final bool linked;

  bool get loadable => loadableImage(uri, server, allowHttp: allowHttp);

  @override
  State<_Image> createState() => _ImageState();
}

class _ImageState extends State<_Image> {
  Uint8List? _frame;

  /// Whether the read ended, by finishing or failing, so there is nothing more to follow.
  bool _ended = false;

  /// Why the read failed, or null.
  String? _failure;

  bool _onstage = true;
  bool _appShown = true;
  StreamSubscription<Uint8List>? _reading;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _reset();
    _lifecycle = AppLifecycleListener(
      onHide: () => _setAppShown(false),
      onShow: () => _setAppShown(true),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onstage = TickerMode.valuesOf(context).enabled;
    _follow();
  }

  @override
  void didUpdateWidget(_Image old) {
    super.didUpdateWidget(old);
    if (old.uri == widget.uri && old.loadable == widget.loadable) return;
    _stop();
    _reset();
    _follow();
  }

  @override
  void dispose() {
    _stop();
    _lifecycle.dispose();
    super.dispose();
  }

  void _setAppShown(bool shown) {
    _appShown = shown;
    _follow();
  }

  /// Starts from the frame last read for this image, if any.
  void _reset() {
    _frame = widget.loadable
        ? AppScope.of(context).chat.lastFrame(widget.uri)
        : null;
    _ended = false;
    _failure = null;
  }

  /// Reads the image while it can be seen and has more to give, and lets go of it otherwise.
  void _follow() {
    if (!widget.loadable || !_onstage || !_appShown || _ended) {
      _stop();
      return;
    }
    _reading ??= AppScope.of(context).chat
        .imageFrames(widget.uri)
        .listen(
          _show,
          onError: (Object error) =>
              _end(failure: error is ApiException ? error.message : '$error'),
          onDone: _end,
          cancelOnError: true,
        );
  }

  /// Shows [frame] in place of the last, whose decoded image would otherwise stay in the image
  /// cache: each frame is its own [MemoryImage].
  void _show(Uint8List frame) {
    final last = _frame;
    if (last != null && !identical(last, frame)) {
      unawaited(MemoryImage(last).evict());
    }
    setState(() => _frame = frame);
  }

  void _end({String? failure}) => setState(() {
    _ended = true;
    _failure = failure;
    _reading = null;
  });

  void _stop() {
    unawaited(_reading?.cancel());
    _reading = null;
  }

  /// The image's description, drawn as a link: the host it is not loaded from, or that it did
  /// not load, with why in its tooltip.
  Widget _described(BuildContext context) {
    final t = Tokens.of(context);
    final alt = widget.alt?.trim();
    final name = alt != null && alt.isNotEmpty ? alt : 'image';
    final failed = widget.loadable;
    final text = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon('link', size: IconSize.xs, color: t.accent),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '[$name: ${failed ? 'did not load' : widget.uri.host}]',
            style: Type.sans(
              14,
              color: t.accent,
            ).copyWith(decoration: TextDecoration.underline),
          ),
        ),
      ],
    );
    final why = failed
        ? _failure ?? 'The image did not load.'
        : 'Not loaded: images load only from the server\'s own host.';
    if (widget.linked) return Tooltip(message: why, child: text);
    return Tappable(
      label: 'Open $name',
      tooltip: why,
      onTap: () => openLink(context, widget.uri.toString()),
      child: text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    final described = _described(context);
    if (!widget.loadable || (frame == null && _ended)) return described;
    if (frame == null) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          frame,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          semanticLabel: widget.alt,
          errorBuilder: (_, _, _) => described,
        ),
      ),
    );
  }
}

/// Draws a fenced or indented code block as a [_CodeBlock].
class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    var code = element.textContent;
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    return _CodeBlock(code);
  }
}

/// A code block: monospaced, scrolling sideways, with a Copy button in its corner.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.line),
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 12, 44, 12),
            child: Text(
              code,
              style: Type.mono(13.5, color: t.ink, height: 1.5),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: CopyButton(code, tooltip: 'Copy code', box: 28),
          ),
        ],
      ),
    );
  }
}

/// Puts [text] on the clipboard, and says Copied for a moment after.
class CopyButton extends StatefulWidget {
  const CopyButton(
    this.text, {
    super.key,
    this.tooltip = 'Copy',
    this.box = 30,
  });

  final String text;
  final String tooltip;
  final double box;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  Timer? _reset;
  bool _copied = false;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_copied)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text('Copied', style: Type.sans(12.5, color: t.muted)),
          ),
        IconBtn(
          'copy',
          tooltip: widget.tooltip,
          onPressed: _copy,
          box: widget.box,
          size: IconSize.xs,
        ),
      ],
    );
  }
}
