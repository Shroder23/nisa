import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../widgets/localized_text.dart';

import 'services/app_language_service.dart';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'services/api_verification_service.dart';
import 'services/screen_security_service.dart';

class ApiAdminVerificationScreen extends StatefulWidget {
  const ApiAdminVerificationScreen({super.key});

  @override
  State<ApiAdminVerificationScreen> createState() =>
      _ApiAdminVerificationScreenState();
}

class _ApiAdminVerificationScreenState
    extends State<ApiAdminVerificationScreen> {
  late Future<List<Map<String, dynamic>>> _queue =
      ApiVerificationService.getReviewQueue();

  Future<void> _refresh() async {
    final request = ApiVerificationService.getReviewQueue();
    setState(() {
      _queue = request;
    });
    await request;
  }

  Future<void> _open(Map<String, dynamic> request) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _VerificationReviewDetail(request: request),
      ),
    );
    if (changed == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('Verification review'),
      actions: [
        IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _queue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: LocalizedText('Something went wrong. Please try again.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final requests = snapshot.data!;
        if (requests.isEmpty) {
          return const Center(
            child: LocalizedText(
              'No verification requests are waiting for review.',
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              final name =
                  request['applicant_name']?.toString() ?? 'Nisa member';
              final relation =
                  request['guardian_relationship']?.toString() ?? 'guardian';
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.verified_user_outlined),
                ),
                title: Text(name),
                subtitle: LocalizedRichText(
                  spanBuilder: () => TextSpan(
                    children: [
                      TextSpan(
                        text: request['applicant_email']?.toString() ?? '',
                      ),
                      const TextSpan(text: '\n'),
                      TextSpan(
                        text: request['guardian_name']?.toString() ?? '',
                      ),
                      const TextSpan(text: ' · '),
                      TextSpan(text: AppLanguageService.translate(relation)),
                    ],
                  ),
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(request),
              );
            },
          ),
        );
      },
    ),
  );
}

class _VerificationReviewDetail extends StatefulWidget {
  final Map<String, dynamic> request;

  const _VerificationReviewDetail({required this.request});

  @override
  State<_VerificationReviewDetail> createState() =>
      _VerificationReviewDetailState();
}

class _VerificationReviewDetailState extends State<_VerificationReviewDetail> {
  Uint8List? _idImage;
  Uint8List? _authorityImage;
  VideoPlayerController? _videoController;
  File? _temporaryVideo;
  bool _loading = true;
  bool _reviewing = false;
  String? _error;

  String get _id => widget.request['id'].toString();

  @override
  void initState() {
    super.initState();
    unawaited(ScreenSecurityService.setScreenshotBlocked(true));
    _loadEvidence();
  }

  Future<void> _loadEvidence() async {
    File? video;
    VideoPlayerController? controller;
    try {
      final idResponse = await ApiVerificationService.getEvidence(_id, 'id');
      final videoResponse = await ApiVerificationService.getEvidence(
        _id,
        'video',
      );
      Uint8List? authorityBytes;
      if (widget.request['has_authority_proof'] == true) {
        final authorityResponse = await ApiVerificationService.getEvidence(
          _id,
          'authority',
        );
        authorityBytes = authorityResponse.bodyBytes;
      }
      final directory = await getTemporaryDirectory();
      final disposition = videoResponse.headers['content-disposition'] ?? '';
      final ext =
          RegExp(r'filename="verification_video\.(mp4|mov|webm)"')
              .firstMatch(disposition)
              ?.group(1) ??
          'mp4';
      video = File('${directory.path}/nisa-review-$_id.$ext');
      _temporaryVideo = video;
      await video.writeAsBytes(videoResponse.bodyBytes, flush: true);
      controller = VideoPlayerController.file(video);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        await video.delete();
        _temporaryVideo = null;
        return;
      }
      setState(() {
        _idImage = idResponse.bodyBytes;
        _authorityImage = authorityBytes;
        _temporaryVideo = video;
        _videoController = controller;
        _loading = false;
      });
      controller = null;
      video = null;
    } catch (error) {
      await controller?.dispose();
      if (video != null && await video.exists()) await video.delete();
      _temporaryVideo = null;
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    final file = _temporaryVideo;
    if (file != null) file.delete().ignore();
    unawaited(ScreenSecurityService.setScreenshotBlocked(false));
    super.dispose();
  }

  Future<String?> _askReason(String title) async {
    var reasonText = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          onChanged: (value) => reasonText = value,
          minLines: 2,
          maxLines: 5,
          maxLength: 2000,
          decoration: InputDecoration(
            labelText: AppLanguageService.translate(
              'Private reviewer note (the applicant sees status only)',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, reasonText.trim()),
            child: const LocalizedText('Continue'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return null;
    return result;
  }

  Future<void> _review(String decision) async {
    String notes = '';
    if (decision != 'approve') {
      final reason = await _askReason(
        decision == 'reject' ? 'Reject request' : 'Request new evidence',
      );
      if (reason == null) return;
      notes = reason;
    }
    setState(() => _reviewing = true);
    try {
      await ApiVerificationService.review(
        _id,
        decision: decision,
        notes: notes,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  Widget _evidenceImage(String title, Uint8List? bytes) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (bytes == null)
            const LocalizedText('No document provided.')
          else
            Image.memory(bytes, fit: BoxFit.contain),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final controller = _videoController;
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('Review evidence')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: LocalizedText('Something went wrong. Please try again.'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                LocalizedRichText(
                  spanBuilder: () => TextSpan(
                    children: [
                      TextSpan(
                        text:
                            widget.request['applicant_name']?.toString() ?? '',
                      ),
                      const TextSpan(text: ' · '),
                      TextSpan(
                        text:
                            widget.request['applicant_email']?.toString() ?? '',
                      ),
                    ],
                  ),
                ),
                LocalizedRichText(
                  spanBuilder: () => TextSpan(
                    children: [
                      TextSpan(
                        text: AppLanguageService.translate('Parent/wali'),
                      ),
                      const TextSpan(text: ': '),
                      TextSpan(
                        text: widget.request['guardian_name']?.toString() ?? '',
                      ),
                      const TextSpan(text: ' ('),
                      TextSpan(
                        text: AppLanguageService.translate(
                          widget.request['guardian_relationship']?.toString() ??
                              'guardian',
                        ),
                      ),
                      const TextSpan(text: ')'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _evidenceImage('Parent or wali ID', _idImage),
                if (_authorityImage != null)
                  _evidenceImage('Wali authority evidence', _authorityImage),
                Card(
                  child: Column(
                    children: [
                      const ListTile(
                        title: LocalizedText('Consent video (10–30 seconds)'),
                      ),
                      if (controller != null && controller.value.isInitialized)
                        AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                      if (controller != null)
                        IconButton(
                          icon: Icon(
                            controller.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                          onPressed: () => setState(
                            () => controller.value.isPlaying
                                ? controller.pause()
                                : controller.play(),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _reviewing ? null : () => _review('approve'),
                  icon: const Icon(Icons.check),
                  label: const LocalizedText('Approve · Parent Verified'),
                ),
                OutlinedButton(
                  onPressed: _reviewing
                      ? null
                      : () => _review('request_resubmission'),
                  child: const LocalizedText('Request resubmission'),
                ),
                TextButton(
                  onPressed: _reviewing ? null : () => _review('reject'),
                  child: const LocalizedText('Reject'),
                ),
              ],
            ),
    );
  }
}
