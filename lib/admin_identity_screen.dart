import 'presentation/nisa_premium/nisa_premium.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AdminIdentityScreen extends StatelessWidget {
  const AdminIdentityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Admin Identity'),
        actions: const [LanguageSelectorButton()],
      ),
      body: NisaPageBody(
        form: true,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LocalizedText(
                'Firebase administrator UID',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              SelectableText(uid.isEmpty ? 'Not signed in' : uid),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: uid.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: uid));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: LocalizedText('Admin UID copied.'),
                          ),
                        );
                      },
                icon: const Icon(Icons.copy),
                label: const LocalizedText('Copy UID'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
