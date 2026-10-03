class MatrimonialMatch {
  final String id;
  final String userA;
  final String userB;
  final DateTime matchedAt;

  MatrimonialMatch({
    required this.id,
    required this.userA,
    required this.userB,
    required this.matchedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'userA': userA,
      'userB': userB,
      'matchedAt': matchedAt.toIso8601String(),
    };
  }

  factory MatrimonialMatch.fromJson(Map<String, dynamic> json) {
    return MatrimonialMatch(
      id: json['id'] as String,
      userA: json['userA'] as String,
      userB: json['userB'] as String,
      matchedAt: DateTime.parse(json['matchedAt'] as String),
    );
  }
}
