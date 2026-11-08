import 'presentation/nisa_premium/nisa_premium.dart';

import 'package:flutter/material.dart';

import 'widgets/localized_text.dart';

/// Confirmation shown after a parent or wali submits verification evidence.
class ApiVerificationPendingScreen extends StatelessWidget {
  const ApiVerificationPendingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('Verification status')),
    body: NisaPageBody(
      form: true,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.hourglass_top_rounded,
                  size: 84,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 22),
                LocalizedText(
                  'Verification Pending',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                const LocalizedText(
                  'Your parent or wali verification was submitted successfully and is waiting for review by an authorized Nisa reviewer.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: LocalizedText(
                      'You do not need to submit the documents again. The Parent Verified badge will appear only after the review is approved.',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check),
                  label: const LocalizedText('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
