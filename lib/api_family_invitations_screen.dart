import 'package:flutter/material.dart';

import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';

import 'services/api_family_service.dart';

const _roleNames = <String, String>{
  'father': 'father',
  'mother': 'mother',
  'brother': 'brother',
  'sister': 'sister',
  'guardian': 'guardian',
  'other': 'family member',
};

/// In-app invitations addressed to the signed-in account's verified email.
class ApiFamilyInvitationsScreen extends StatefulWidget {
  const ApiFamilyInvitationsScreen({super.key});

  @override
  State<ApiFamilyInvitationsScreen> createState() =>
      _ApiFamilyInvitationsScreenState();
}

class _ApiFamilyInvitationsScreenState
    extends State<ApiFamilyInvitationsScreen> {
  List<Map<String, dynamic>> _invitations = const [];
  final Set<String> _responding = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final invitations = await ApiFamilyService.getIncomingInvitations();
      if (!mounted) return;
      setState(() {
        _invitations = invitations;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _respond(
    Map<String, dynamic> invitation, {
    required bool accept,
  }) async {
    final id = invitation['id']?.toString() ?? '';
    if (id.isEmpty || !_responding.add(id)) return;
    setState(() {});
    try {
      await ApiFamilyService.respondToInvitation(id, accept: accept);
      if (!mounted) return;
      setState(() => _invitations.removeWhere((item) => item['id'] == id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept ? 'Family invitation accepted.' : 'Invitation declined.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      _responding.remove(id);
      if (mounted) setState(() {});
    }
  }

  Future<bool> _confirm(
    Map<String, dynamic> invitation, {
    required bool accept,
  }) async {
    final role = _roleNames[invitation['role']?.toString()] ?? 'family member';
    final owner = invitation['owner_name']?.toString().trim();
    final ownerName = owner?.isNotEmpty == true ? owner! : 'A Nisa member';
    final previouslyConfirmed = invitation['status'] == 'email_confirmed';
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(accept ? 'Accept invitation?' : 'Decline invitation?'),
        content: Text(
          accept
              ? previouslyConfirmed
                    ? 'You previously confirmed this invitation by email. Accept now to link your Nisa account as $ownerName’s $role. This does not provide access to private profile details or give you a verification badge.'
                    : 'Accept $ownerName’s request to link you as their $role? This confirms your consent to be listed. It does not provide access to private profile details or give you a verification badge.'
              : 'Decline $ownerName’s family invitation?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(accept ? 'Accept' : 'Decline'),
          ),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('Family invitations'),
      actions: [
        IconButton(
          tooltip: AppLanguageService.translate('Refresh'),
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? _InvitationMessage(message: _error!, onRetry: _load)
        : _invitations.isEmpty
        ? const _InvitationMessage(
            message: 'No pending family invitations were found for your signed-in email address.',
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: _invitations.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _invitationCard(_invitations[index]),
            ),
          ),
  );

  Widget _invitationCard(Map<String, dynamic> invitation) {
    final owner = invitation['owner_name']?.toString().trim();
    final ownerName = owner?.isNotEmpty == true ? owner! : 'A Nisa member';
    final role = _roleNames[invitation['role']?.toString()] ?? 'family member';
    final memberName = invitation['member_name']?.toString().trim() ?? '';
    final id = invitation['id']?.toString() ?? '';
    final busy = _responding.contains(id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.family_restroom)),
              title: Text(ownerName),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocalizedText(
                    'Invited you as {role}',
                    substitutions: {'role': AppLanguageService.translate(role)},
                  ),
                  if (memberName.isNotEmpty) Text(memberName),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (await _confirm(invitation, accept: false) &&
                                mounted) {
                              await _respond(invitation, accept: false);
                            }
                          },
                    child: const LocalizedText('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (await _confirm(invitation, accept: true) &&
                                mounted) {
                              await _respond(invitation, accept: true);
                            }
                          },
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const LocalizedText('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitationMessage extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;

  const _InvitationMessage({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LocalizedText(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const LocalizedText('Try again'),
            ),
          ],
        ],
      ),
    ),
  );
}
