import 'package:flutter/material.dart';

import 'tokens.dart';

/// A numeric readout: mono digits, a small label under them.
///
/// Values that are not known render as an em dash ([bestValueUnavailable]),
/// never as a plausible zero. Ported from Yokai's YokaiMetric.
class BestMetric extends StatelessWidget {
  const BestMetric({
    super.key,
    required this.value,
    required this.label,
    this.tone = BestTone.neutral,
    this.valueSize = BestMetricType.valueMedium,
    this.icon,
  });

  final String value;
  final String label;
  final BestTone tone;
  final double valueSize;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final toneColor = tone.content(context);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: toneColor),
          const SizedBox(height: BestSpace.xs),
        ],
        Text(
          value,
          style: TextStyle(
            fontFamily: BestFontFamily.mono,
            fontSize: valueSize,
            fontWeight: FontWeight.w700,
            color: toneColor,
            height: 1.1,
          ),
        ),
        const SizedBox(height: BestSpace.xs),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
