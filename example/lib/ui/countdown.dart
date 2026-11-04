import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds every second with the time left until [target].
class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.target, required this.builder, this.clock = DateTime.now});

  final DateTime target;
  final Widget Function(BuildContext context, Duration remaining) builder;
  final DateTime Function() clock;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.target.difference(widget.clock()));
}
