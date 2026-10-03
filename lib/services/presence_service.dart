import 'package:cloud_firestore/cloud_firestore.dart';

class UserPresence {
  final bool isOnline;
  final DateTime? lastSeenAt;

  const UserPresence({required this.isOnline, this.lastSeenAt});

  String get label {
    if (isOnline) return 'online';
    final time = lastSeenAt;
    if (time == null) return 'last seen recently';

    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return 'last seen ${time.day}/${time.month} at $hour:$minute $suffix';
  }
}

class PresenceService {
  PresenceService._();

  static final _profiles = FirebaseFirestore.instance.collection(
    'public_profiles',
  );

  static Stream<UserPresence> watch(String uid) {
    if (uid.isEmpty) {
      return Stream.value(const UserPresence(isOnline: false));
    }

    return _profiles.doc(uid).snapshots().map((snapshot) {
      final data = snapshot.data() ?? const <String, dynamic>{};
      final raw = data['lastSeenAt'];
      DateTime? lastSeen;

      if (raw is Timestamp) lastSeen = raw.toDate();
      if (raw is DateTime) lastSeen = raw;
      if (raw is String) lastSeen = DateTime.tryParse(raw);

      return UserPresence(
        isOnline: data['isOnline'] == true,
        lastSeenAt: lastSeen,
      );
    });
  }

  static Future<void> markOnline(String uid) async {
    if (uid.isEmpty) return;
    await _profiles.doc(uid).update({
      'isOnline': true,
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> markOffline(String uid) async {
    if (uid.isEmpty) return;
    await _profiles.doc(uid).update({
      'isOnline': false,
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
  }
}
