import 'widgets/google_sign_in_button.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'presentation/nisa_premium/nisa_premium.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'account_type_screen.dart';
import 'api_email_access_screen.dart';
import 'api_login_screen.dart';
import 'api_home_screen.dart';
import 'api_account_restriction_screen.dart';
import 'config/auth_mode.dart';
import 'age_restricted_screen.dart';
import 'basic_profile_screen.dart';
import 'create_account_screen.dart';
import 'firebase_options.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'models/user_profile.dart';
import 'services/api_app_state.dart';
import 'services/api_auth_service.dart';
import 'services/app_state.dart';
import 'services/firestore_service.dart';
import 'services/age_eligibility_service.dart';
import 'services/auth_service.dart';
import 'services/app_language_service.dart';
import 'theme/nisa_theme.dart';

final GlobalKey<NavigatorState> nisaNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppLanguageService.load();

  if (AuthMode.usePostgresPreview) {
    runApp(const NisaApp());
    return;
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 15));
  } catch (e) {
    runApp(FirebaseStartupErrorApp(error: e.toString()));
    return;
  }

  runApp(const NisaApp());
}

class FirebaseStartupErrorApp extends StatelessWidget {
  final String error;

  const FirebaseStartupErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppLanguageService.translate('Nisa'),
      theme: NisaPremiumTheme.apply(NisaTheme.light),
      home: Scaffold(
        appBar: AppBar(
          title: const LocalizedText('Nisa Startup Error'),
          actions: const [LanguageSelectorButton()],
        ),
        body: NisaPageBody(
          form: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 70),
                  const SizedBox(height: 20),
                  const LocalizedText(
                    'Nisa could not start Firebase.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  LocalizedText(error, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NisaApp extends StatelessWidget {
  const NisaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLanguageService.selectedCode,
      builder: (context, _, _) {
        final locale = AppLanguageService.selected.locale;
        return MaterialApp(
          navigatorKey: nisaNavigatorKey,
          debugShowCheckedModeBanner: false,
          title: AppLanguageService.translate('Nisa'),
          locale: locale,
          supportedLocales: AppLanguageService.languages
              .map((language) => language.locale)
              .toSet()
              .toList(growable: false),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => Directionality(
            textDirection: AppLanguageService.textDirectionFor(
              AppLanguageService.selected,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
          theme: NisaPremiumTheme.apply(NisaTheme.light),
          home: const AuthGate(),
        );
      },
    );
  }
}

/// Root authentication gate.
///
/// This widget stays at the bottom of Nisa's navigation stack for the
/// lifetime of the application. It listens to Firebase authentication and
/// also clears any routes that were manually pushed by older login/profile
/// code when the user signs out.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends LanguageAwareState<AuthGate> {
  late final Stream<User?> _authStream;
  StreamSubscription<User?>? _authSubscription;
  Future<UserProfile?>? _apiRestoreFuture;
  bool _restoringApi = false;

  @override
  void initState() {
    super.initState();

    if (AuthMode.usePostgresPreview) {
      _apiRestoreFuture = _restoreApiSession();
      ApiAuthService.currentAccount.addListener(_apiAccountChanged);
      return;
    }

    _authStream = FirebaseAuth.instance.authStateChanges();
    _authSubscription = _authStream.listen((user) {
      if (user != null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final navigator = nisaNavigatorKey.currentState;
        if (navigator == null) return;
        navigator.popUntil((route) => route.isFirst);
      });
    });
  }

  Future<UserProfile?> _restoreApiSession() async {
    _restoringApi = true;
    try {
      return await ApiAppState.restore();
    } finally {
      _restoringApi = false;
    }
  }

  void _apiAccountChanged() {
    if (!mounted || _restoringApi) return;
    setState(() {
      _apiRestoreFuture = ApiAuthService.currentAccount.value == null
          ? Future<UserProfile?>.value(null)
          : ApiAppState.loadCurrentProfile();
    });
  }

  Future<void> _retryApiRestore() async {
    setState(() {
      _apiRestoreFuture = _restoreApiSession();
    });
  }

  Future<void> _signOutAfterApiRestoreError() async {
    await ApiAppState.clearLocalSession();
    if (!mounted) return;
    setState(() {
      _apiRestoreFuture = Future<UserProfile?>.value(null);
    });
  }

  @override
  void dispose() {
    if (AuthMode.usePostgresPreview) {
      ApiAuthService.currentAccount.removeListener(_apiAccountChanged);
    }
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AuthMode.usePostgresPreview) {
      return FutureBuilder<UserProfile?>(
        future: _apiRestoreFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _StartupLoadingScreen();
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            if (error is ApiAccountRestrictionException) {
              return ApiAccountRestrictionScreen(
                restriction: error,
                onSignOut: _signOutAfterApiRestoreError,
              );
            }
            return _StartupErrorScreen(
              error: error.toString(),
              onRetry: _retryApiRestore,
              onSignOut: _signOutAfterApiRestoreError,
            );
          }
          final profile = snapshot.data;
          if (profile == null) return const WelcomeScreen();
          final account = ApiAppState.currentAccount;
          final registrationComplete =
              account?['account_status'] == 'active' ||
              account?['registration_step'] == 'complete';
          if (!registrationComplete) {
            return BasicProfileScreen(
              uid: profile.uid ?? account?['id']?.toString() ?? '',
              email: account?['email']?.toString() ?? profile.email ?? '',
              phone: '',
              accountType: 'unverified',
              initialName: profile.name,
              existingProfile: profile,
            );
          }
          return ApiHomeScreen(profile: profile);
        },
      );
    }

    return StreamBuilder<User?>(
      stream: _authStream,
      initialData: FirebaseAuth.instance.currentUser,
      builder: (BuildContext context, AsyncSnapshot<User?> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const _StartupLoadingScreen();
        }
        final user = snapshot.data;
        if (user == null) return const WelcomeScreen();
        return SignedInRouter(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

/// Determines where an authenticated user belongs.
///
/// Firebase authentication is already confirmed before this widget runs.
/// It restores either the completed Home experience or the appropriate
/// registration stage.
class SignedInRouter extends StatefulWidget {
  final User user;

  const SignedInRouter({super.key, required this.user});

  @override
  State<SignedInRouter> createState() => _SignedInRouterState();
}

class _SignedInRouterState extends LanguageAwareState<SignedInRouter> {
  late Future<Widget> _destinationFuture;

  @override
  void initState() {
    super.initState();
    _destinationFuture = _resolveDestination();
  }

  Future<Widget> _resolveDestination() async {
    final uid = widget.user.uid;

    // Load the cloud profile first, with a local-cache fallback. This keeps
    // an unfinished registration recoverable during a temporary handshake
    // failure instead of showing the startup error screen.
    try {
      await AppState.loadUser();
    } catch (_) {
      // If even the cloud profile fetch is unavailable, keep the account in
      // the editable registration flow instead of trapping the user on the
      // generic restore-error screen.
      return BasicProfileScreen(
        uid: uid,
        email: widget.user.email ?? '',
        phone: widget.user.phoneNumber ?? '',
        accountType: 'unverified',
        initialName: widget.user.displayName,
        initialProfilePhoto: widget.user.photoURL,
      );
    }
    final cachedProfile = AppState.currentUser;

    bool profileComplete;
    try {
      profileComplete = await FirestoreService.isProfileComplete(uid);
    } catch (error) {
      if (cachedProfile != null) {
        return BasicProfileScreen(
          uid: uid,
          email: cachedProfile.email ?? widget.user.email ?? '',
          phone: cachedProfile.phone ?? widget.user.phoneNumber ?? '',
          accountType: cachedProfile.accountType,
          initialName: cachedProfile.name,
          initialProfilePhoto:
              cachedProfile.profilePhoto ?? widget.user.photoURL,
          existingProfile: cachedProfile,
        );
      }
      rethrow;
    }

    if (profileComplete) {
      var ageEligibility = await FirestoreService.getAgeEligibility(uid);

      // A newly completed account can briefly have no persisted age signal.
      // Re-run the authoritative server-side age check before treating that
      // transient state as an account restore failure.
      if (ageEligibility != 'eligible' && ageEligibility != 'blocked') {
        final refreshed = await AgeEligibilityService.refreshCurrentUser();
        ageEligibility = refreshed.eligibility;
      }

      if (ageEligibility == 'blocked') {
        return const AgeRestrictedScreen();
      }

      if (ageEligibility != 'eligible') {
        throw StateError(
          'Your age eligibility could not be confirmed. '
          'Please try again while the Nisa server is available.',
        );
      }

      final profile = AppState.currentUser;
      if (profile != null) {
        return HomeScreen(profile: profile);
      }
    }

    // Account exists but registration is incomplete.
    final incompleteProfile = AppState.currentUser;

    if (incompleteProfile != null) {
      // Always rebuild registration from Basic Profile when an unfinished
      // account is restored. The screen receives the saved draft, so all
      // previously entered values remain filled in, while the user can move
      // forward through Profile Details and Matrimonial Preferences again.
      return BasicProfileScreen(
        uid: uid,
        email: incompleteProfile.email ?? widget.user.email ?? '',
        phone: incompleteProfile.phone ?? widget.user.phoneNumber ?? '',
        accountType: incompleteProfile.accountType,
        initialName: incompleteProfile.name,
        initialProfilePhoto:
            incompleteProfile.profilePhoto ?? widget.user.photoURL,
        existingProfile: incompleteProfile,
      );
    }

    final signedInWithGoogle = widget.user.providerData.any(
      (provider) => provider.providerId == 'google.com',
    );

    if (signedInWithGoogle) {
      return BasicProfileScreen(
        uid: uid,
        email: widget.user.email ?? '',
        phone: widget.user.phoneNumber ?? '',
        accountType: 'unverified',
        initialName: widget.user.displayName,
        initialProfilePhoto: widget.user.photoURL,
      );
    }

    // Firebase account exists but there is not yet a profile draft.
    final accountType = await FirestoreService.getAccountType(uid);

    return AccountTypeScreen(
      existingUid: uid,
      existingEmail: widget.user.email ?? '',
      existingAccountType: accountType,
    );
  }

  Future<void> _retry() async {
    setState(() {
      _destinationFuture = _resolveDestination();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _destinationFuture,
      builder: (BuildContext context, AsyncSnapshot<Widget> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupLoadingScreen();
        }

        if (snapshot.hasError) {
          return _StartupErrorScreen(
            error: snapshot.error.toString(),
            onRetry: _retry,
            onSignOut: AppState.clearUser,
          );
        }

        final destination = snapshot.data;

        if (destination == null) {
          return _StartupErrorScreen(
            error: 'Nisa could not determine where to continue.',
            onRetry: _retry,
            onSignOut: AppState.clearUser,
          );
        }

        return destination;
      },
    );
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: NisaPageBody(
        form: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSignOut;

  const _StartupErrorScreen({
    required this.error,
    required this.onRetry,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Nisa'),
        centerTitle: true,
        actions: const [LanguageSelectorButton()],
      ),
      body: NisaPageBody(
        form: false,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 72,
                    color: Color(0xFF7B2CBF),
                  ),
                  const SizedBox(height: 24),
                  const LocalizedText(
                    'Could not restore your account',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  LocalizedText(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _retryPressed,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const LocalizedText('Try Again'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: onSignOut,
                    child: const LocalizedText('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retryPressed() async {
    await onRetry();
  }
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends LanguageAwareState<WelcomeScreen> {
  bool _googleLoading = false;

  Future<void> _showLanguagePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .72,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 4, 24, 12),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: LocalizedText(
                      'Choose language',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: AppLanguageService.languages.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final language = AppLanguageService.languages[index];
                      final selected =
                          language.code ==
                          AppLanguageService.selectedCode.value;
                      return ListTile(
                        leading: const Icon(Icons.language_rounded),
                        title: LocalizedText(language.name),
                        subtitle: LocalizedText(language.nativeName),
                        trailing: selected
                            ? const Icon(Icons.check_circle_rounded)
                            : null,
                        onTap: () {
                          // Close immediately after the in-memory notifier
                          // changes; preference persistence runs in parallel.
                          unawaited(AppLanguageService.setLanguage(language));
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showWelcomeHelp() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Account help'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: AuthMode.usePostgresPreview
              ? const [
                  LocalizedText('Sign in or create an account'),
                  SizedBox(height: 8),
                  LocalizedText('Enter your verification code'),
                ]
              : const [
                  LocalizedText('Continue with Google'),
                  SizedBox(height: 8),
                  LocalizedText('Continue with email'),
                  SizedBox(height: 8),
                  LocalizedText('Already have an account? Log in'),
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

  Future<void> _continueWithEmail() async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuthMode.usePostgresPreview
            ? const ApiEmailAccessScreen()
            : const CreateAccountScreen(isVerified: false),
      ),
    );
  }

  Future<void> _continueWithGoogle() async {
    if (_googleLoading) return;
    setState(() => _googleLoading = true);
    try {
      if (AuthMode.usePostgresPreview) {
        await ApiAuthService.signInWithGoogle();
      } else {
        await AuthService.signInWithGoogle();
      }
      if (!mounted) return;
      // Let AuthGate/SignedInRouter choose Basic Profile, resume, or Home.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: LocalizedText(e.message)));
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString().replaceFirst('Bad state: ', '');
        if (message.contains('Google sign-in was cancelled.')) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: LocalizedText(message)));
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: NisaPageBody(
      form: true,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _showLanguagePicker,
                  icon: const Icon(Icons.language_rounded),
                  label: Text(AppLanguageService.selected.nativeName),
                ),

                IconButton(
                  onPressed: _showWelcomeHelp,
                  tooltip: AppLanguageService.translate('Help'),
                  icon: const Icon(Icons.help_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 48),
            const Icon(
              Icons.favorite_rounded,
              color: NisaPremiumTheme.gold,
              size: 56,
            ),
            const SizedBox(height: 20),
            LocalizedText(
              'Nisa e Sakina',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: NisaPremiumTheme.plum,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            const LocalizedText(
              'Where meaningful connections begin',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            NisaSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LocalizedText(
                    'Join Nisa e Sakina',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const LocalizedText(
                    'Choose how you would like to continue',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _googleLoading ? null : _continueWithEmail,
                    icon: const Icon(Icons.email_outlined),
                    label: const LocalizedText('Continue with email'),
                  ),
                  const SizedBox(height: 12),
                  GoogleSignInButton(
                    onPressed: _googleLoading ? null : _continueWithGoogle,
                    busy: _googleLoading,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _googleLoading
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AuthMode.usePostgresPreview
                                  ? const ApiLoginScreen()
                                  : const LoginScreen(),
                            ),
                          ),
                    child: const LocalizedText(
                      'Already have an account? Log in',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            LocalizedText(
              'By continuing, you agree to our Terms and Privacy Policy.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class AgeConfirmationScreen extends StatelessWidget {
  const AgeConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Age Confirmation'),
        centerTitle: true,
        leading: IconButton(
          tooltip: AppLanguageService.translate('Back'),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        actions: const [LanguageSelectorButton()],
      ),
      body: NisaPageBody(
        form: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),

              const Icon(
                Icons.verified_user_rounded,
                size: 80,
                color: NisaPremiumTheme.plum,
              ),

              const SizedBox(height: 28),

              const LocalizedAgeText(
                'Are you {age} or older?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 16),

              const LocalizedText(
                'Nisa is intended for adults seeking a serious and respectful marriage.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.black54,
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(context, true);
                  },
                  child: const LocalizedAgeText(
                    'Yes, I am {age} or older',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context, false);
                  },
                  child: const LocalizedAgeText(
                    'No, I am under {age}',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
