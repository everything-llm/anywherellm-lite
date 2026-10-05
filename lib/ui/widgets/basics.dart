import 'package:flutter/material.dart';

import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'dashed.dart';

class NilsCard extends StatelessWidget {
  const NilsCard({
    super.key,
    required this.children,
    this.gap = 14,
    this.padding = const EdgeInsets.all(20),
  });

  final List<Widget> children;
  final double gap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(Sizes.card),
      ),
      child: Column(
        spacing: gap,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// A card of [Kv] rows, as on a document page.
class KvCard extends StatelessWidget {
  const KvCard(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => NilsCard(
    gap: 0,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    children: children,
  );
}

enum KvRule { bottom, top, none }

/// A label and its value on one line, wrapping when they do not fit.
class Kv extends StatelessWidget {
  const Kv(
    this.label, {
    super.key,
    this.text,
    this.child,
    this.rule = KvRule.bottom,
  });

  final String label;
  final String? text;
  final Widget? child;
  final KvRule rule;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final side = BorderSide(color: t.line2);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: rule == KvRule.bottom ? side : BorderSide.none,
          top: rule == KvRule.top ? side : BorderSide.none,
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: [
          Text(label, style: Type.sans(14, color: t.muted)),
          if (child != null)
            child!
          else
            Text(
              text ?? '',
              textAlign: TextAlign.right,
              style: Type.sans(14, color: t.ink),
            ),
        ],
      ),
    );
  }
}

/// Selectable monospace text in a tinted box. [long] caps the height and scrolls.
class CodeBlock extends StatelessWidget {
  const CodeBlock(this.text, {super.key, this.long = false, this.maxHeight});

  final String text;
  final bool long;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final cap =
        maxHeight ?? (long ? MediaQuery.sizeOf(context).height * 0.7 : null);
    final body = SelectableText(
      text,
      style: Type.mono(12, color: t.ink, height: 1.6),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.code,
        border: Border.all(color: t.line2),
        borderRadius: BorderRadius.circular(Sizes.control),
      ),
      child: cap == null
          ? body
          : ConstrainedBox(
              constraints: BoxConstraints(maxHeight: cap),
              child: SingleChildScrollView(child: body),
            ),
    );
  }
}

enum AlertKind { warn, bad }

class AlertBox extends StatelessWidget {
  const AlertBox(this.kind, this.title, {super.key, this.text});

  final AlertKind kind;
  final String title;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final bad = kind == AlertKind.bad;
    final fg = bad ? t.badfg : t.warnfg;
    return Semantics(
      liveRegion: bad,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bad ? t.badbg : t.warnbg,
          border: bad ? Border.all(color: t.badln) : null,
          borderRadius: BorderRadius.circular(Sizes.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Type.sans(14, weight: FontWeight.w600, color: fg),
            ),
            if (text != null) ...[
              const SizedBox(height: 6),
              Text(text!, style: Type.sans(14, color: fg)),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.title, this.text, {super.key});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return DashedBox(
      color: t.line,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            Text(
              title,
              style: Type.sans(16, weight: FontWeight.w500, color: t.ink),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Type.sans(14, color: t.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Underlined accent text that acts as a link.
class NilsLink extends StatefulWidget {
  const NilsLink(this.text, {super.key, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  State<NilsLink> createState() => _NilsLinkState();
}

class _NilsLinkState extends State<NilsLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        link: true,
        child: InkWell(
          onTap: widget.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: Text(
                widget.text,
                style: Type.sans(14, color: _hover ? t.ink : t.accent).copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: _hover ? t.ink : t.accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CrumbPart {
  const CrumbPart(this.text, {this.onTap});
  final String text;
  final VoidCallback? onTap;
}

class Crumb extends StatelessWidget {
  const Crumb(this.parts, {super.key, this.mono = false});

  final List<CrumbPart> parts;

  /// Set in the mono face, for a path.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final style = mono
        ? Type.mono(13.5, color: t.muted)
        : Type.sans(14, color: t.muted);
    return Wrap(
      spacing: 6,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) Text('›', style: style),
          parts[i].onTap == null
              ? Text(parts[i].text, style: style)
              : MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: parts[i].onTap,
                    child: Text(parts[i].text, style: style),
                  ),
                ),
        ],
      ],
    );
  }
}

/// A page title with an optional breadcrumb above and a subtitle below.
class PageHead extends StatelessWidget {
  const PageHead(
    this.title, {
    super.key,
    this.sub,
    this.crumb,
    this.mono = false,
  });

  final String title;

  /// A name that is code, such as a skill or a file: set in the mono face.
  final bool mono;
  final String? sub;
  final Widget? crumb;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = ScreenClass.ofContext(context).isPhone;
    final size = mono ? 28.0 : (phone ? 30.0 : 38.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (crumb != null) ...[crumb!, const SizedBox(height: 6)],
        Semantics(
          header: true,
          child: Text(
            title,
            style: mono
                ? Type.mono(size, color: t.ink, height: 1.15)
                : Type.serif(
                    size,
                    color: t.ink,
                    height: 1.15,
                    letterSpacing: -0.01 * size,
                  ),
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 6),
          Text(sub!, style: Type.sans(15, color: t.ink2, height: 1.5)),
        ],
      ],
    );
  }
}
