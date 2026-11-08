import 'presentation/nisa_premium/nisa_premium.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';

import 'models/family_invitation.dart';
import 'services/family_service.dart';

class FamilyInvitationsScreen extends StatelessWidget {
  const FamilyInvitationsScreen({super.key});

  String _roleLabel(String role) {
    switch (role) {
      case 'father':
        return 'Father';
      case 'mother':
        return 'Mother';
      case 'brother':
        return 'Brother';
      case 'sister':
        return 'Sister';
      case 'guardian':
        return 'Guardian';
      default:
        return 'Family member';
    }
  }

  Future<void> _respond(
    BuildContext context,
    FamilyInvitation invitation,
    bool accept,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: LocalizedText(
          accept ? 'Accept invitation?' : 'Decline invitation?',
        ),
        content: LocalizedText(
          accept
              ? 'Accept ${invitation.ownerName}\'s request to link you as '
                    '${_roleLabel(invitation.role).toLowerCase()}?'
              : 'Decline ${invitation.ownerName}\'s family invitation?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: LocalizedText(accept ? 'Accept' : 'Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await FamilyService.respondToInvitation(
        invitation: invitation,
        accept: accept,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText(
            accept
                ? 'Family invitation accepted.'
                : 'Family invitation declined.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Family Invitations'),
        centerTitle: true,
        actions: const [LanguageSelectorButton()],
      ),
      body: NisaPageBody(
        form: false,
        child: StreamBuilder<List<FamilyInvitation>>(
          stream: FamilyService.watchInvitationsForCurrentUser(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: LocalizedText(
                    'Something went wrong. Please try again.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final invitations = snapshot.data!;

            if (invitations.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: LocalizedText(
                    'No pending family invitations were found for your '
                    'signed-in email address.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: invitations.length,
              itemBuilder: (context, index) {
                final invitation = invitations[index];

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            child: Icon(Icons.family_restroom),
                          ),
                          title: LocalizedText(invitation.ownerName),
                          subtitle: LocalizedText(
                            'Invited you as {role}',
                            substitutions: {
                              'role': _roleLabel(invitation.role),
                            },
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    _respond(context, invitation, false),
                                child: const LocalizedText('Decline'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: () =>
                                    _respond(context, invitation, true),
                                child: const LocalizedText('Accept'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
