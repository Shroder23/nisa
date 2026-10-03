import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'services/email_otp_service.dart';
import 'services/app_language_service.dart';

class EmailOtpScreen extends StatefulWidget {
  final String email;

  const EmailOtpScreen({super.key, required this.email});

  @override
  State<EmailOtpScreen> createState() => _EmailOtpScreenState();
}

class _EmailOtpScreenState extends LanguageAwareState<EmailOtpScreen> {
  static const _codeLength = 6;

  final _code = TextEditingController();
  Timer? _countdownTimer;
  Timer? _caretTimer;
  int _seconds = 60;
  bool _busy = false;
  bool _closing = false;
  bool _caretVisible = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(_handleCodeChanged);
    _startCountdown();
    _caretTimer = Timer.periodic(const Duration(milliseconds: 520), (_) {
      if (!mounted) return;
      setState(() => _caretVisible = !_caretVisible);
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_seconds > 0) setState(() => _seconds--);
    });
  }

  void _handleCodeChanged() {
    if (!mounted) return;
    if (_error != null) setState(() => _error = null);
    setState(() {});
    if (_code.text.length == _codeLength) _verify();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _caretTimer?.cancel();
    _code.removeListener(_handleCodeChanged);
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy || _closing) return;
    final value = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(value)) {
      if (mounted) setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await EmailOtpService.verify(widget.email, value)) {
        throw StateError('Incorrect verification code.');
      }
      _closing = true;
      await Future<void>.delayed(Duration.zero);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  void _cancel() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop(false);
  }

  void _pressDigit(String digit) {
    if (_busy || _closing || _code.text.length >= _codeLength) return;
    _code.text += digit;
  }

  void _deleteDigit() {
    if (_busy || _closing || _code.text.isEmpty) return;
    _code.text = _code.text.substring(0, _code.text.length - 1);
  }

  Future<void> _resend() async {
    if (_seconds > 0 || _busy || _closing) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await EmailOtpService.request(widget.email);
      if (mounted) {
        setState(() {
          _seconds = 60;
          _busy = false;
        });
        _startCountdown();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  Future<void> _showOtpHelp() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Email code help'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocalizedText('Enter your verification code'),
            SizedBox(height: 8),
            LocalizedText(
              'If the code is missing, check spam. Request another after the countdown.',
            ),
          ],
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

  Widget _codeSlots(BuildContext context) {
    final theme = Theme.of(context);
    final value = _code.text;
    final activeIndex = value.length.clamp(0, _codeLength - 1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(_codeLength, (index) {
        final filled = index < value.length;
        final active = index == activeIndex && !filled;
        return SizedBox(
          width: 42,
          height: 62,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 160),
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
                child: LocalizedText(filled ? value[index] : ''),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: active ? 3 : 1.5,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              if (active && _caretVisible)
                Positioned(
                  bottom: 12,
                  child: Container(
                    width: 2,
                    height: 24,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _numberKey(String label, {VoidCallback? onPressed}) {
    return Expanded(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(48),
            onTap: onPressed,
            child: SizedBox(
              width: 76,
              height: 64,
              child: Center(
                child: LocalizedText(
                  label,
                  style: const TextStyle(
                    fontSize: 31,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _numericKeypad(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Row(
          children: [
            _numberKey('1', onPressed: () => _pressDigit('1')),
            _numberKey('2', onPressed: () => _pressDigit('2')),
            _numberKey('3', onPressed: () => _pressDigit('3')),
          ],
        ),
        Row(
          children: [
            _numberKey('4', onPressed: () => _pressDigit('4')),
            _numberKey('5', onPressed: () => _pressDigit('5')),
            _numberKey('6', onPressed: () => _pressDigit('6')),
          ],
        ),
        Row(
          children: [
            _numberKey('7', onPressed: () => _pressDigit('7')),
            _numberKey('8', onPressed: () => _pressDigit('8')),
            _numberKey('9', onPressed: () => _pressDigit('9')),
          ],
        ),
        Row(
          children: [
            const Spacer(),
            _numberKey('0', onPressed: () => _pressDigit('0')),
            Expanded(
              child: Center(
                child: IconButton(
                  tooltip: AppLanguageService.translate('Delete'),
                  onPressed: _busy || _closing ? null : _deleteDigit,
                  icon: Icon(
                    Icons.backspace_outlined,
                    size: 30,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          tooltip: AppLanguageService.translate('Back'),
          onPressed: _cancel,
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        actions: [
          const LanguageSelectorButton(),
          IconButton(
            tooltip: AppLanguageService.translate('Help'),
            onPressed: _showOtpHelp,
            icon: const Icon(Icons.help_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
          child: Column(
            children: [
              Expanded(
                flex: 6,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Icon(
                        Icons.mark_email_read_outlined,
                        size: 38,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      LocalizedText(
                        AppLanguageService.translate('Verification code'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      LocalizedText(
                        AppLanguageService.translate(
                          'Please enter the 6-digit code sent to',
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),
                      LocalizedText(
                        widget.email,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _codeSlots(context),
                      const SizedBox(height: 15),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _error == null
                            ? const SizedBox(height: 22)
                            : LocalizedText(
                                _error!,
                                key: ValueKey(_error),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                      ),
                      const SizedBox(height: 20),
                      LocalizedText(
                        _seconds > 0
                            ? 'You can request a new code in $_seconds seconds'
                            : 'Didn’t receive the code?',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextButton(
                        onPressed: _seconds == 0 && !_busy ? _resend : null,
                        child: LocalizedText('Resend code'),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(flex: 5, child: _numericKeypad(context)),
              if (_busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
