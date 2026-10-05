import 'package:flutter/material.dart';

import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';

/// Every page scrolls inside a centred column of at most 720px.
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final phone = ScreenClass.ofContext(context).isPhone;
    final padding = phone
        ? const EdgeInsets.fromLTRB(16, 20, 16, 28)
        : const EdgeInsets.fromLTRB(40, 44, 40, 56);
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.column),
          child: Padding(
            padding: padding,
            child: Column(
              spacing: 22,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// [PageFrame] for content made of slivers, so a long list builds only the rows on screen. The
/// column, gutters and spacing are the same.
class SliverPageFrame extends StatelessWidget {
  const SliverPageFrame({super.key, required this.slivers});

  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    final phone = ScreenClass.ofContext(context).isPhone;
    final gutter = phone ? 16.0 : 40.0;
    final top = phone ? 20.0 : 44.0;
    final bottom = phone ? 28.0 : 56.0;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final side = width > Sizes.column
            ? (width - Sizes.column) / 2 + gutter
            : gutter;
        final sides = EdgeInsets.symmetric(horizontal: side);
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: top)),
            for (var i = 0; i < slivers.length; i++) ...[
              if (i > 0) const SliverToBoxAdapter(child: SizedBox(height: 22)),
              SliverPadding(padding: sides, sliver: slivers[i]),
            ],
            SliverToBoxAdapter(child: SizedBox(height: bottom)),
          ],
        );
      },
    );
  }
}

/// Loads a page's data and builds its content. A failure shows nils's words.
///
/// The default form builds the children of a [PageFrame]. [LoadPage.slivers] builds the slivers
/// of a [SliverPageFrame].
class LoadPage<T> extends StatefulWidget {
  const LoadPage({
    super.key,
    required this.load,
    required List<Widget> Function(BuildContext context, T data) this.builder,
  }) : slivers = null;

  const LoadPage.slivers({
    super.key,
    required this.load,
    required List<Widget> Function(BuildContext context, T data) this.slivers,
  }) : builder = null;

  final Future<T> Function() load;
  final List<Widget> Function(BuildContext context, T data)? builder;
  final List<Widget> Function(BuildContext context, T data)? slivers;

  @override
  State<LoadPage<T>> createState() => _LoadPageState<T>();
}

class _LoadPageState<T> extends State<LoadPage<T>> {
  late final Future<T> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return PageFrame(
            children: [
              const PageHead('Something went wrong'),
              AlertBox(
                AlertKind.bad,
                'Could not load this page',
                text: '${snapshot.error}',
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return PageFrame(
            children: [
              Text('Loading...', style: Type.sans(14.5, color: t.muted)),
            ],
          );
        }
        final data = snapshot.data as T;
        final slivers = widget.slivers;
        return slivers == null
            ? PageFrame(children: widget.builder!(context, data))
            : SliverPageFrame(slivers: slivers(context, data));
      },
    );
  }
}
