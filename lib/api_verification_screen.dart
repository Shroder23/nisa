import 'package:flutter/material.dart';

import 'widgets/localized_text.dart';

import 'api_verification_upload_screen.dart';
import 'api_verification_pending_screen.dart';
import 'edit_profile_screen.dart';
import 'main.dart' show AuthGate;
import 'models/user_profile.dart';
import 'services/api_app_state.dart';
import 'services/api_profile_service.dart';
import 'services/api_verification_service.dart';

class ApiVerificationScreen extends StatefulWidget {
  final UserProfile profile;

  const ApiVerificationScreen({super.key, required this.profile});

  @override
  State<ApiVerificationScreen> createState() => _ApiVerificationScreenState();
}

class _ApiVerificationScreenState extends State<ApiVerificationScreen> {
  late UserProfile _profile = widget.profile;
  late Future<Map<String, dynamic>> _status =
      ApiVerificationService.getStatus();
  bool _continuing = false;

  bool get _hasProfilePhoto => _profile.profilePhoto?.trim().isNotEmpty == true;

  Future<void> _addProfilePhoto() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditProfileScreen(profile: _profile)),
    );
    if (!mounted) return;
    try {
      final refreshed = await ApiProfileService.getMyProfile();
      if (mounted && refreshed != null) {
        setState(() => _profile = refreshed);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText('Something went wrong. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _startUpload() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ApiVerificationUploadScreen()),
    );
    if (submitted == true && mounted) {
      setState(() {
        _status = Future.value({'status': 'pending'});
      });
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const ApiVerificationPendingScreen()),
      );
      if (!mounted) return;
      setState(() {
        _status = ApiVerificationService.getStatus();
      });
    }
  }

  Future<void> _continueUnverified() async {
    if (_continuing) return;
    setState(() => _continuing = true);
    try {
      await ApiAppState.completeRegistration();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  Widget _statusBody(Map<String, dynamic> data) {
    final status = data['status']?.toString() ?? 'not_submitted';
    if (_profile.isVerified || status == 'approved') {
      return _StatusCard(
        icon: Icons.verified,
        title: 'Parent Verified',
        body: 'No further verification upload is required. Your verified badge remains active unless your verification status is changed by moderation.',
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      );
    }
    if (status == 'pending') {
      return _StatusCard(
        icon: Icons.hourglass_top_rounded,
        title: 'Verification is under review',
        body: 'Your verification documents have already been submitted. You do not need to upload them again while the request is being reviewed.',
        backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
      );
    }

    if (status == 'resubmission_required') {
      return _outcomeNeedsResubmission(
        icon: Icons.edit_note,
        title: 'Verification resubmission requested',
        backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
      );
    }
    if (status == 'rejected') {
      return _outcomeNeedsResubmission(
        icon: Icons.error_outline_rounded,
        title: 'Verification rejected',
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusCard(
          icon: Icons.verified_user_outlined,
          title: 'Parent verification not completed',
          body: 'Verification is optional. You can continue without a Verified badge.',
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        ),
        const SizedBox(height: 14),
        _verificationUploadAction(),
      ],
    );
  }

  Widget _outcomeNeedsResubmission({
    required IconData icon,
    required String title,
    required Color backgroundColor,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _StatusCard(icon: icon, title: title, backgroundColor: backgroundColor),
      const SizedBox(height: 14),
      _verificationUploadAction(),
    ],
  );

  Widget _verificationUploadAction() => !_hasProfilePhoto
      ? FilledButton.icon(
          onPressed: _addProfilePhoto,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const LocalizedText('Add profile photo first'),
        )
      : FilledButton.icon(
          onPressed: _startUpload,
          icon: const Icon(Icons.upload_file_outlined),
          label: const LocalizedText('Start Parent Verification'),
        );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('Parent Verification')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const LocalizedText(
            'Verification is optional. Unverified members can still use discovery, interests, messaging after a match, blocking, and reporting.',
          ),
          const SizedBox(height: 18),
          FutureBuilder<Map<String, dynamic>>(
            future: _status,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  children: [
                    LocalizedText('Something went wrong. Please try again.'),
                    TextButton(
                      onPressed: () => setState(
                        () => _status = ApiVerificationService.getStatus(),
                      ),
                      child: const LocalizedText('Try again'),
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              final approved =
                  _profile.isVerified ||
                  data['status']?.toString() == 'approved';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _statusBody(data),
                  if (!approved) ...[
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: _continuing ? null : _continueUnverified,
                      child: LocalizedText(
                        _continuing
                            ? 'Continuing…'
                            : 'Continue without verification',
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final Color? backgroundColor;

  const _StatusCard({
    required this.icon,
    required this.title,
    this.body,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) => Card(
    color: backgroundColor,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (body != null) ...[
                  const SizedBox(height: 6),
                  LocalizedText(body),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
