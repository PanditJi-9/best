import 'dart:math';
import 'package:best_domain/best_domain.dart';
import 'package:flutter/material.dart';

/// Renders translated Arabic speech bubbles over manga pages with matching background and text colors.
/// Ported from HikariManga 1.4.2 reader overlay.
class BubbleOverlayWidget extends StatelessWidget {
  const BubbleOverlayWidget({
    super.key,
    required this.bubbles,
    required this.imageWidth,
    required this.imageHeight,
    required this.displayWidth,
    required this.displayHeight,
    this.visible = true,
  });

  final List<Bubble> bubbles;
  final int imageWidth;
  final int imageHeight;
  final double displayWidth;
  final double displayHeight;
  final bool visible;

  Color _parseHex(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    try {
      final clean = hex.replaceAll('#', '');
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      } else if (clean.length == 8) {
        return Color(int.parse(clean, radix: 16));
      }
    } catch (_) {}
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    if (!visible || bubbles.isEmpty || imageWidth <= 0 || imageHeight <= 0) {
      return const SizedBox.shrink();
    }

    final scaleX = displayWidth / imageWidth;
    final scaleY = displayHeight / imageHeight;

    return Stack(
      children: [
        for (final bubble in bubbles) ...[
          Positioned(
            left: bubble.box.left * scaleX,
            top: bubble.box.top * scaleY,
            width: max(20.0, bubble.box.width * scaleX),
            height: max(16.0, bubble.box.height * scaleY),
            child: _BubbleCard(
              bubble: bubble,
              boxWidth: bubble.box.width * scaleX,
              boxHeight: bubble.box.height * scaleY,
              bgColor: _parseHex(bubble.bgColorHex, Colors.white),
              gradientEndColor: bubble.bgGradientEndHex != null
                  ? _parseHex(bubble.bgGradientEndHex, Colors.white)
                  : null,
              textColor: _parseHex(bubble.textColorHex, Colors.black),
            ),
          ),
        ],
      ],
    );
  }
}

class _BubbleCard extends StatelessWidget {
  const _BubbleCard({
    required this.bubble,
    required this.boxWidth,
    required this.boxHeight,
    required this.bgColor,
    this.gradientEndColor,
    required this.textColor,
  });

  final Bubble bubble;
  final double boxWidth;
  final double boxHeight;
  final Color bgColor;
  final Color? gradientEndColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    // Dynamically calculate font size to fit inside the bubble
    final area = boxWidth * boxHeight;
    final charCount = max(1, bubble.text.length);
    final approxFontSize = (sqrt(area / (charCount * 1.3))).clamp(8.0, 16.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: gradientEndColor == null ? bgColor : null,
        gradient: gradientEndColor != null
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bgColor, gradientEndColor!],
              )
            : null,
        borderRadius: BorderRadius.circular(max(4.0, min(boxWidth, boxHeight) * 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Text(
            bubble.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: approxFontSize,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
        ),
      ),
    );
  }
}
