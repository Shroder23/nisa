import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'services/api_app_state.dart';
import 'widgets/localized_text.dart';

class ApiAccountRestrictionScreen extends StatelessWidget {
  const ApiAccountRestrictionScreen({
    super.key,
    required this.restriction,
    required this.onSignOut,
  });

  final ApiAccountRestrictionException restriction;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final expiryText = DateFormat.yMMMMd().add_jm().format(
      restriction.expiresAt.toLocal(),
    );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const LocalizedText('Account restriction active'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.gpp_bad_outlined,
                        size: 52,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      const LocalizedText(
                        'Temporary account ban',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      const LocalizedText('Moderation notice'),
                      const SizedBox(height: 8),
                      SelectableText(restriction.notice),
                      const SizedBox(height: 20),
                      const LocalizedText('Restriction ends'),
                      const SizedBox(height: 4),
                      Text(expiryText),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => onSignOut(),
                        icon: const Icon(Icons.logout),
                        label: const LocalizedText('Sign out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
