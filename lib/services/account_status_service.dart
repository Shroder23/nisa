import 'package:cloud_firestore/cloud_firestore.dart';

/// The users document is the source of truth for whether an account may be
/// shown or used. Missing users documents are treated as deleted accounts.
enum AccountAccessState { active, disabled, deleted }

class AccountStatusService {
  AccountStatusService._();

  static final CollectionReference<Map<String, dynamic>> _users =
      FirebaseFirestore.instance.collection('users');
  static final CollectionReference<Map<String, dynamic>> _publicProfiles =
      FirebaseFirestore.instance.collection('public_profiles');

  static AccountAccessState _stateFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!snapshot.exists) return AccountAccessState.deleted;

    final data = snapshot.data() ?? const <String, dynamic>{};
    if (data['disabled'] == true ||
        data['isDisabled'] == true ||
        data['deleted'] == true) {
      return AccountAccessState.disabled;
    }
    final raw = (data['status'] ?? data['accountStatus'] ?? 'active')
        .toString()
        .trim()
        .toLowerCase();

    return raw == 'active' || raw == 'enabled'
        ? AccountAccessState.active
        : AccountAccessState.disabled;
  }

  static Stream<AccountAccessState> watch(String uid) {
    if (uid.trim().isEmpty) {
      return Stream.value(AccountAccessState.deleted);
    }

    return _users.doc(uid).snapshots().map(_stateFromSnapshot);
  }

  /// Visibility watcher for another member. Public profiles are readable by
  /// signed-in users, while private users documents are intentionally not.
  static Stream<AccountAccessState> watchVisibility(String uid) {
    if (uid.trim().isEmpty) {
      return Stream.value(AccountAccessState.deleted);
    }

    return _publicProfiles.doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) return AccountAccessState.deleted;
      final data = snapshot.data() ?? const <String, dynamic>{};
      return data['profileActive'] == false
          ? AccountAccessState.disabled
          : AccountAccessState.active;
    });
  }

  static Future<AccountAccessState> getState(String uid) async {
    if (uid.trim().isEmpty) return AccountAccessState.deleted;
    try {
      // Other users' private documents are normally protected by Firestore
      // rules. Check the public profile first; it is the visibility index.
      final publicSnapshot = await _publicProfiles.doc(uid).get();
      if (publicSnapshot.exists) {
        final data = publicSnapshot.data() ?? const <String, dynamic>{};
        return data['profileActive'] == false
            ? AccountAccessState.disabled
            : AccountAccessState.active;
      }

      // This fallback is important for the currently signed-in account,
      // whose users document is owner-readable and is watched for logout.
      return _stateFromSnapshot(await _users.doc(uid).get());
    } on FirebaseException {
      // A temporary Firestore outage must not make every visible profile
      // disappear. The live watcher will enforce the state once reachable.
      return AccountAccessState.active;
    }
  }

  static Future<bool> isActive(String uid) async {
    return await getState(uid) == AccountAccessState.active;
  }
}
