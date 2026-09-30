import 'package:firebase_auth/firebase_auth.dart';

/// Turns Firebase errors into sentences a site manager can act on.
String friendlyError(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-email' => 'That email address doesn\'t look right.',
      'user-disabled' => 'This account has been turned off. Contact your office admin.',
      'user-not-found' || 'wrong-password' || 'invalid-credential' || 'invalid-login-credentials' =>
        'Email or password is incorrect.',
      'email-already-in-use' =>
        'An account with this email already exists. If the person was removed earlier, reactivate them from the Users list.',
      'weak-password' => 'Password is too weak. Use at least 8 characters.',
      'too-many-requests' => 'Too many attempts. Wait a few minutes and try again.',
      'network-request-failed' => 'No internet connection. Check your network and try again.',
      'requires-recent-login' => 'For your security, sign out and sign in again, then retry.',
      'operation-not-allowed' =>
        'Email sign-in is not switched on for this Firebase project. Enable Email/Password in the Firebase console.',
      _ => error.message ?? 'Sign-in failed (${error.code}).',
    };
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' => 'You don\'t have permission to do this.',
      'unavailable' => 'Can\'t reach the server. Check your internet connection.',
      'not-found' => 'This record no longer exists.',
      _ => error.message ?? 'Something went wrong (${error.code}).',
    };
  }
  return error.toString().replaceFirst('Exception: ', '');
}
