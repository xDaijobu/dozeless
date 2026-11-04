import 'package:flutter/material.dart';

/// A small rounded label: trigger names, modes, the Doze badge.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.background, required this.foreground, this.icon});

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground);
    return DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(icon == null ? 8 : 6, 2, 8, 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: foreground), const SizedBox(width: 4)],
          Text(label, style: style),
        ]),
      ),
    );
  }
}

/// Title above a group of cards, with an optional note on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ?trailing,
        ]),
      );
}

/// Pull to refresh around a list that can always be pulled, even when short.
class Refreshable extends StatelessWidget {
  const Refreshable({super.key, required this.onRefresh, required this.children});

  final Future<void> Function() onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: children,
        ),
      );
}
