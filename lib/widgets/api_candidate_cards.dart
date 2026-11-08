import 'package:flutter/material.dart';

import '../models/candidate_profile.dart';
import '../models/interest.dart';
import '../services/app_language_service.dart';
import 'localized_text.dart';
import 'home_member_card.dart';

class ApiCandidateProfileCard extends StatelessWidget {
  final CandidateProfile profile;
  final InterestStatus? interestStatus;
  final bool existingInterest;
  final bool sendingInterest;
  final bool showRecommendationReasons;
  final VoidCallback onOpen;
  final VoidCallback? onInterest;
  final VoidCallback? onBlock;
  final VoidCallback? onReport;

  const ApiCandidateProfileCard({
    super.key,
    required this.profile,
    required this.onOpen,
    this.interestStatus,
    this.existingInterest = false,
    this.sendingInterest = false,
    this.showRecommendationReasons = false,
    this.onInterest,
    this.onBlock,
    this.onReport,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HomeMemberCard(
        profile: profile,
        nearby: true,
        interestStatus: interestStatus,
        existingInterest: existingInterest,
        sendingInterest: sendingInterest,
        onOpen: onOpen,
        onInterest: onInterest,
        onBlock: onBlock,
        onReport: onReport,
      ),
      if (showRecommendationReasons && profile.recommendationReasons.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: profile.recommendationReasons
                .take(2)
                .map((reason) => Chip(label: LocalizedText(reason)))
                .toList(),
          ),
        ),
    ],
  );
}

class ApiNearbyProfileCard extends StatelessWidget {
  static const double cardWidth = 116;
  static const double cardHeight = 182;
  static double widthFor(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return MediaQuery.textScalerOf(context).scale(16) > 22
        ? 176
        : ((width - 64) / 3).clamp(112, 152).toDouble();
  }

  static double heightFor(BuildContext context) =>
      widthFor(context) + 76 + MediaQuery.textScalerOf(context).scale(72);

  static double contentHeight(BuildContext context, CandidateProfile profile) {
    final width = widthFor(context);
    double textHeight(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: width - 20);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return width +
        36 +
        textHeight(
          '${profile.name}, ${AppLanguageService.formatAgeNumber(profile.age)}',
          Theme.of(context).textTheme.titleSmall,
        ) +
        textHeight(profile.city, Theme.of(context).textTheme.bodySmall);
  }

  final CandidateProfile profile;
  final InterestStatus? interestStatus;
  final bool existingInterest;
  final bool sendingInterest;
  final VoidCallback onOpen;
  final VoidCallback? onInterest;
  final VoidCallback? onBlock;
  final VoidCallback? onReport;
  const ApiNearbyProfileCard({
    super.key,
    required this.profile,
    required this.onOpen,
    this.interestStatus,
    this.existingInterest = false,
    this.sendingInterest = false,
    this.onInterest,
    this.onBlock,
    this.onReport,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: widthFor(context),
    child: HomeMemberCard(
      profile: profile,
      nearby: true,
      interestStatus: interestStatus,
      existingInterest: existingInterest,
      sendingInterest: sendingInterest,
      onOpen: onOpen,
      onInterest: onInterest,
      onBlock: onBlock,
      onReport: onReport,
    ),
  );
}

class ApiInlineState extends StatelessWidget {
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool busy;

  const ApiInlineState({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.actionLabel,
    this.onAction,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(message),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : onAction,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: LocalizedText(actionLabel),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
