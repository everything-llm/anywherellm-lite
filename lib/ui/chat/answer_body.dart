import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/gallery.dart';
import '../../core/markdown.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../links.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/side_scroll.dart';
import 'answer_image.dart';
import 'gallery.dart';
import 'highlight.dart';
import 'markdown_lists.dart';
import 'math.dart';
import '../icons.dart';

/// An answer's text, drawn as Markdown and selectable. A code block, a table and display math
/// scroll sideways rather than widen the chat, showing a scrollbar while they do, and a code
/// block has its own Copy button. A link opens outside the app. An image loads only from the
/// AnythingLLM server's own host, on any port, and only over https: loading any other would send
/// its address, which a model could have filled with what it read, to that site. Any other image shows as its description, which
/// reads as a link: a tap opens the link around the image, or else the image's own address. Two
/// or more pictures in a row are a [Gallery] ([answerParts]).
class AnswerBody extends StatelessWidget {
  const AnswerBody(
    this.text, {
    super.key,
    this.muted = false,
    this.caret = false,
  });

  final String text;

  /// Ends the text with the [Caret], for an answer still being written that [takesCaret]. The
  /// text is not selectable meanwhile, since a selectable text holds no widget.
  final bool caret;

  /// Draws the words in the second ink, for an answer that stopped before its end.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final parts = answerParts(text);
    if (parts case [TextPart(:final markdown)]) {
      return _markdown(context, markdown, caret: caret);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        for (final (i, part) in parts.indexed)
          switch (part) {
            TextPart(:final markdown) => _markdown(
              context,
              markdown,
              caret: caret && i == parts.length - 1,
            ),
            GalleryPart(:final pictures) => Gallery(pictures),
          },
      ],
    );
  }

  /// [text] drawn as Markdown, ending in the caret when [caret].
  Widget _markdown(BuildContext context, String text, {required bool caret}) {
    final t = Tokens.of(context);
    final ink = muted ? t.muted : t.ink;
    const lineHeight = 1.5;
    final body = Type.sans(Type.chat, color: ink, height: lineHeight);
    final code = Type.mono(15, color: ink, height: 1.45);
    // A model's headings are bold body text at every level, so a wordy answer's many headings
    // never outshout the answer itself.
    final heading = Type.sans(
      Type.chat,
      weight: FontWeight.w600,
      color: ink,
      height: lineHeight,
    );
    const headingPadding = EdgeInsets.only(top: 4);
    final border = BorderSide(color: t.line);
    final settings = AppScope.of(context).settings;
    final server = settings.connection?.uri;
    // Parsing the answer again to find them is only worth it once an image is drawn.
    Set<Uri>? linked;
    return TightListMarkdown(
      data: caret ? '$text$caretMark' : text,
      selectable: !caret,
      extensionSet: caret ? _withCaret : answerMarkdown,
      onTapLink: (_, href, _) {
        if (href != null) openAnswerLink(context, href);
      },
      imageBuilder: (uri, _, alt) {
        final inLink = (linked ??= linkedImages(text)).contains(uri);
        return AnswerImage(
          uri,
          alt: alt,
          server: server,
          linked: inLink,
          framed: inLink,
        );
      },
      bulletBuilder: (bullet) => listBullet(bullet, body),
      builders: {
        'pre': _CodeBlockBuilder(),
        'math': MathBuilder(style: body, fallback: code),
        'caret': CaretBuilder(),
      },
      styleSheet: MarkdownStyleSheet(
        // Named, so the text is drawn again at the new size when the system's text size or
        // the person's chat text size changes while the answer shows.
        textScaler: MediaQuery.textScalerOf(context),
        p: body,
        a: body.copyWith(
          color: t.accent,
          decoration: TextDecoration.underline,
          decorationColor: t.accent,
        ),
        code: code.copyWith(backgroundColor: t.sunken),
        // A code block draws its own box; the package's default would set it on a square of
        // Material's card colour.
        codeblockDecoration: const BoxDecoration(),
        h1: heading,
        h2: heading,
        h3: heading,
        h4: heading,
        h5: heading,
        h6: heading,
        h1Padding: headingPadding,
        h2Padding: headingPadding,
        h3Padding: headingPadding,
        h4Padding: headingPadding,
        h5Padding: headingPadding,
        h6Padding: headingPadding,
        em: body.copyWith(fontStyle: FontStyle.italic),
        strong: Type.sans(
          Type.chat,
          weight: FontWeight.w600,
          color: ink,
          height: lineHeight,
        ),
        del: body.copyWith(decoration: TextDecoration.lineThrough),
        blockquote: body.copyWith(color: t.ink),
        blockquotePadding: const EdgeInsets.only(left: 14),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: t.line, width: 3)),
        ),
        blockSpacing: 8,
        listIndent: 20,
        listBullet: body,
        tableHead: Type.sans(
          Type.chat,
          weight: FontWeight.w600,
          color: ink,
          height: 1.4,
        ),
        tableBody: Type.sans(Type.chat, color: ink, height: 1.4),
        tableBorder: TableBorder.all(color: t.line),
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        tableHeadCellsDecoration: BoxDecoration(color: t.sunken),
        // The package scrolls a table itself; these give it what [SideScroll] gives a code
        // block and display math: its scrollbar under it while it is wider than the chat.
        tableScrollbarThumbVisibility: true,
        tablePadding: const EdgeInsets.only(bottom: 10),
        horizontalRuleDecoration: BoxDecoration(border: Border(top: border)),
      ),
    );
  }
}

/// [answerMarkdown] that also reads the [caretMark].
final _withCaret = md.ExtensionSet(answerMarkdown.blockSyntaxes, [
  ...answerMarkdown.inlineSyntaxes,
  CaretSyntax(),
]);

/// The addresses of the images in the Markdown [text] that sit inside a link.
Set<Uri> linkedImages(String text) => {
  for (final linked in linkedImagesIn(text)) linked.image,
};

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
    final fence = element.children?.whereType<md.Element>().firstOrNull;
    final language = switch (fence?.attributes['class']) {
      final String c when c.startsWith('language-') => c.substring(9),
      _ => null,
    };
    return _CodeBlock(code, language: language);
  }
}

/// A code block: monospaced, scrolling sideways ([SideScroll]), with a Copy button in a gutter
/// of its own at its end, so no code ever scrolls under it. Code in a [language] [highlighted]
/// knows is coloured; Copy takes the plain code either way.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock(this.code, {this.language});

  final String code;

  /// The language the Markdown fence names, or null.
  final String? language;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final style = Type.mono(15, color: t.ink, height: 1.45);
    return Container(
      width: double.infinity,
      // The scrollbar stays inside the rounded corners.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(Sizes.control),
        border: Border.all(color: t.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SideScroll(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Text.rich(
                highlighted(
                      code,
                      language,
                      base: style,
                      dark: Theme.of(context).brightness == Brightness.dark,
                    ) ??
                    TextSpan(text: code, style: style),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 4),
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
    this.size = IconSize.xs,
  });

  final String text;
  final String tooltip;
  final double box;
  final IconSize size;

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

  // Copied swaps the icon for a check in its place, so nothing beside it moves, and a live
  // region around it says Copied to a screen reader.
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: _copied ? 'Copied' : null,
    child: IconBtn(
      _copied ? 'check' : 'copy',
      tooltip: widget.tooltip,
      onPressed: _copy,
      box: widget.box,
      size: widget.size,
    ),
  );
}
