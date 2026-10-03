import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';

import 'models/family_member.dart';
import 'services/app_state.dart';
import 'services/family_service.dart';

class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});

  Future<void> _showAddMember(BuildContext context) async {
    final uid = AppState.firebaseUser?.uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Please sign in again.')),
      );
      return;
    }

    final added = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddFamilyMemberDialog(
        ownerUid: uid,
        ownerName: AppState.currentUser?.name ?? 'Nisa Member',
      ),
    );

    if (!context.mounted) return;

    if (added == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText(
            'Family invitation created. The invited person can accept it '
            'after signing in to Nisa with the invited email address.',
          ),
        ),
      );
    }
  }

  static String _roleLabel(FamilyRole role) {
    switch (role) {
      case FamilyRole.father:
        return 'Father';
      case FamilyRole.mother:
        return 'Mother';
      case FamilyRole.brother:
        return 'Brother';
      case FamilyRole.sister:
        return 'Sister';
      case FamilyRole.guardian:
        return 'Guardian';
      case FamilyRole.other:
        return 'Other';
    }
  }

  static String _statusLabel(FamilyInvitationStatus status) {
    switch (status) {
      case FamilyInvitationStatus.pending:
        return 'Invitation pending';
      case FamilyInvitationStatus.emailConfirmed:
        return 'Email confirmed';
      case FamilyInvitationStatus.accepted:
        return 'Linked';
      case FamilyInvitationStatus.declined:
        return 'Declined';
      case FamilyInvitationStatus.cancelled:
        return 'Cancelled';
    }
  }

  Future<void> _removeMember(BuildContext context, FamilyMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Remove family member?'),
        content: LocalizedText(
          member.invitationStatus == FamilyInvitationStatus.pending
              ? 'Remove ${member.name} and cancel the pending invitation?'
              : 'Remove ${member.name} from your family list?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const LocalizedText('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await FamilyService.cancelAndDeleteMember(member);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Family member removed.')),
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
    final uid = AppState.firebaseUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Family / Guardian'),
        centerTitle: true,
        actions: const [LanguageSelectorButton()],
      ),
      floatingActionButton: uid == null || uid.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddMember(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: const LocalizedText('Invite Member'),
            ),
      body: uid == null || uid.isEmpty
          ? const Center(child: LocalizedText('You are not signed in.'))
          : StreamBuilder<List<FamilyMember>>(
              stream: FamilyService.watchMembers(uid),
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

                final members = snapshot.data!;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: [
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: LocalizedText(
                          'Invite a trusted adult family member or guardian. '
                          'For this phase, in-app acceptance works when the '
                          'invite uses the same email address as their Nisa '
                          'account. Nisa does not send an external email or '
                          'SMS yet.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (members.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(28),
                        child: LocalizedText(
                          'No family member is linked yet.\n\n'
                          'Tap Invite Member to create an invitation.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ...members.map(
                        (member) => Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(
                                member.invitationStatus ==
                                        FamilyInvitationStatus.accepted
                                    ? Icons.verified_user
                                    : Icons.family_restroom,
                              ),
                            ),
                            title: LocalizedText(member.name),
                            subtitle: LocalizedRichText(
                              spanBuilder: () => TextSpan(
                                children: [
                                  TextSpan(
                                    text: AppLanguageService.translate(
                                      _roleLabel(member.role),
                                    ),
                                  ),
                                  const TextSpan(text: ' • '),
                                  TextSpan(
                                    text: AppLanguageService.translate(
                                      _statusLabel(member.invitationStatus),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: AppLanguageService.translate('Remove'),
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _removeMember(context, member),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _AddFamilyMemberDialog extends StatefulWidget {
  final String ownerUid;
  final String ownerName;

  const _AddFamilyMemberDialog({
    required this.ownerUid,
    required this.ownerName,
  });

  @override
  State<_AddFamilyMemberDialog> createState() => _AddFamilyMemberDialogState();
}

class _AddFamilyMemberDialogState
    extends LanguageAwareState<_AddFamilyMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  FamilyRole _role = FamilyRole.father;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String _roleLabel(FamilyRole role) {
    switch (role) {
      case FamilyRole.father:
        return 'Father';
      case FamilyRole.mother:
        return 'Mother';
      case FamilyRole.brother:
        return 'Brother';
      case FamilyRole.sister:
        return 'Sister';
      case FamilyRole.guardian:
        return 'Guardian';
      case FamilyRole.other:
        return 'Other';
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await FamilyService.addMember(
        ownerUid: widget.ownerUid,
        ownerName: widget.ownerName,
        name: _nameController.text,
        role: _role,
        email: _emailController.text,
        phone: _phoneController.text,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const LocalizedText('Invite Family / Guardian'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Name'),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<FamilyRole>(
                initialValue: _role,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Role'),
                ),
                items: FamilyRole.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: LocalizedText(_roleLabel(value)),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _role = value);
                      },
              ),
              const SizedBox(height: 16),
              const LocalizedText(
                'Provide at least one contact method. Email enables the '
                'in-app acceptance flow in this phase.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                enabled: !_saving,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate(
                    'Email (recommended)',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                enabled: !_saving,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate(
                    'Phone (optional if email is provided)',
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                LocalizedText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const LocalizedText('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const LocalizedText('Create Invite'),
        ),
      ],
    );
  }
}
