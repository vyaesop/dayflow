import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Initials avatar with a deterministic per-person color.
class DfAvatar extends StatelessWidget {
  const DfAvatar({super.key, required this.name, this.imageUrl, this.size = 32, this.seed});

  final String name;
  final String? imageUrl;
  final double size;

  /// Stable color seed (defaults to name) — pass the user id when available.
  final String? seed;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    final color = DfColors.avatarFor(seed ?? name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.32),
        image: imageUrl != null
            ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: imageUrl == null
          ? Text(
              initials,
              style: TextStyle(
                fontFamily: 'Inter',
                color: Colors.white,
                fontSize: size * 0.4,
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation('wght', 700)],
              ),
            )
          : null,
    );
  }

  String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}
