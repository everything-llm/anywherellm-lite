import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/chat.dart';
import '../app_scope.dart';
import '../links.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../icons.dart';

/// An answer's text, drawn as Markdown and selectable. A code block and a table scroll sideways
/// rather than widen the chat, and a code block has its own Copy button. A link opens outside
/// the app. An image loads only from the AnythingLLM server's own host, on any port, as a tool's
/// card does, and only over https or the server's own scheme where plain http is allowed:
/// loading any other would send its address, which a model could have filled with what it read,
/// to that site. Any other image shows as its description.
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
    return MarkdownBody(
      data: text,
      selectable: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      onTapLink: (_, href, _) {
        if (href != null) openLink(context, href);
      },
      imageBuilder: (uri, _, alt) =>
          _Image(uri, alt: alt, server: server, allowHttp: allowHttp),
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

/// An image in an answer: loaded when it is on the [server]'s host over https, or over http
/// when the [server] itself is http and [allowHttp] holds; otherwise its description.
class _Image extends StatelessWidget {
  const _Image(
    this.uri, {
    required this.alt,
    required this.server,
    required this.allowHttp,
  });

  final Uri uri;
  final String? alt;
  final Uri? server;
  final bool allowHttp;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final described = Text(
      '[${alt?.trim().isNotEmpty == true ? alt!.trim() : 'image'}: ${uri.host}]',
      style: Type.sans(14, color: t.muted),
    );
    if (!loadableImage(uri, server, allowHttp: allowHttp)) return described;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          uri.toString(),
          fit: BoxFit.contain,
          semanticLabel: alt,
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
