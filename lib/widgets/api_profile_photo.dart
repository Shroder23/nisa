import 'package:flutter/material.dart';

import 'profile_photo.dart';

/// Keeps API-screen call sites stable while sharing the app's established
/// photo loading, caching, protected-media, preview, and fallback behavior.
class ApiProfilePhoto extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final String? fallbackText;
  final bool showBorder;
  final bool enablePreview;
  final BorderRadius? borderRadius;

  const ApiProfilePhoto({
    super.key,
    this.imageUrl,
    this.radius = 42,
    this.fallbackText,
    this.showBorder = false,
    this.enablePreview = true,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) => ProfilePhoto(
    imageUrl: imageUrl,
    radius: radius,
    fallbackText: fallbackText,
    showBorder: showBorder,
    enablePreview: enablePreview,
    borderRadius: borderRadius,
  );
}
