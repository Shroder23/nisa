import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static Future<UserCredential> register({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_friendlyMessage(e));
    }
  }

  static Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_friendlyMessage(e));
    }
  }

  static Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthException(_friendlyMessage(e));
    }
  }

  static Future<void> signOut() => _auth.signOut();

  static Future<UserCredential> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn();
      // Signing out of the Google chooser does not sign the user out of
      // Firebase. It makes Android show the account chooser again, allowing
      // the user to select a different Google account.
      await googleSignIn.signOut();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthException('Google sign-in was cancelled.');
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      return await _auth.signInWithCredential(credential);
    } on AuthException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_friendlyMessage(e));
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_failed' &&
          (e.message?.contains('ApiException: 10') == true ||
              e.message?.contains('ApiException:10') == true)) {
        throw const AuthException(
          'Google Sign-In is not configured for this Android app. '
          'Add the app SHA-1 in Firebase and download the updated Google services file.',
        );
      }
      throw AuthException('Google sign-in failed: ${e.message ?? e.code}');
    } catch (e) {
      throw AuthException('Google sign-in failed: $e');
    }
  }

  static Future<void> verifyAndLinkPhone({
    required String phoneNumber,
    required Future<String?> Function() requestCode,
  }) async {
    final completer = Completer<void>();
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (credential) async {
        try {
          await _auth.currentUser?.linkWithCredential(credential);
          if (!completer.isCompleted) {
            completer.complete();
          }
        } catch (e) {
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        }
      },
      verificationFailed: (e) {
        if (!completer.isCompleted) {
          completer.completeError(AuthException(_friendlyMessage(e)));
        }
      },
      codeSent: (verificationId, _) async {
        try {
          final code = await requestCode();
          if (code == null || code.trim().isEmpty) {
            throw const AuthException('Phone verification was cancelled.');
          }
          final credential = PhoneAuthProvider.credential(
            verificationId: verificationId,
            smsCode: code.trim(),
          );
          await _auth.currentUser?.linkWithCredential(credential);
          if (!completer.isCompleted) {
            completer.complete();
          }
        } catch (e) {
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        }
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    return completer.future;
  }

  static Future<UserCredential> verifyPhoneAndSignIn({
    required String phoneNumber,
    required Future<String?> Function() requestCode,
  }) async {
    final completer = Completer<UserCredential>();
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (credential) async {
        try {
          final result = await _auth.signInWithCredential(credential);
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        } catch (e) {
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        }
      },
      verificationFailed: (e) {
        if (!completer.isCompleted) {
          completer.completeError(AuthException(_friendlyMessage(e)));
        }
      },
      codeSent: (verificationId, _) async {
        try {
          final code = await requestCode();
          if (code == null || code.trim().isEmpty) {
            throw const AuthException('Phone verification was cancelled.');
          }
          final credential = PhoneAuthProvider.credential(
            verificationId: verificationId,
            smsCode: code.trim(),
          );
          final result = await _auth.signInWithCredential(credential);
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        } catch (e) {
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        }
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    return completer.future;
  }

  static String _friendlyMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Please choose a stronger password.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'The email or password is incorrect.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }
}

class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  @override
  String toString() => message;
}
