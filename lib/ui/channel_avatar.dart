import 'package:flutter/material.dart';

class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({
    super.key,
    required this.name,
    required this.imageUrl,
    this.size = 36,
  });

  final String name;
  final String imageUrl;
  final double size;

  String _initial() {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  Widget _fallbackAvatar() {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF272727),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _initial(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.45,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return _fallbackAvatar();
    }

    return ClipOval(
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) => _fallbackAvatar(),
      ),
    );
  }
}
