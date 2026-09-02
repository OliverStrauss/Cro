import 'package:flutter/material.dart';

// The app's one visual mark - a rotated squircle (three corners fully rounded, one squared
// off) reading as a wing/leaf in flight. Was previously inlined once in IconRail; extracted so
// the auth screens can reuse the exact same shape at a larger size instead of duplicating it.
class CroLogoMark extends StatelessWidget {
  final double size;
  final Color color;

  const CroLogoMark({super.key, this.size = 34, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.78,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(size / 2),
            topRight: Radius.circular(size / 2),
            bottomLeft: Radius.circular(size / 2),
            bottomRight: Radius.circular(size * 0.12),
          ),
        ),
      ),
    );
  }
}
