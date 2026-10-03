import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/candidate_profile.dart';
import 'block_service.dart';

class CandidateService {
  CandidateService._();

  static final _profiles = FirebaseFirestore.instance.collection(
    'public_profiles',
  );
  static Future<List<CandidateProfile>> getEligiblePool({
    required String currentUserId,
    String? gender,
    int limit = 100,
  }) async {
    Query<Map<String, dynamic>> q = _profiles.where(
      'profileActive',
      isEqualTo: true,
    );
    if (gender != null && gender.trim().isNotEmpty) {
      q = q.where('gender', isEqualTo: gender.trim());
    }
    final activeSnapshot = await q.limit(limit).get();

    // Profiles created before the public-profile migration may not have the
    // profileActive field at all. Keep the explicit false state private, but
    // allow legacy documents with no flag to remain discoverable when the
    // modern query did not return them.
    final snapshots = <QueryDocumentSnapshot<Map<String, dynamic>>>[
      ...activeSnapshot.docs,
    ];
    if (snapshots.length < limit) {
      final legacy = await _profiles.limit(limit).get();
      final seen = snapshots.map((doc) => doc.id).toSet();
      for (final doc in legacy.docs) {
        if (seen.contains(doc.id)) continue;
        final data = doc.data();
        if (data['profileActive'] == false) continue;
        if (gender != null &&
            gender.trim().isNotEmpty &&
            data['gender'] != gender.trim()) {
          continue;
        }
        snapshots.add(doc);
        seen.add(doc.id);
        if (snapshots.length >= limit) break;
      }
    }

    final bf = BlockService.blockedUserIds(currentUserId),
        bmf = BlockService.usersWhoBlockedMe(currentUserId);
    final b = await bf, bm = await bmf, hidden = <String>{...b, ...bm};
    final out = <CandidateProfile>[];
    for (final d in snapshots) {
      if (d.id == currentUserId || hidden.contains(d.id)) continue;
      final c = CandidateProfile.fromMap(d.id, d.data());
      if (!c.ageEligible || c.age < 18) continue;
      out.add(c);
    }
    return out;
  }

  static Future<List<CandidateProfile>> getCandidates({
    required String currentUserId,
    String? gender,
    int? minimumAge,
    int? maximumAge,
    String? country,
    String? city,
    String? maritalStatus,
    String? education,
  }) async {
    Query<Map<String, dynamic>> q = _profiles.where(
      'profileActive',
      isEqualTo: true,
    );
    if (gender != null && gender.trim().isNotEmpty) {
      q = q.where('gender', isEqualTo: gender.trim());
    }
    if (country != null && country.trim().isNotEmpty) {
      q = q.where('country', isEqualTo: country.trim());
    }
    if (city != null && city.trim().isNotEmpty) {
      q = q.where('city', isEqualTo: city.trim());
    }
    if (maritalStatus != null && maritalStatus.trim().isNotEmpty) {
      q = q.where('maritalStatus', isEqualTo: maritalStatus.trim());
    }
    if (education != null && education.trim().isNotEmpty) {
      q = q.where('education', isEqualTo: education.trim());
    }
    final sf = q.get(),
        bf = BlockService.blockedUserIds(currentUserId),
        bmf = BlockService.usersWhoBlockedMe(currentUserId);
    final s = await sf,
        b = await bf,
        bm = await bmf,
        hidden = <String>{...b, ...bm};
    final out = <CandidateProfile>[];
    for (final d in s.docs) {
      if (d.id == currentUserId || hidden.contains(d.id)) continue;
      final c = CandidateProfile.fromMap(d.id, d.data());
      if (!c.ageEligible || c.age < 18) continue;
      if (minimumAge != null && c.age < minimumAge) continue;
      if (maximumAge != null && c.age > maximumAge) continue;
      out.add(c);
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  static Future<CandidateProfile?> getCandidateById(String id) async {
    if (id.trim().isEmpty) return null;
    final d = await _profiles.doc(id).get();
    Map<String, dynamic>? data = d.data();
    // Existing interests/matches must remain renderable even when a profile
    // was temporarily deactivated or was created before profileActive existed.
    if (data == null) {
      final legacy = await FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .get();
      data = legacy.data();
    }
    if (data == null) return null;
    final c = CandidateProfile.fromMap(d.id, data);
    if (c.age > 0 && c.age < 18) return null;
    return c;
  }
}
