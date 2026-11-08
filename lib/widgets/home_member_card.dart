import 'package:flutter/material.dart';

import '../presentation/nisa_premium/nisa_premium.dart';

import '../models/candidate_profile.dart';
import '../models/interest.dart';
import '../services/app_language_service.dart';
import 'api_profile_photo.dart';
import 'localized_text.dart';

/// Compact Home presentation; all actions are owned by the existing dashboard.
class HomeMemberCard extends StatelessWidget {
  final CandidateProfile profile;
  final bool nearby;
  final InterestStatus? interestStatus;
  final bool existingInterest;
  final bool sendingInterest;
  final VoidCallback onOpen;
  final VoidCallback? onInterest;
  final VoidCallback? onBlock;
  final VoidCallback? onReport;

  const HomeMemberCard({
    super.key,
    required this.profile,
    required this.onOpen,
    this.nearby = false,
    this.interestStatus,
    this.existingInterest = false,
    this.sendingInterest = false,
    this.onInterest,
    this.onBlock,
    this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final connected =
        existingInterest ||
        interestStatus == InterestStatus.pending ||
        interestStatus == InterestStatus.accepted;
    final label = sendingInterest
        ? 'Sending…'
        : connected
        ? 'Interest sent'
        : interestStatus == InterestStatus.cancelled
        ? 'Send interest again'
        : 'Send interest';
    final safety = PopupMenuButton<String>(
      tooltip: AppLanguageService.translate('Safety options'),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      iconSize: 18,
      onSelected: (value) {
        if (value == 'block') onBlock?.call();
        if (value == 'report') onReport?.call();
      },
      itemBuilder: (_) => [
        if (onBlock != null)
          const PopupMenuItem(value: 'block', child: LocalizedText('Block')),
        if (onReport != null)
          const PopupMenuItem(value: 'report', child: LocalizedText('Report')),
      ],
    );
    final detail = [profile.education, profile.profession]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .map(AppLanguageService.translate)
        .join(' · ');
    return LayoutBuilder(
      builder: (context, box) => NisaProfileCard(
        key: ValueKey('${nearby ? 'nearby' : 'recommendation'}-${profile.id}'),
        title:
            '${profile.name}, ${AppLanguageService.formatAgeNumber(profile.age)}',
        location: profile.city,
        detail: detail,
        compact: nearby,
        photo: ApiProfilePhoto(
          imageUrl: profile.profilePhoto,
          fallbackText: profile.name,
          radius: nearby ? box.maxWidth / 2 : 40,
          borderRadius: BorderRadius.circular(14),
          enablePreview: false,
        ),
        openLabel: AppLanguageService.translate('View Profile'),
        onOpen: onOpen,
        actionLabel: AppLanguageService.translate(label),
        actionIcon: connected ? Icons.favorite : Icons.favorite_border,
        actionBusy: sendingInterest,
        onAction: connected ? null : onInterest,
        safetyAction: onBlock != null || onReport != null ? safety : null,
      ),
    );
  }
}
