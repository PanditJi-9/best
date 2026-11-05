import 'package:flutter/material.dart';

/// A 1px hairline used to separate layers without shadows.
///
/// The design language separates layers with colour and rules, not with
/// elevation — a reader that floats its chrome on shadows reads as a stack
/// of paper. Ported from Yokai's yokaiBottomRule / yokaiTopRule.
class BestHairlineRule extends StatelessWidget {
  const BestHairlineRule({
    super.key,
    this.color,
    this.indent = 0,
    this.endIndent = 0,
  });

  final Color? color;
  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: indent,
      endIndent: endIndent,
      color: color ?? Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
