import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'basic_profile_screen.dart';
import 'login_screen.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/email_otp_service.dart';
import 'email_otp_screen.dart';
import 'services/app_language_service.dart';

class CreateAccountScreen extends StatefulWidget {
  final bool isVerified;

  final String? existingUid;
  final String? existingEmail;
  final String? existingAccountType;

  const CreateAccountScreen({
    super.key,
    required this.isVerified,
    this.existingUid,
    this.existingEmail,
    this.existingAccountType,
  });

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState
    extends LanguageAwareState<CreateAccountScreen> {
  /* Calling-code selection is no longer part of email OTP registration. */
  /*
    '+92 Pakistan', '+1 United States/Canada', '+44 United Kingdom',
    '+971 United Arab Emirates', '+966 Saudi Arabia', '+974 Qatar',
    '+968 Oman', '+965 Kuwait', '+973 Bahrain', '+91 India',
    '+880 Bangladesh', '+86 China', '+81 Japan', '+82 South Korea',
    '+60 Malaysia', '+90 Turkey', '+49 Germany', '+33 France', '+39 Italy',
    '+34 Spain', '+7 Russia/Kazakhstan', '+61 Australia', '+64 New Zealand',
    '+27 South Africa', '+20 Egypt', '+234 Nigeria', '+254 Kenya',
    '+212 Morocco', '+213 Algeria', '+216 Tunisia', '+218 Libya',
    '+249 Sudan', '+255 Tanzania', '+256 Uganda', '+251 Ethiopia',
    '+55 Brazil', '+52 Mexico', '+54 Argentina', '+56 Chile',
    '+57 Colombia', '+58 Venezuela', '+31 Netherlands', '+32 Belgium',
    '+41 Switzerland', '+43 Austria', '+45 Denmark', '+46 Sweden',
    '+47 Norway', '+48 Poland', '+30 Greece', '+351 Portugal',
    '+353 Ireland', '+358 Finland', '+380 Ukraine', '+420 Czechia',
    '+36 Hungary', '+40 Romania', '+381 Serbia', '+359 Bulgaria',
    '+972 Israel', '+98 Iran', '+964 Iraq', '+962 Jordan', '+961 Lebanon',
    '+963 Syria', '+967 Yemen', '+93 Afghanistan', '+998 Uzbekistan',
    '+992 Tajikistan', '+993 Turkmenistan', '+994 Azerbaijan',
    '+995 Georgia', '+976 Mongolia', '+977 Nepal', '+94 Sri Lanka',
    '+95 Myanmar', '+62 Indonesia', '+63 Philippines', '+66 Thailand',
    '+84 Vietnam', '+852 Hong Kong', '+886 Taiwan', '+65 Singapore',
    '+675 Papua New Guinea', '+679 Fiji', '+599 Caribbean Netherlands',
    '+51 Peru', '+505 Nicaragua', '+507 Panama', '+506 Costa Rica',
    '+502 Guatemala', '+503 El Salvador', '+504 Honduras', '+591 Bolivia',
    '+593 Ecuador', '+598 Uruguay', '+350 Gibraltar', '+354 Iceland',
    '+356 Malta', '+357 Cyprus', '+352 Luxembourg', '+377 Monaco',
    '+385 Croatia', '+386 Slovenia', '+387 Bosnia',
    '+389 North Macedonia', '+421 Slovakia', '+423 Liechtenstein',
    '+375 Belarus', '+370 Lithuania', '+371 Latvia', '+372 Estonia',
    '+373 Moldova', '+374 Armenia', '+378 San Marino',
    '+382 Montenegro', '+599 Curaçao', '+689 French Polynesia',
  ]; */
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();

  final _passwordController = TextEditingController();

  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;

  bool _obscurePassword = true;

  bool _obscureConfirmPassword = true;

  Timer? _emailCheckTimer;
  int _emailCheckToken = 0;
  bool _checkingEmail = false;
  bool? _emailAlreadyRegistered;

  bool get _isExistingAccount {
    return widget.existingUid != null && widget.existingUid!.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();

    final currentUser = AuthService.currentUser;

    _emailController.text = widget.existingEmail ?? currentUser?.email ?? '';
  }

  @override
  void dispose() {
    _emailCheckTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    super.dispose();
  }

  void _scheduleEmailCheck(String rawEmail) {
    if (_isExistingAccount) return;
    _emailCheckTimer?.cancel();
    final email = rawEmail.trim().toLowerCase();
    final token = ++_emailCheckToken;

    if (!email.contains('@') || !email.contains('.')) {
      setState(() {
        _checkingEmail = false;
        _emailAlreadyRegistered = null;
      });
      return;
    }

    setState(() {
      _checkingEmail = true;
      _emailAlreadyRegistered = null;
    });

    _emailCheckTimer = Timer(const Duration(milliseconds: 450), () async {
      try {
        final exists = await EmailOtpService.accountExists(email);
        if (!mounted || token != _emailCheckToken) return;
        setState(() {
          _checkingEmail = false;
          _emailAlreadyRegistered = exists;
        });
      } catch (_) {
        if (!mounted || token != _emailCheckToken) return;
        setState(() {
          _checkingEmail = false;
          _emailAlreadyRegistered = null;
        });
      }
    });
  }

  void _openLogin() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_isExistingAccount && _checkingEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Checking this email address…')),
      );
      return;
    }

    if (!_isExistingAccount && _emailAlreadyRegistered == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText('Email already registered. Please use Login.'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String uid;
      String email;

      if (_isExistingAccount) {
        uid = widget.existingUid!;

        email =
            widget.existingEmail ??
            AuthService.currentUser?.email ??
            _emailController.text.trim();

        await FirestoreService.setRegistrationStep(
          uid: uid,
          step: 'basic_profile',
        );
      } else {
        email = _emailController.text.trim();
        final current = AuthService.currentUser;
        final currentMatches =
            current?.email?.toLowerCase() == email.toLowerCase();
        var accountExists = currentMatches;

        if (!accountExists) {
          // The server check is authoritative, but try Firebase once as a
          // fallback as well. This prevents a temporary API response or
          // network race from sending an existing email through OTP signup.
          try {
            accountExists = await EmailOtpService.accountExists(email);
          } catch (_) {
            // The Firebase sign-in fallback below can still identify an
            // existing account when the lookup endpoint is unavailable.
          }
        }

        if (accountExists) {
          throw const AuthException(
            'Email already registered. Please use Login.',
          );
        }

        await EmailOtpService.request(email);
        if (!mounted) return;
        final verified = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => EmailOtpScreen(email: email)),
        );
        if (verified != true) {
          throw const AuthException(
            'Please enter the correct email verification code.',
          );
        }
        final credential = await AuthService.register(
          email: email,
          password: _passwordController.text,
        );
        final newUser = credential.user;
        if (newUser == null) {
          throw const AuthException('Unable to create the account.');
        }
        uid = newUser.uid;
        await FirestoreService.createIncompleteUser(
          uid: uid,
          accountType: widget.isVerified ? 'verified' : 'unverified',
          email: email,
          phone: null,
        );
      }

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BasicProfileScreen(
            uid: uid,
            email: email,
            phone: '',
            accountType: widget.isVerified ? 'verified' : 'unverified',
          ),
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: LocalizedText(e.message)));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: LocalizedText('Create Account'),
        centerTitle: true,
        leading: IconButton(
          tooltip: AppLanguageService.translate('Back'),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        actions: const [LanguageSelectorButton()],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 16),

                  Icon(
                    _isExistingAccount
                        ? Icons.login_rounded
                        : Icons.person_add_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),

                  const SizedBox(height: 20),

                  LocalizedText(
                    _isExistingAccount
                        ? 'Continue your profile'
                        : 'Create your Nisa account',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

                  LocalizedText(
                    _isExistingAccount
                        ? 'Your account already exists. Continue completing your profile.'
                        : 'Your account will be securely connected to Firebase.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Colors.black54,
                    ),
                  ),

                  const SizedBox(height: 32),

                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_isExistingAccount,
                    onChanged: _scheduleEmailCheck,
                    decoration: InputDecoration(
                      labelText: AppLanguageService.translate('Email'),
                      prefixIcon: Icon(Icons.email_outlined),
                      suffixIcon: !_isExistingAccount && _checkingEmail
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return AppLanguageService.translate(
                          'Please enter your email.',
                        );
                      }

                      if (!value.contains('@')) {
                        return AppLanguageService.translate(
                          'Please enter a valid email.',
                        );
                      }

                      return null;
                    },
                  ),

                  if (!_isExistingAccount &&
                      _emailAlreadyRegistered == true) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: LocalizedText(
                            'Email already registered',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openLogin,
                          icon: const Icon(Icons.login_rounded, size: 18),
                          label: LocalizedText('Login'),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),

                  const LocalizedText(
                    'A 6-digit verification code will be sent to this email before your Firebase account is created.',
                    style: TextStyle(color: Colors.black54),
                  ),

                  if (!_isExistingAccount) ...[
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: AppLanguageService.translate('Password'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return AppLanguageService.translate(
                            'Please enter a password.',
                          );
                        }

                        if (value.length < 6) {
                          return AppLanguageService.translate(
                            'Password must be at least 6 characters.',
                          );
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      decoration: InputDecoration(
                        labelText: AppLanguageService.translate(
                          'Confirm password',
                        ),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return AppLanguageService.translate(
                            'Please confirm your password.',
                          );
                        }

                        if (value != _passwordController.text) {
                          return AppLanguageService.translate(
                            'Passwords do not match.',
                          );
                        }

                        return null;
                      },
                    ),
                  ],

                  const SizedBox(height: 30),

                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _continue,
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : LocalizedText(
                              _isExistingAccount
                                  ? 'Continue'
                                  : 'Create Account',
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  if (_isExistingAccount)
                    const LocalizedText(
                      'You are continuing an existing Firebase account. A new account will not be created.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                ],
              ),
            ),
            if (_isLoading)
              Positioned.fill(
                child: AbsorbPointer(
                  child: ColoredBox(
                    color: Color(0xF2FFF9FF),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 18),
                          LocalizedText(
                            'Preparing your profile…',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
