import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/app_language_service.dart';

import '../services/api_auth_service.dart';
import '../services/photo_service.dart';
import '../services/screen_security_service.dart';

class ProfilePhoto extends StatefulWidget {
  final String? imageUrl;
  final double radius;
  final String? fallbackText;
  final bool showBorder;
  final bool enablePreview;
  final BorderRadius? borderRadius;

  const ProfilePhoto({
    super.key,
    this.imageUrl,
    this.radius = 42,
    this.fallbackText,
    this.showBorder = false,
    this.enablePreview = true,
    this.borderRadius,
  });

  @override
  State<ProfilePhoto> createState() => _ProfilePhotoState();
}

class _ProfilePhotoState extends State<ProfilePhoto> {
  String? _protectedPath;
  Future<Uint8List>? _protectedImage;

  @override
  void initState() {
    super.initState();
    _prepareProtectedImage(widget.imageUrl);
  }

  @override
  void didUpdateWidget(covariant ProfilePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _prepareProtectedImage(widget.imageUrl);
    }
  }

  void _prepareProtectedImage(String? url) {
    final raw = url?.trim() ?? '';
    final uri = Uri.tryParse(raw);
    final path = raw.startsWith('/api/profile-photos/')
        ? raw
        : raw.startsWith('api/profile-photos/')
        ? '/$raw'
        : (uri?.path.startsWith('/api/profile-photos/') == true
              ? uri!.path
              : null);
    _protectedPath = path;
    _protectedImage = path == null ? null : _fetchProtectedImage(path);
  }

  Future<Uint8List> _fetchProtectedImage(String path) async {
    final response = await ApiAuthService.getProtectedFile(path);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Profile photo could not be loaded.');
    }
    return response.bodyBytes;
  }

  @override
  Widget build(BuildContext context) {
    final protectedPath = _protectedPath;
    if (protectedPath != null) {
      return FutureBuilder<Uint8List>(
        future: _protectedImage,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _avatar(
              radius: widget.radius,
              child: SizedBox(
                width: widget.radius * .55,
                height: widget.radius * .55,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (!snapshot.hasData) return _fallback(context);
          final provider = MemoryImage(snapshot.data!);
          Widget photo = _avatar(
            radius: widget.radius,
            child: ClipRRect(
              borderRadius:
                  widget.borderRadius ?? BorderRadius.circular(widget.radius),
              child: SizedBox.square(
                dimension: widget.radius * 2,
                child: Image(
                  image: provider,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _fallback(context),
                ),
              ),
            ),
          );
          if (widget.showBorder) {
            photo = Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              child: photo,
            );
          }
          if (!widget.enablePreview) return photo;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                _openFullScreen(context, null, imageProvider: provider),
            child: photo,
          );
        },
      );
    }

    final resolvedUrl = PhotoService.resolvePhotoUrl(widget.imageUrl);
    final fallback = _fallback(context);

    Widget child;

    if (resolvedUrl.isEmpty) {
      child = fallback;
    } else {
      child = CachedNetworkImage(
        imageUrl: resolvedUrl,
        imageBuilder: (context, provider) {
          return _avatar(radius: widget.radius, backgroundImage: provider);
        },
        placeholder: (context, url) {
          return _avatar(
            radius: widget.radius,
            child: SizedBox(
              width: widget.radius * .55,
              height: widget.radius * .55,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorWidget: (context, url, error) => fallback,
      );
    }

    final photo = widget.showBorder
        ? Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            child: child,
          )
        : child;

    if (!widget.enablePreview || resolvedUrl.isEmpty) {
      return photo;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openFullScreen(context, resolvedUrl),
      child: photo,
    );
  }

  Future<void> _openFullScreen(
    BuildContext context,
    String? url, {
    ImageProvider? imageProvider,
  }) async {
    await ScreenSecurityService.setScreenshotBlocked(true);

    try {
      if (!context.mounted) return;

      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Close photo',
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return Material(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: SizedBox.expand(
                    child: imageProvider == null
                        ? CachedNetworkImage(
                            imageUrl: url!,
                            fit: BoxFit.contain,
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                            errorWidget: (context, url, error) => const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white70,
                                size: 56,
                              ),
                            ),
                          )
                        : Image(image: imageProvider, fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: SafeArea(
                    child: IconButton(
                      tooltip: AppLanguageService.translate('Close photo'),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      );
    } finally {
      await ScreenSecurityService.setScreenshotBlocked(false);
    }
  }

  Widget _avatar({
    required double radius,
    Widget? child,
    ImageProvider? backgroundImage,
  }) {
    if (widget.borderRadius == null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: backgroundImage,
        child: child,
      );
    }
    return ClipRRect(
      borderRadius: widget.borderRadius!,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: backgroundImage == null
            ? Center(child: child)
            : Image(image: backgroundImage, fit: BoxFit.cover),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final text = widget.fallbackText?.trim();

    return _avatar(
      radius: widget.radius,
      child: text != null && text.isNotEmpty
          ? Text(
              text[0].toUpperCase(),
              style: TextStyle(
                fontSize: widget.radius * .75,
                fontWeight: FontWeight.bold,
              ),
            )
          : Icon(Icons.person, size: widget.radius),
    );
  }
}
