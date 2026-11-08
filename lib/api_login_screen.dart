import 'widgets/google_sign_in_button.dart';
import 'presentation/nisa_premium/nisa_premium.dart';

import 'package:flutter/material.dart';

import 'services/api_auth_service.dart';
import 'services/app_language_service.dart';
import 'api_email_access_screen.dart';
import 'widgets/language_selector_button.dart';
import 'widgets/localized_text.dart';

class ApiLoginScreen extends StatefulWidget {
  final String? initialEmail;
  final bool accountAlreadyExists;

  const ApiLoginScreen({
    super.key,
    this.initialEmail,
    this.accountAlreadyExists = false,
  });

  @override
  State<ApiLoginScreen> createState() => _ApiLoginScreenState();
}

class _ApiLoginScreenState extends LanguageAwareState<ApiLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;
  bool _passwordSetupRequired = false;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail ?? '';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(Object error) {
    final message = error.toString().replaceFirst('Bad state: ', '');
    if (message.contains('Google sign-in was cancelled.')) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: LocalizedText(message)));
  }

  Future<void> _signIn() async {
    if (_busy) return;
    if (_emailController.text.trim().isEmpty) {
      _showError(StateError('Please enter your email.'));
      return;
    }
    if (_passwordController.text.isEmpty) {
      _showError(StateError('Please enter your password.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiAuthService.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      if (ApiAuthFailureCode.requiresPasswordSetup(error)) {
        setState(() => _passwordSetupRequired = true);
      } else {
        setState(() => _passwordSetupRequired = false);
        _showError(error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ApiAuthService.signInWithGoogle();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword({bool setPassword = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApiPasswordResetScreen(
          initialEmail: _emailController.text.trim(),
          setPasswordMode: setPassword,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Sign In'),
        actions: const [LanguageSelectorButton()],
      ),
      body: NisaPageBody(
        form: true,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              SizedBox(height: compact ? 4 : 20),
              Icon(
                Icons.lock_open_rounded,
                size: compact ? 40 : 68,
                color: Theme.of(context).colorScheme.primary,
              ),
              SizedBox(height: compact ? 8 : 20),
              const LocalizedText(
                'Welcome back',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const LocalizedText(
                'Sign in or create an account',
                textAlign: TextAlign.center,
              ),
              if (widget.accountAlreadyExists) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: LocalizedText(
                      'Account already exists. Please sign in.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Email'),
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passwordController,
                enabled: !_busy,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _signIn(),
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Password'),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: AppLanguageService.translate('Password'),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                  ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_passwordSetupRequired) {
                    setState(() => _passwordSetupRequired = false);
                  }
                },
              ),
              if (_passwordSetupRequired) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const LocalizedText('Email sign-in help'),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _resetPassword(setPassword: true),
                          child: const LocalizedText('Set your password'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: _busy ? null : _resetPassword,
                  child: const LocalizedText('Forgot password?'),
                ),
              ),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const LocalizedText('Sign In'),
                ),
              ),
              const SizedBox(height: 14),
              GoogleSignInButton(onPressed: _busy ? null : _signInWithGoogle),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const ApiEmailAccessScreen(),
                        ),
                      ),
                child: const LocalizedText('Create Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ApiPasswordResetScreen extends StatefulWidget {
  final String initialEmail;
  final bool setPasswordMode;

  const ApiPasswordResetScreen({
    super.key,
    required this.initialEmail,
    this.setPasswordMode = false,
  });

  @override
  State<ApiPasswordResetScreen> createState() => _ApiPasswordResetScreenState();
}

class _ApiPasswordResetScreenState
    extends LanguageAwareState<ApiPasswordResetScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_codeSent && _emailController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your email.');
      return;
    }
    if (_codeSent &&
        !RegExp(r'^\d{6}$').hasMatch(_codeController.text.trim())) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    if (_codeSent && _passwordController.text.length < 10) {
      setState(() => _error = 'Password must be at least 10 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_codeSent) {
        await ApiAuthService.requestPasswordReset(_emailController.text.trim());
        if (mounted) setState(() => _codeSent = true);
      } else {
        await ApiAuthService.resetPassword(
          email: _emailController.text.trim(),
          code: _codeController.text.trim(),
          password: _passwordController.text,
        );
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst('Bad state: ', '');
        setState(() => _error = message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: LocalizedText(message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: LocalizedText(
        widget.setPasswordMode ? 'Set your password' : 'Forgot password?',
      ),
      actions: const [LanguageSelectorButton()],
    ),
    body: NisaPageBody(
      form: true,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.lock_reset_rounded, size: 56),
            const SizedBox(height: 16),
            LocalizedText(
              widget.setPasswordMode ? 'Set your password' : 'Forgot password?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 24),
            TextField(
              controller: _emailController,
              enabled: !_codeSent && !_busy,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: AppLanguageService.translate('Email'),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_codeSent) ...[
              const LocalizedText(
                'If an account matches this email, a reset code will be sent.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _codeController,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Reset code'),
                  hintText: AppLanguageService.translate('Enter OTP'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passwordController,
                enabled: !_busy,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Password'),
                  border: const OutlineInputBorder(),
                ),
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
                  : LocalizedText(_codeSent ? 'Continue' : 'Send code'),
            ),
          ],
        ),
      ),
    ),
  );
}
