import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/browser.dart';
import '../../core/chat.dart';
import '../../core/markdown.dart';
import '../app_scope.dart';
import '../links.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import 'card_image.dart';
import 'highlight.dart';
import 'math.dart';
import '../icons.dart';

/// An answer's text, drawn as Markdown and selectable. A code block and a table scroll sideways
/// rather than widen the chat, and a code block has its own Copy button. A link opens outside
/// the app. An image loads only from the AnythingLLM server's own host, on any port, as a tool's
/// card does, and only over https or the server's own scheme where plain http is allowed:
/// loading any other would send its address, which a model could have filled with what it read,
/// to that site. Any other image shows as its description, which reads as a link: a tap opens
/// the link around the image, or else the image's own address.
class AnswerBody extends StatelessWidget {
  const AnswerBody(this.text, {super.key, this.label = false});

  final String text;

  /// Whether the answer carries its words as a semantics label, for a screen reader where the
  /// selectable text is missing from the semantics tree ([AppScope.labelAnswers]).
  final bool label;

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
    final markdown = MarkdownBody(
      data: text,
      selectable: true,
      extensionSet: answerMarkdown,
      onTapLink: (_, href, _) {
        if (href == null) return;
        // A browser card opens the chat's browser beside it, where Take over leaves the app.
        if (isBrowserPage(href, server)) {
          AppScope.of(context).shell.showBrowser();
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            card,
            if (linked.contains(uri)) _LiveCaption(),
          ],
        );
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

/// Under an app card whose link opens its page: the card is live, and a tap opens the app.
class _LiveCaption extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: t.okdot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('Live · tap to open', style: Type.sans(12.5, color: t.muted)),
        ],
      ),
    );
  }
}
