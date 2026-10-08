import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/browser.dart';
import '../../core/chat.dart';
import '../../core/markdown.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../links.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import 'card_image.dart';
import 'highlight.dart';
import 'math.dart';
import '../icons.dart';

/// An answer's text, drawn as Markdown and selectable. A code block and a table scroll sideways
/// rather than widen the chat, a table showing its scrollbar while it does, and a code block has
/// its own Copy button. A link opens outside
/// the app. An image loads only from the AnythingLLM server's own host, on any port, as a tool's
/// card does, and only over https or the server's own scheme where plain http is allowed:
/// loading any other would send its address, which a model could have filled with what it read,
/// to that site. Any other image shows as its description, which reads as a link: a tap opens
/// the link around the image, or else the image's own address. A linked app card opens its app
/// beside the chat, or in a sheet on a phone, rather than its page.
class AnswerBody extends StatelessWidget {
  const AnswerBody(
    this.text, {
    super.key,
    this.label = false,
    this.muted = false,
  });

  final String text;

  /// Draws the words in the second ink, for an answer that stopped before its end.
  final bool muted;

  /// Whether the answer carries its words as a semantics label, for a screen reader where the
  /// selectable text is missing from the semantics tree ([AppScope.labelAnswers]).
  final bool label;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final ink = muted ? t.ink2 : t.ink;
    final body = Type.sans(15.5, color: ink, height: 1.65);
    final code = Type.mono(13.5, color: ink, height: 1.5);
    TextStyle heading(double size) =>
        Type.sans(size, weight: FontWeight.w600, color: ink, height: 1.35);
    final border = BorderSide(color: t.line);
    final settings = AppScope.of(context).settings;
    final server = settings.connection?.uri;
    final allowHttp = settings.allowHttp;
    final linkedIn = linkedImagesIn(text);
    final linked = {for (final l in linkedIn) l.image};
    // The apps whose cards the answer links, by the link a tap on the card follows.
    final apps = {
      for (final l in linkedIn)
        l.link: ?appCardOf(l.image, l.link, l.alt, server),
    };
    final markdown = MarkdownBody(
      data: text,
      selectable: true,
      extensionSet: answerMarkdown,
      onTapLink: (_, href, _) {
        if (href == null) return;
        final shell = AppScope.of(context).shell;
        // A browser card opens the chat's browser beside it, where Take over leaves the app,
        // and an app's card its app.
        if (isBrowserPage(href, server)) {
          shell.showBrowser();
        } else if (apps[Uri.tryParse(href)] case final app?) {
          shell.showApp(app);
        } else {
          openLink(context, href);
        }
      },
      imageBuilder: (uri, _, alt) {
        final card = CardImage(
          uri,
          alt: alt,
          server: server,
          allowHttp: allowHttp,
          linked: linked.contains(uri),
        );
        if (!isAppCard(uri, server)) return card;
        if (!linked.contains(uri)) return card;
        return _AppCardShown(uri, card: card);
      },
      builders: {
        'pre': _CodeBlockBuilder(),
        'math': MathBuilder(style: body, fallback: code),
      },
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
          color: ink,
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
          color: ink,
          height: 1.4,
        ),
        tableBody: Type.sans(14, color: ink, height: 1.4),
        tableBorder: TableBorder.all(color: t.line),
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        tableHeadCellsDecoration: BoxDecoration(color: t.panel2),
        // A table wider than the chat shows its scrollbar, under the table, so its cut edge
        // reads as more to scroll to.
        tableScrollbarThumbVisibility: true,
        tablePadding: const EdgeInsets.only(bottom: 10),
        horizontalRuleDecoration: BoxDecoration(border: Border(top: border)),
      ),
    );
    if (!label) return markdown;
    // Explicit child nodes keep a link or a Copy code button from merging into the label.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: plainText(text),
      child: markdown,
    );
  }
}

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

/// A code block: monospaced, scrolling sideways, with a Copy button in its corner. Code in a
/// [language] [highlighted] knows is coloured; Copy takes the plain code either way.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock(this.code, {this.language});

  final String code;

  /// The language the Markdown fence names, or null.
  final String? language;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final style = Type.mono(13.5, color: t.ink, height: 1.5);
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

/// A linked app card, ringed in the accent while its app shows beside the chat, over a caption
/// that says the card is live and what a tap does: on a phone it opens a sheet, elsewhere the
/// panel beside the chat.
class _AppCardShown extends StatelessWidget {
  const _AppCardShown(this.uri, {required this.card});

  final Uri uri;
  final Widget card;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final shell = AppScope.of(context).shell;
    final phone = ScreenClass.ofContext(context).isPhone;
    return ListenableBuilder(
      listenable: shell,
      child: card,
      builder: (context, card) {
        final beside = !phone && shell.appOpen && shell.app?.card == uri;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  if (beside) BoxShadow(color: t.accent, spreadRadius: 2),
                ],
              ),
              child: card,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ReadyDot(gap: false, color: t.okdot),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      phone
                          ? 'Live · tap to open'
                          : beside
                          ? 'Live · open beside the chat'
                          : 'Live · click to open beside the chat',
                      style: Type.sans(12.5, color: t.muted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
