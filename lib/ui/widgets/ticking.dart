import 'dart:async';

import 'package:flutter/widgets.dart';

/// What [builder] builds, built again every [every] while it shows, as a countdown on screen
/// needs.
class Ticking extends StatefulWidget {
  const Ticking({
    super.key,
    required this.builder,
    this.every = const Duration(seconds: 30),
  });

  final WidgetBuilder builder;
  final Duration every;

  @override
  State<Ticking> createState() => _TickingState();
}

class _TickingState extends State<Ticking> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(widget.every, (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
