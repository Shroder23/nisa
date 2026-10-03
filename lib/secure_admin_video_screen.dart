import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'services/secure_admin_media_service.dart';
import 'services/screen_security_service.dart';

class SecureAdminVideoScreen extends StatefulWidget {
  final String adminKey;
  final String protectedUrl;

  const SecureAdminVideoScreen({
    super.key,
    required this.adminKey,
    required this.protectedUrl,
  });

  @override
  State<SecureAdminVideoScreen> createState() => _SecureAdminVideoScreenState();
}

class _SecureAdminVideoScreenState
    extends LanguageAwareState<SecureAdminVideoScreen> {
  VideoPlayerController? _controller;
  File? _localFile;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(ScreenSecurityService.setScreenshotBlocked(true));
    _load();
  }

  Future<void> _load() async {
    try {
      final file = await SecureAdminMediaService.downloadVideo(
        adminKey: widget.adminKey,
        protectedUrl: widget.protectedUrl,
      );

      final controller = VideoPlayerController.file(file);
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        await SecureAdminMediaService.deleteIfExists(file);
        return;
      }

      setState(() {
        _localFile = file;
        _controller = controller;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    final file = _localFile;

    if (controller != null) {
      controller.dispose();
    }

    // Best-effort deletion of sensitive temporary media after leaving screen.
    SecureAdminMediaService.deleteIfExists(file);
    unawaited(ScreenSecurityService.setScreenshotBlocked(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Parent Confirmation Video'),
        actions: const [LanguageSelectorButton()],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _error != null
              ? LocalizedText('Something went wrong. Please try again.')
              : controller == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: controller.value.aspectRatio == 0
                          ? 16 / 9
                          : controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          if (controller.value.isPlaying) {
                            controller.pause();
                          } else {
                            controller.play();
                          }
                        });
                      },
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                      label: LocalizedText(
                        controller.value.isPlaying ? 'Pause' : 'Play',
                      ),
                    ),
                    const SizedBox(height: 10),
                    const LocalizedText(
                      'This protected verification video is downloaded '
                      'temporarily for review and deleted when you leave '
                      'this screen.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
