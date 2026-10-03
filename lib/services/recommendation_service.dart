import '../models/candidate_profile.dart';
import '../models/interest.dart';
import '../models/profile_recommendation.dart';
import '../models/user_profile.dart';
import 'block_service.dart';
import 'candidate_service.dart';
import 'discovery_service.dart';
import 'interest_service.dart';
import 'match_service.dart';

class RecommendationService {
  RecommendationService._();

  static Future<List<ProfileRecommendation>> getRecommendations({
    required UserProfile currentUser,
    int limit = 20,
  }) async {
    final uid = currentUser.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('You are not signed in.');
    }

    final oppositeGender = currentUser.gender == 'Male'
        ? 'Female'
        : currentUser.gender == 'Female'
        ? 'Male'
        : null;

    final poolFuture = CandidateService.getEligiblePool(
      currentUserId: uid,
      gender: oppositeGender,
    );
    final blockedFuture = BlockService.blockedUserIds(uid);
    final blockedMeFuture = BlockService.usersWhoBlockedMe(uid);
    final matchesFuture = MatchService.matchesForUser(uid);
    final outgoingFuture = InterestService.interestsForSender(uid);
    final incomingFuture = InterestService.interestsForReceiver(uid);

    final candidates = await poolFuture;
    final blockedByMe = await blockedFuture;
    final blockedMe = await blockedMeFuture;
    final matches = await matchesFuture;
    final outgoing = await outgoingFuture;
    final incoming = await incomingFuture;

    final hiddenIds = <String>{...blockedByMe, ...blockedMe};
    final matchedIds = <String>{};

    for (final match in matches) {
      if (match.userA == uid && match.userB.isNotEmpty) {
        matchedIds.add(match.userB);
      } else if (match.userB == uid && match.userA.isNotEmpty) {
        matchedIds.add(match.userA);
      }
    }

    // An accepted interest is already a mutual match in the user flow. The
    // match document can be written a moment later, so hide both parties
    // immediately instead of briefly showing the new match again.
    for (final interest in outgoing) {
      if (interest.status == InterestStatus.accepted &&
          interest.receiverId.isNotEmpty) {
        matchedIds.add(interest.receiverId);
      }
    }
    for (final interest in incoming) {
      if (interest.status == InterestStatus.accepted &&
          interest.senderId.isNotEmpty) {
        matchedIds.add(interest.senderId);
      }
    }

    final interestIds = <String>{};
    for (final interest in outgoing) {
      if (interest.receiverId.isNotEmpty &&
          (interest.status == InterestStatus.pending ||
              interest.status == InterestStatus.accepted)) {
        interestIds.add(interest.receiverId);
      }
    }
    for (final interest in incoming) {
      if (interest.senderId.isNotEmpty &&
          (interest.status == InterestStatus.pending ||
              interest.status == InterestStatus.accepted)) {
        interestIds.add(interest.senderId);
      }
    }

    final recommendations = <ProfileRecommendation>[];

    for (final candidate in candidates) {
      if (candidate.age < 18) continue;
      if (hiddenIds.contains(candidate.id)) continue;
      if (matchedIds.contains(candidate.id)) continue;
      if (!DiscoveryService.heightMeetsRange(
        candidate.height,
        currentUser.preferences.minimumHeight,
        currentUser.preferences.maximumHeight,
      )) {
        continue;
      }

      final result = _score(currentUser, candidate);
      recommendations.add(
        ProfileRecommendation(
          candidate: candidate,
          score: result.score,
          reasons: result.reasons,
          hasExistingInterest: interestIds.contains(candidate.id),
        ),
      );
    }

    recommendations.sort((a, b) {
      if (a.hasExistingInterest != b.hasExistingInterest) {
        return a.hasExistingInterest ? 1 : -1;
      }
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      if (a.candidate.verified != b.candidate.verified) {
        return a.candidate.verified ? -1 : 1;
      }
      return a.candidate.name.toLowerCase().compareTo(
        b.candidate.name.toLowerCase(),
      );
    });

    return recommendations.take(limit).toList();
  }

  static _ScoreResult _score(UserProfile user, CandidateProfile candidate) {
    var score = 0;
    final reasons = <String>[];
    final p = user.preferences;

    if (candidate.age >= p.minimumAge && candidate.age <= p.maximumAge) {
      score += 30;
      reasons.add('Preferred age range');
    }
    if (_same(p.country, candidate.country)) {
      score += 20;
      reasons.add('Preferred country');
    }
    if (_same(p.city, candidate.city)) {
      score += 15;
      reasons.add('Preferred city');
    }
    if (_same(p.maritalStatus, candidate.maritalStatus)) {
      score += 15;
      reasons.add('Preferred marital status');
    }
    if (DiscoveryService.educationMeetsMinimum(
      p.education,
      candidate.education,
    )) {
      score += 10;
      reasons.add('Preferred education');
    }
    if (candidate.verified) {
      score += 8;
      reasons.add('Parent verified');
    }
    final myRelocation = user.relocation;

    if (myRelocation == 'Willing to relocate' &&
        candidate.relocation == 'Willing to relocate') {
      score += 3;
      reasons.add('Both open to relocation');
    } else if (candidate.relocation == 'Maybe') {
      score += 1;
    }
    if (candidate.religiousPractice?.trim().isNotEmpty == true) score += 2;
    if (candidate.about?.trim().isNotEmpty == true) score += 1;

    return _ScoreResult(score, reasons.take(3).toList());
  }

  static bool _same(String? preferred, String? actual) {
    final a = preferred?.trim().toLowerCase();
    final b = actual?.trim().toLowerCase();
    return a != null && b != null && a.isNotEmpty && b.isNotEmpty && a == b;
  }
}

class _ScoreResult {
  final int score;
  final List<String> reasons;
  const _ScoreResult(this.score, this.reasons);
}
