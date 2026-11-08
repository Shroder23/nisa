import 'presentation/nisa_premium/nisa_premium.dart';

import 'dart:async';

import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';

import 'main.dart' show AuthGate;
import 'models/user_profile.dart';
import 'services/firestore_service.dart';
import 'services/app_language_service.dart';
import 'services/api_app_state.dart';
import 'api_verification_screen.dart';
import 'verification_upload_screen.dart';

class VerificationScreen extends StatelessWidget {
  final UserProfile profile;
  final bool isRegistration;

  const VerificationScreen({
    super.key,
    required this.profile,
    this.isRegistration = false,
  });

  Future<void> _getVerified(BuildContext context) async {
    // Safety guard: a verified or already-pending profile must never
    // start another verification submission from this screen.
    if (profile.isVerified || profile.verificationPending) {
      return;
    }

    try {
      final uid = profile.uid;

      if (uid == null || uid.isEmpty) {
        throw StateError('Please sign in again.');
      }

      unawaited(
        FirestoreService.setRegistrationStep(
          uid: uid,
          step: 'verification',
        ).catchError((error) {
          debugPrint('Verification step sync deferred: $error');
        }),
      );

      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VerificationUploadScreen(profile: profile),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  Future<void> _continueUnverified(BuildContext context) async {
    // This action only belongs to users who have not started verification.
    if (profile.isVerified || profile.verificationPending) {
      return;
    }

    try {
      final uid = profile.uid;

      if (uid == null || uid.isEmpty) {
        throw StateError('Please sign in again.');
      }

      if (ApiAppState.isSignedIn) {
        await ApiAppState.completeRegistration();
      } else {
        await FirestoreService.markProfileComplete(uid);
      }

      if (!context.mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AuthGate()),
        (route) => false,
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ApiAppState.isSignedIn) {
      return ApiVerificationScreen(
        profile: profile,
        isRegistration: isRegistration,
      );
    }

    if (profile.isVerified) {
      return _VerifiedStatusScreen(profile: profile);
    }

    if (profile.verificationPending) {
      return _PendingStatusScreen(profile: profile);
    }

    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Verification'),
        centerTitle: true,
        leading: IconButton(
          tooltip: AppLanguageService.translate('Back'),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        actions: const [LanguageSelectorButton()],
      ),
      body: NisaPageBody(
        form: false,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 20),
              Icon(
                Icons.verified_user_outlined,
                size: 76,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              LocalizedText(
                'Family Verification',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const LocalizedText(
                'A verified badge is given only after parent or guardian verification is reviewed and approved.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(
                        'Required for verification:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 12),
                      _Point('Linked parent or guardian'),
                      _Point('Parent/guardian ID image'),
                      _Point('Parent/guardian confirmation video'),
                      _Point('Manual approval before badge appears'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (ApiAppState.isSignedIn)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: LocalizedText(
                      'Family verification upload is not connected to PostgreSQL yet. Continuing below will leave this profile unverified.',
                    ),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: () => _getVerified(context),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const LocalizedText('Start Verification Upload'),
                ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _continueUnverified(context),
                child: const LocalizedText('Continue Without Verification'),
              ),
              const SizedBox(height: 16),
              const LocalizedText(
                'Unverified profiles can use core Nisa features. Approved profiles display the Parent Verified badge.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerifiedStatusScreen extends StatelessWidget {
  final UserProfile profile;

  const _VerifiedStatusScreen({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Verification'),
        centerTitle: true,
        leading: IconButton(
          tooltip: AppLanguageService.translate('Back'),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        actions: const [LanguageSelectorButton()],
      ),
      body: NisaPageBody(
        form: false,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 48),
              Icon(
                Icons.verified,
                size: 92,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 22),
              LocalizedText(
                'Parent Verified',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              LocalizedRichText(
                spanBuilder: () => TextSpan(
                  children: [
                    if (profile.name.isNotEmpty) ...[
                      TextSpan(text: profile.name),
                      const TextSpan(text: ' · '),
                    ],
                    TextSpan(
                      text: AppLanguageService.translate('Parent Verified'),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_outline),
                      SizedBox(width: 12),
                      Expanded(
                        child: LocalizedText(
                          'No further verification upload is required. Your verified badge remains active unless your verification status is changed by moderation.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.done),
                label: const LocalizedText('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingStatusScreen extends StatelessWidget {
  final UserProfile profile;

  const _PendingStatusScreen({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Verification'),
        centerTitle: true,
        leading: IconButton(
          tooltip: AppLanguageService.translate('Back'),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        actions: const [LanguageSelectorButton()],
      ),
      body: NisaPageBody(
        form: false,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 48),
              Icon(
                Icons.hourglass_top,
                size: 88,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 22),
              LocalizedText(
                'Verification Under Review',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const LocalizedText(
                'Your verification documents have already been submitted. You do not need to upload them again while the request is being reviewed.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline),
                      SizedBox(width: 12),
                      Expanded(
                        child: LocalizedText(
                          'When the review is completed, your status will change to verified or you will receive a reason if another submission is required.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.done),
                label: const LocalizedText('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final String text;

  const _Point(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(child: LocalizedText(text)),
        ],
      ),
    );
  }
}
