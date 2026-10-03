import 'candidate_profile.dart';

class ProfileRecommendation {
  final CandidateProfile candidate;
  final int score;
  final List<String> reasons;
  final bool hasExistingInterest;

  const ProfileRecommendation({
    required this.candidate,
    required this.score,
    required this.reasons,
    this.hasExistingInterest = false,
  });
}
