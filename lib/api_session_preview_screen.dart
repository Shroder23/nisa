import 'package:flutter/material.dart';

import '../widgets/localized_text.dart';

import 'api_discovery_screen.dart';
import 'api_incoming_interests_screen.dart';
import 'api_conversations_screen.dart';
import 'api_notifications_screen.dart';
import 'api_sent_interests_screen.dart';
import 'edit_profile_screen.dart';
import 'matrimonial_preferences_screen.dart';
import 'models/user_profile.dart';
import 'services/api_app_state.dart';

/// Temporary destination proving that an API session restores without Firebase.
class ApiSessionPreviewScreen extends StatefulWidget {
  final UserProfile profile;

  const ApiSessionPreviewScreen({super.key, required this.profile});

  @override
  State<ApiSessionPreviewScreen> createState() =>
      _ApiSessionPreviewScreenState();
}

class _ApiSessionPreviewScreenState extends State<ApiSessionPreviewScreen> {
  late UserProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
  }

  Future<void> _refreshProfile() async {
    try {
      final profile = await ApiAppState.loadCurrentProfile();
      if (mounted && profile != null) setState(() => _profile = profile);
    } catch (_) {
      // Keep the current preview visible if a refresh fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ApiAppState.currentAccount;
    final email = account?['email']?.toString() ?? _profile.email ?? '';
    final status = account?['account_status']?.toString() ?? 'unknown';
    final step = account?['registration_step']?.toString() ?? 'unknown';

    return Scaffold(
      appBar: AppBar(title: const LocalizedText('PostgreSQL session preview')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.cloud_done_outlined, size: 64),
            const SizedBox(height: 16),
            LocalizedText(
              'PostgreSQL sign-in is connected',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            _AccountRow(label: 'Email', value: email),
            _AccountRow(
              label: 'Profile',
              value: _profile.name.isEmpty ? 'Not created yet' : _profile.name,
            ),
            _AccountRow(label: 'Account status', value: status),
            _AccountRow(label: 'Registration step', value: step),
            const SizedBox(height: 24),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: LocalizedText(
                  'Recommendations, interests, and matched conversations use PostgreSQL. Other app screens are still being connected.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ApiDiscoveryScreen(currentUser: _profile),
                ),
              ),
              icon: const Icon(Icons.search),
              label: const LocalizedText('Browse recommendations'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ApiIncomingInterestsScreen(),
                ),
              ),
              icon: const Icon(Icons.favorite_outline),
              label: const LocalizedText('Review incoming interests'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ApiSentInterestsScreen(),
                ),
              ),
              icon: const Icon(Icons.outbox_outlined),
              label: const LocalizedText('View sent interests'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ApiConversationsScreen(),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const LocalizedText('Open messages'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ApiNotificationsScreen(),
                ),
              ),
              icon: const Icon(Icons.notifications_outlined),
              label: const LocalizedText('Open notifications'),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () async {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(profile: _profile),
                  ),
                );
                if (saved == true) await _refreshProfile();
              },
              icon: const Icon(Icons.edit_outlined),
              label: const LocalizedText('Edit profile'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => MatrimonialPreferencesScreen(
                      profile: _profile,
                      isEditing: true,
                    ),
                  ),
                );
                if (saved == true) await _refreshProfile();
              },
              icon: const Icon(Icons.tune),
              label: const LocalizedText('Edit preferences'),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () async {
                await ApiAppState.signOut();
              },
              icon: const Icon(Icons.logout_rounded),
              label: const LocalizedText('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  final String label;
  final String value;

  const _AccountRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(value),
  );
}
