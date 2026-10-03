import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';

import 'create_account_screen.dart';
import 'login_screen.dart';
import 'services/auth_service.dart';

class AccountTypeScreen extends StatelessWidget {
  final String? existingUid;
  final String? existingEmail;
  final String? existingAccountType;

  const AccountTypeScreen({
    super.key,
    this.existingUid,
    this.existingEmail,
    this.existingAccountType,
  });

  bool get isExistingAccount {
    return existingUid != null && existingUid!.isNotEmpty;
  }

  void _openCreateAccount(BuildContext context, bool isVerified) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateAccountScreen(
          isVerified: isVerified,
          existingUid: existingUid,
          existingEmail: existingEmail,
          existingAccountType: existingAccountType,
        ),
      ),
    );
  }

  Future<void> _useDifferentAccount(BuildContext context) async {
    await AuthService.signOut();
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: LocalizedText(
          isExistingAccount ? 'Resume Your Account' : 'Choose Your Account',
        ),
        centerTitle: true,
        leading: IconButton(
          tooltip: AppLanguageService.translate('Back'),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        actions: const [LanguageSelectorButton()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LocalizedText(
                isExistingAccount
                    ? 'Complete your Nisa profile'
                    : 'How would you like to join Nisa?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              LocalizedText(
                isExistingAccount
                    ? 'Your Firebase account already exists. '
                          'Choose your account type to continue setup.'
                    : 'Choose the account type that best suits you.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: Colors.black54,
                ),
              ),

              const SizedBox(height: 24),

              AccountCard(
                icon: Icons.verified_rounded,
                title: 'Parent/guardian verified account',
                subtitle: 'Build trust through family verification',
                description:
                    'A parent or guardian completes Nisa’s family '
                    'verification process. This badge does not verify '
                    'the member’s own photo or government ID.',
                features: const [
                  'Family verification badge on your profile',
                  'Parent identification document',
                  'Parent confirmation video',
                  'Greater trust with potential matches',
                ],
                buttonText: 'Choose Verified',
                isVerified: true,
                onPressed: () {
                  _openCreateAccount(context, true);
                },
              ),

              const SizedBox(height: 16),

              AccountCard(
                icon: Icons.person_outline_rounded,
                title: 'Unverified Account',
                subtitle: 'Start using Nisa immediately',
                description:
                    'Create your profile and use Nisa without '
                    'completing verification.',
                features: const [
                  'Create your personal profile',
                  'Discover potential matches',
                  'Use Nisa normally',
                  'No verification badge',
                ],
                buttonText: 'Choose Unverified',
                isVerified: false,
                onPressed: () {
                  _openCreateAccount(context, false);
                },
              ),

              const SizedBox(height: 24),

              if (isExistingAccount)
                const LocalizedText(
                  'You are already signed in. '
                  'Nisa will continue your existing account '
                  'instead of creating another one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black45),
                )
              else
                const LocalizedText(
                  'You can learn more about verification before '
                  'making your choice.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black45),
                ),

              if (isExistingAccount) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => _useDifferentAccount(context),
                  icon: const Icon(Icons.switch_account_outlined),
                  label: const LocalizedText('Use a different account'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AccountCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final List<String> features;
  final String buttonText;
  final bool isVerified;
  final VoidCallback onPressed;

  const AccountCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.features,
    required this.buttonText,
    required this.isVerified,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7B2CBF);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isVerified
            ? purple.withValues(alpha: 0.06)
            : Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isVerified
              ? purple.withValues(alpha: 0.30)
              : Colors.grey.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isVerified ? purple : Colors.grey.shade700,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 27),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: LocalizedText(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.check_circle,
                            color: purple,
                            size: 18,
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 3),

                    LocalizedText(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isVerified ? purple : Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          LocalizedText(
            description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.black54,
            ),
          ),

          const SizedBox(height: 13),

          ...features.map((feature) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_rounded,
                    size: 17,
                    color: isVerified ? purple : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: LocalizedText(
                      feature,
                      style: const TextStyle(fontSize: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 7),

          SizedBox(
            width: double.infinity,
            height: 46,
            child: isVerified
                ? FilledButton(
                    onPressed: onPressed,
                    child: LocalizedText(buttonText),
                  )
                : OutlinedButton(
                    onPressed: onPressed,
                    child: LocalizedText(buttonText),
                  ),
          ),
        ],
      ),
    );
  }
}
