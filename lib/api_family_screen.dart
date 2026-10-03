import 'package:flutter/material.dart';

import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';

import 'api_family_invitations_screen.dart';
import 'services/api_family_service.dart';

const _familyRoles = <String, String>{
  'father': 'Father',
  'mother': 'Mother',
  'brother': 'Brother',
  'sister': 'Sister',
  'guardian': 'Guardian',
  'other': 'Other',
};

/// Family records for the signed-in PostgreSQL account.
class ApiFamilyScreen extends StatefulWidget {
  const ApiFamilyScreen({super.key});

  @override
  State<ApiFamilyScreen> createState() => _ApiFamilyScreenState();
}

class _ApiFamilyScreenState extends State<ApiFamilyScreen> {
  List<Map<String, dynamic>> _members = const [];
  final Set<String> _removing = {};
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
      final members = await ApiFamilyService.getMembers();
      if (!mounted) return;
      setState(() {
        _members = members;
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

  Future<void> _invite() async {
    final draft = await showDialog<_FamilyDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _InviteFamilyDialog(),
    );
    if (draft == null || !mounted) return;
    try {
      await ApiFamilyService.createInvitation(
        name: draft.name,
        role: draft.role,
        email: draft.email,
        phone: draft.phone,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText(
            'Invitation created. It will appear in the recipient’s Nisa app when they sign in with that email.',
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
    }
  }

  Future<void> _remove(Map<String, dynamic> member) async {
    final id = member['id']?.toString() ?? '';
    if (id.isEmpty || !_removing.add(id)) return;
    final name = member['name']?.toString() ?? 'this person';
    final status = member['invitation_status']?.toString() ?? 'pending';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Remove family member?'),
        content: Text(
          status == 'pending'
              ? 'Remove $name and cancel the pending invitation?'
              : 'Remove $name and unlink this family connection?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      _removing.remove(id);
      return;
    }
    try {
      await ApiFamilyService.removeMember(id);
      if (!mounted) return;
      setState(
        () => _members.removeWhere((item) => item['id']?.toString() == id),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Family connection removed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      _removing.remove(id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('Family / Guardian'),
      actions: [
        IconButton(
          tooltip: AppLanguageService.translate('Incoming family invitations'),
          icon: const Icon(Icons.mark_email_unread_outlined),
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ApiFamilyInvitationsScreen(),
              ),
            );
            if (mounted) _load();
          },
        ),
        IconButton(
          tooltip: AppLanguageService.translate('Refresh'),
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _invite,
      icon: const Icon(Icons.person_add_alt_1),
      label: const LocalizedText('Invite member'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? _FamilyMessage(message: _error!, onRetry: _load)
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: LocalizedText(
                      'Invitations appear in Nisa when the recipient signs in with the invited email. No email or SMS is sent in this phase. Phone-only invitations cannot be accepted yet. Family information stays private and is not shown in discovery. Accepting does not grant a verification badge.',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: LocalizedText(
                      'No family members yet. Use Invite member to add a parent, guardian, or trusted family member.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ..._members.map(_memberCard),
              ],
            ),
          ),
  );

  Widget _memberCard(Map<String, dynamic> member) {
    final name = member['name']?.toString().trim() ?? '';
    final role = _familyRoles[member['role']?.toString()] ?? 'Family member';
    final status = member['invitation_status']?.toString() ?? 'pending';
    final linked = member['is_linked'] == true;
    final statusLabel = switch (status) {
      'accepted' when linked => 'Linked',
      'accepted' => 'Accepted',
      'email_confirmed' => 'Email confirmed',
      'declined' => 'Declined',
      'cancelled' => 'Cancelled',
      _ => 'Invitation pending',
    };
    final contacts = [member['email'], member['phone']]
        .where((value) => value != null && value.toString().isNotEmpty)
        .join(' • ');
    final id = member['id']?.toString() ?? '';
    final removing = _removing.contains(id);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(linked ? Icons.family_restroom : Icons.person_outline),
        ),
        title: Text(name.isEmpty ? 'Family member' : name),
        subtitle: LocalizedRichText(
          spanBuilder: () => TextSpan(
            children: [
              TextSpan(text: AppLanguageService.translate(role)),
              const TextSpan(text: ' • '),
              TextSpan(text: AppLanguageService.translate(statusLabel)),
              if (contacts.isNotEmpty) ...[
                const TextSpan(text: '\n'),
                TextSpan(text: contacts),
              ],
            ],
          ),
        ),
        isThreeLine: contacts.isNotEmpty,
        trailing: IconButton(
          tooltip: AppLanguageService.translate('Remove'),
          onPressed: removing ? null : () => _remove(member),
          icon: removing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}

class _FamilyDraft {
  final String name;
  final String role;
  final String email;
  final String phone;

  const _FamilyDraft(this.name, this.role, this.email, this.phone);
}

class _InviteFamilyDialog extends StatefulWidget {
  const _InviteFamilyDialog();

  @override
  State<_InviteFamilyDialog> createState() => _InviteFamilyDialogState();
}

class _InviteFamilyDialogState extends State<_InviteFamilyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  String _role = 'father';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      _FamilyDraft(
        _name.text.trim(),
        _role,
        _email.text.trim(),
        _phone.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const LocalizedText('Invite family / guardian'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: AppLanguageService.translate('Name'),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a name.'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: InputDecoration(
                labelText: AppLanguageService.translate('Role'),
              ),
              items: _familyRoles.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _role = value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: AppLanguageService.translate('Email (recommended)'),
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isNotEmpty &&
                    !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
                  return 'Enter a valid email address.';
                }
                if (text.isEmpty && _phone.text.trim().isEmpty) {
                  return 'Enter an email or phone number.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: AppLanguageService.translate(
                  'Phone (optional if email is provided)',
                ),
              ),
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                if (_email.text.trim().isEmpty && digits.isEmpty) {
                  return 'Enter an email or phone number.';
                }
                if (digits.isNotEmpty &&
                    (digits.length < 7 || digits.length > 15)) {
                  return 'Enter a phone number with 7 to 15 digits.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            const LocalizedText(
              'The recipient must sign in using this email to accept. Phone-only invitations cannot be accepted yet. No email or SMS is sent.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const LocalizedText('Cancel'),
      ),
      FilledButton(
        onPressed: _submit,
        child: const LocalizedText('Create invitation'),
      ),
    ],
  );
}

class _FamilyMessage extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _FamilyMessage({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LocalizedText(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const LocalizedText('Try again'),
          ),
        ],
      ),
    ),
  );
}
