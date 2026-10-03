import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'main.dart' show AuthGate;
import 'models/user_profile.dart';
import 'services/app_state.dart';
import 'services/firestore_service.dart';
import 'services/local_verification_service.dart';

class VerificationUploadScreen extends StatefulWidget {
  final UserProfile? profile;

  const VerificationUploadScreen({super.key, this.profile});

  @override
  State<VerificationUploadScreen> createState() =>
      _VerificationUploadScreenState();
}

class _VerificationUploadScreenState
    extends LanguageAwareState<VerificationUploadScreen> {
  final ImagePicker _picker = ImagePicker();

  UserProfile? get _profile => widget.profile ?? AppState.currentUser;

  File? _parentIdFile;
  File? _parentVideoFile;

  bool _isSubmitting = false;

  Future<void> _pickParentId() async {
    if (_isSubmitting) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const LocalizedText('Take ID photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const LocalizedText('Choose ID image'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    final file = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 2000,
    );

    if (file == null) return;

    setState(() => _parentIdFile = File(file.path));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: LocalizedText('Parent ID selected.')),
    );
  }

  Future<void> _pickParentVideo() async {
    if (_isSubmitting) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const LocalizedText('Record verification video'),
                subtitle: const LocalizedText('Recommended: under 60 seconds'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.video_library_outlined),
                title: const LocalizedText('Choose video from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    final file = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 60),
    );

    if (file == null) return;

    setState(() => _parentVideoFile = File(file.path));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: LocalizedText('Parent verification video selected.'),
      ),
    );
  }

  Future<void> _completeUnverified() async {
    if (_isSubmitting) return;

    final profile = _profile;

    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Please sign in again.')),
      );
      return;
    }

    if (profile.isVerified || profile.verificationPending) return;
    setState(() => _isSubmitting = true);
    try {
      final uid = AppState.firebaseUser?.uid;
      if (uid == null || uid != profile.uid) {
        throw StateError('Please sign in again.');
      }
      await FirestoreService.markProfileComplete(uid);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AuthGate()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitVerification() async {
    if (_isSubmitting) return;

    final idFile = _parentIdFile;
    final videoFile = _parentVideoFile;

    if (idFile == null || videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText(
            'Please provide both parent ID and parent video.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await LocalVerificationService.submit(
        idFile: idFile,
        videoFile: videoFile,
      );

      await AppState.loadUser();
      final profile = AppState.currentUser;

      if (profile == null) {
        throw StateError('Profile could not be reloaded after submission.');
      }

      if (profile.isVerified || !profile.verificationPending) {
        throw StateError(
          'Verification evidence was uploaded, but Firestore did not '
          'confirm the Pending Review state.',
        );
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const LocalizedText('Verification Submitted'),
            content: const LocalizedText(
              'Your parent identification and confirmation video were submitted successfully. Your profile will remain pending until an administrator reviews and approves the evidence.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const LocalizedText('Done'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AuthGate()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7B2CBF);

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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
          children: [
            Row(
              children: [
                for (int i = 0; i < 4; i++) ...[
                  Expanded(
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: purple,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  if (i < 3) const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 30),
            const Icon(Icons.verified_user_rounded, size: 70, color: purple),
            const SizedBox(height: 20),
            const LocalizedText(
              'Parent Verification',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const LocalizedText(
              'For a Verified badge, submit one parent/guardian identification image and a short confirmation video. No linked guardian account is required.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 26),
            _UploadCard(
              icon: Icons.badge_outlined,
              title: AppLanguageService.translate('Parent Identification'),
              description: 'Take or choose a clear image of one parent/guardian identification document.',
              uploaded: _parentIdFile != null,
              fileName: _parentIdFile == null
                  ? null
                  : _shortName(_parentIdFile!.path),
              buttonText: _parentIdFile == null
                  ? 'Select ID Image'
                  : 'Change ID Image',
              onPressed: _isSubmitting ? null : _pickParentId,
            ),
            const SizedBox(height: 18),
            _UploadCard(
              icon: Icons.videocam_outlined,
              title: AppLanguageService.translate('Parent Confirmation Video'),
              description: 'The parent should say they are your parent/guardian and permit you to seek marriage through Nisa.',
              uploaded: _parentVideoFile != null,
              fileName: _parentVideoFile == null
                  ? null
                  : _shortName(_parentVideoFile!.path),
              buttonText: _parentVideoFile == null
                  ? 'Select Video'
                  : 'Change Video',
              onPressed: _isSubmitting ? null : _pickParentVideo,
            ),
            const SizedBox(height: 28),
            const _PrivacyNotice(),
            const SizedBox(height: 28),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submitVerification,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const LocalizedText(
                        'Submit for Verification',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: _isSubmitting ? null : _completeUnverified,
                child: const LocalizedText('Continue Without Verification'),
              ),
            ),
            const SizedBox(height: 12),
            const LocalizedText(
              'Verification is optional. You can continue without a Verified badge.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final pieces = normalized.split('/');
    return pieces.isEmpty ? path : pieces.last;
  }
}

class _UploadCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool uploaded;
  final String? fileName;
  final String buttonText;
  final VoidCallback? onPressed;

  const _UploadCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.uploaded,
    required this.fileName,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7B2CBF);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: purple.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    uploaded ? Icons.check_rounded : icon,
                    color: purple,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: LocalizedText(
                    title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LocalizedText(
              description,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.black54,
              ),
            ),
            if (fileName != null) ...[
              const SizedBox(height: 10),
              LocalizedText(
                fileName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: onPressed,
                icon: Icon(
                  uploaded
                      ? Icons.check_circle_outline
                      : Icons.upload_file_outlined,
                ),
                label: LocalizedText(
                  buttonText,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 21, color: Colors.black54),
          SizedBox(width: 10),
          Expanded(
            child: LocalizedText(
              'Verification documents are private, stored on the Nisa local server, and used only for verification review.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
