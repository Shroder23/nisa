import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/api_auth_service.dart';
import 'services/app_language_service.dart';
import 'api_login_screen.dart';
import 'widgets/language_selector_button.dart';
import 'widgets/localized_text.dart';

/// Passwordless email access for the PostgreSQL-backed app flow.
class ApiEmailAccessScreen extends StatefulWidget {
  const ApiEmailAccessScreen({super.key});

  @override
  State<ApiEmailAccessScreen> createState() => _ApiEmailAccessScreenState();
}

class _ApiEmailAccessScreenState
    extends LanguageAwareState<ApiEmailAccessScreen> {
  static const _resendCooldown = 60;
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  Timer? _cooldownTimer;
  bool _codeRequested = false;
  bool _busy = false;
  int _secondsLeft = 0;
  String? _error;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _validEmail {
    final email = _emailController.text.trim();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _secondsLeft = _resendCooldown);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_codeRequested && !_validEmail) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (!_codeRequested && _passwordController.text.length < 10) {
      setState(() => _error = 'Password must be at least 10 characters.');
      return;
    }
    if (!_codeRequested &&
        _passwordController.text != _confirmPasswordController.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    if (_codeRequested &&
        !RegExp(r'^\d{6}$').hasMatch(_codeController.text.trim())) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_codeRequested) {
        final existing = await ApiAuthService.emailExists(
          _emailController.text.trim(),
        );
        if (!mounted) return;
        if (existing) {
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ApiLoginScreen(
                initialEmail: _emailController.text.trim(),
                accountAlreadyExists: true,
              ),
            ),
          );
          return;
        }
        await ApiAuthService.requestEmailCode(_emailController.text.trim());
        if (!mounted) return;
        setState(() => _codeRequested = true);
        _startCooldown();
      } else {
        await ApiAuthService.verifyEmailCode(
          email: _emailController.text.trim(),
          code: _codeController.text.trim(),
          password: _passwordController.text,
        );
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy || !_codeRequested || _secondsLeft > 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiAuthService.requestEmailCode(_emailController.text.trim());
      if (!mounted) return;
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText('Verification code sent. Check your email.'),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeEmail() {
    _cooldownTimer?.cancel();
    setState(() {
      _codeRequested = false;
      _secondsLeft = 0;
      _error = null;
      _codeController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
    });
  }

  Future<void> _showHelp() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Email sign-in help'),
        content: const LocalizedText(
          'If the code is missing, check spam. Request another after the countdown.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const LocalizedText('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resendLabel = _secondsLeft > 0
        ? '${AppLanguageService.translate('Resend code')} (${_secondsLeft}s)'
        : AppLanguageService.translate('Resend code');
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Continue with email'),
        actions: [
          const LanguageSelectorButton(),
          IconButton(
            tooltip: AppLanguageService.translate('Help'),
            onPressed: _showHelp,
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.mark_email_read_outlined, size: 56),
            const SizedBox(height: 16),
            LocalizedText(
              _codeRequested
                  ? 'Enter your verification code'
                  : 'Sign in or create an account',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 24),
            TextField(
              controller: _emailController,
              enabled: !_codeRequested && !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: _codeRequested
                  ? TextInputAction.next
                  : TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: AppLanguageService.translate('Email'),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                if (!_codeRequested) unawaited(_submit());
              },
            ),
            if (!_codeRequested) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                enabled: !_busy,
                obscureText: true,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Password'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                enabled: !_busy,
                obscureText: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Confirm password'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            if (_codeRequested) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('6-digit code'),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy || _secondsLeft > 0 ? null : _resend,
                    child: Text(resendLabel),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : _changeEmail,
                    child: const LocalizedText('Change email'),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              LocalizedText(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : LocalizedText(
                      _codeRequested ? 'Verify and continue' : 'Send code',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
