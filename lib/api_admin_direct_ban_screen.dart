import 'presentation/nisa_premium/nisa_premium.dart';

import 'package:flutter/material.dart';

import 'services/api_safety_service.dart';
import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';

class ApiAdminDirectBanScreen extends StatefulWidget {
  const ApiAdminDirectBanScreen({super.key});
  @override
  State<ApiAdminDirectBanScreen> createState() =>
      _ApiAdminDirectBanScreenState();
}

class _ApiAdminDirectBanScreenState extends State<ApiAdminDirectBanScreen> {
  final _uid = TextEditingController();
  final _reason = TextEditingController();
  final _phone = TextEditingController();
  bool _denyEmail = false;
  bool _busy = false;
  @override
  void dispose() {
    _uid.dispose();
    _reason.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _ban() async {
    final uid = _uid.text.trim();
    final reason = _reason.text.trim();
    if (uid.isEmpty || reason.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText('Please complete all required fields.'),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('Permanent ban'),
        content: const LocalizedText('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LocalizedText('Permanent ban'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiSafetyService.permanentlyBanUser(
        userId: uid,
        reason: reason,
        denyEmail: _denyEmail,
        denyPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: LocalizedText('Action taken')));
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('Permanent ban')),
    body: NisaPageBody(
      form: true,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: _uid,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: AppLanguageService.translate('User ID'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reason,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: AppLanguageService.translate('Reason'),
            ),
          ),
          CheckboxListTile(
            value: _denyEmail,
            contentPadding: EdgeInsets.zero,
            title: const LocalizedText(
              'Block this email from registering again',
            ),
            onChanged: (value) => setState(() => _denyEmail = value ?? false),
          ),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: AppLanguageService.translate(
                'Phone number to block (optional)',
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _ban,
            icon: const Icon(Icons.gavel),
            label: LocalizedText(_busy ? 'Please wait…' : 'Permanent ban'),
          ),
        ],
      ),
    ),
  );
}
