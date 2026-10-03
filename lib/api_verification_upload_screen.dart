import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';

import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'services/api_verification_service.dart';

class ApiVerificationUploadScreen extends StatefulWidget {
  const ApiVerificationUploadScreen({super.key});

  @override
  State<ApiVerificationUploadScreen> createState() =>
      _ApiVerificationUploadScreenState();
}

class _ApiVerificationUploadScreenState
    extends State<ApiVerificationUploadScreen> {
  final _nameController = TextEditingController();
  final _picker = ImagePicker();
  String _relationship = 'mother';
  String _reviewerGenderPreference = 'any';
  File? _guardianId;
  File? _authorityProof;
  File? _video;
  bool _consentConfirmed = false;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<File?> _pickDocument() async {
    final selected = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
    );
    final path = selected?.path;
    return path == null ? null : File(path);
  }

  Future<void> _pickVideo() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const LocalizedText('Record the confirmation video'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const LocalizedText('Choose an existing video'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) {
      return;
    }
    final selected = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 30),
    );
    if (selected == null) return;
    final file = File(selected.path);
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      final duration = controller.value.duration.inMilliseconds;
      if (duration < 10000 || duration > 30000) {
        throw StateError(
          'Record a confirmation video that is 10 to 30 seconds long.',
        );
      }
      if (mounted) setState(() => _video = file);
    } catch (error) {
      if (mounted) _showError(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      await controller.dispose();
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_nameController.text.trim().isEmpty ||
        _guardianId == null ||
        _video == null ||
        (_relationship == 'wali' && _authorityProof == null) ||
        !_consentConfirmed) {
      _showError(
        'Complete each required field and confirm the consent statement.',
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiVerificationService.submit(
        guardianName: _nameController.text,
        relationship: _relationship,
        guardianId: _guardianId!,
        confirmationVideo: _video!,
        authorityProof: _relationship == 'wali' ? _authorityProof : null,
        reviewerGenderPreference: _reviewerGenderPreference,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      final message = error.toString().replaceFirst('Bad state: ', '');
      if (mounted && message.toLowerCase().contains('already under review')) {
        Navigator.pop(context, true);
      } else if (mounted) {
        _showError(message);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: LocalizedText(message)));
  }

  Widget _fileRow(
    String title,
    File? file,
    VoidCallback onTap, {
    bool required = true,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(file == null ? Icons.upload_file : Icons.check_circle),
        title: LocalizedText(title),
        subtitle: Text(
          file?.path.split(Platform.pathSeparator).last ??
              (required ? 'Required' : 'Optional'),
        ),
        trailing: TextButton(
          onPressed: onTap,
          child: Text(file == null ? 'Choose' : 'Change'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('Parent Verification')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const LocalizedText(
            'You must be 18 or older and have at least one profile photo. Your ID and video are private and can only be opened by an authorized Nisa reviewer. Approval adds the “Parent Verified” badge; it confirms this review and does not guarantee character or suitability.',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _nameController,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: AppLanguageService.translate('Parent or wali name'),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _relationship,
            decoration: InputDecoration(
              labelText: AppLanguageService.translate('Relationship'),
            ),
            items: const [
              DropdownMenuItem(value: 'mother', child: LocalizedText('Mother')),
              DropdownMenuItem(value: 'father', child: LocalizedText('Father')),
              DropdownMenuItem(
                value: 'wali',
                child: LocalizedText('Alternate wali / guardian'),
              ),
            ],
            onChanged: _submitting
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _relationship = value);
                    }
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _reviewerGenderPreference,
            decoration: InputDecoration(
              labelText: AppLanguageService.translate(
                'Documents should be reviewed by',
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'male', child: LocalizedText('Male')),
              DropdownMenuItem(value: 'female', child: LocalizedText('Female')),
              DropdownMenuItem(value: 'any', child: LocalizedText('Any')),
            ],
            onChanged: _submitting
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _reviewerGenderPreference = value);
                    }
                  },
          ),
          const SizedBox(height: 12),
          _fileRow('Parent or wali ID document', _guardianId, () async {
            final file = await _pickDocument();
            if (file != null && mounted) {
              setState(() => _guardianId = file);
            }
          }),
          if (_relationship == 'wali')
            _fileRow(
              'Wali relationship or authority proof',
              _authorityProof,
              () async {
                final file = await _pickDocument();
                if (file != null && mounted) {
                  setState(() => _authorityProof = file);
                }
              },
            ),
          _fileRow('10 to 30 second confirmation video', _video, _pickVideo),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: LocalizedText(
                'The parent or wali should say their name and relationship, your name, confirm you are their son or daughter, and confirm they know you are seeking a spouse through Nisa and consent to being involved.',
              ),
            ),
          ),
          CheckboxListTile(
            value: _consentConfirmed,
            onChanged: _submitting
                ? null
                : (value) => setState(() => _consentConfirmed = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: const LocalizedText(
              'The parent or wali knows about and consents to this verification submission.',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_outline),
            label: Text(
              _submitting ? 'Submitting securely…' : 'Submit for review',
            ),
          ),
        ],
      ),
    );
  }
}
