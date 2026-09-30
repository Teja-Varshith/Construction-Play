import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../users/data/user_repository.dart';
import '../domain/app_user.dart';
import 'auth_repository.dart';

enum SessionStatus { loading, signedOut, noProfile, inactive, ready }

/// Who is using the app right now, combining the login with the profile
/// document (which holds the role and the active switch).
class Session {
  const Session(this.status, {this.user, this.authUser});

  final SessionStatus status;
  final AppUser? user;
  final User? authUser;

  bool get isReady => status == SessionStatus.ready;

  static const loading = Session(SessionStatus.loading);
  static const signedOut = Session(SessionStatus.signedOut);
}

final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

final setupDoneProvider = StreamProvider<bool>(
  (ref) => ref.watch(authRepositoryProvider).watchSetupDone(),
);

final sessionProvider = Provider<Session>((ref) {
  final auth = ref.watch(authStateProvider);
  if (!auth.hasValue) return auth.hasError ? Session.signedOut : Session.loading;
  final authUser = auth.value;
  if (authUser == null) return Session.signedOut;

  final profile = ref.watch(userProvider(authUser.uid));
  if (!profile.hasValue) {
    return profile.hasError
        ? Session(SessionStatus.noProfile, authUser: authUser)
        : Session(SessionStatus.loading, authUser: authUser);
  }
  final user = profile.value;
  if (user == null) return Session(SessionStatus.noProfile, authUser: authUser);
  if (!user.active) return Session(SessionStatus.inactive, user: user, authUser: authUser);
  return Session(SessionStatus.ready, user: user, authUser: authUser);
});

/// The signed-in, active user. Only use below the router's guards, where a
/// ready session is guaranteed.
final currentUserProvider = Provider<AppUser>((ref) {
  final user = ref.watch(sessionProvider).user;
  if (user == null) throw StateError('currentUserProvider used without a signed-in user');
  return user;
});

/// True while the first-run setup screen is creating the owner account, so the
/// router doesn't move the person away mid-setup.
class SetupInProgress extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final setupInProgressProvider = NotifierProvider<SetupInProgress, bool>(SetupInProgress.new);
