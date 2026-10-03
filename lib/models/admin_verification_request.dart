class AdminVerificationRequest {
  final String id;
  final String userId;
  final String status;
  final String guardianName;
  final String guardianRelation;
  final String parentIdUrl;
  final String parentVideoUrl;
  final String createdAt;
  final String rejectionReason;

  const AdminVerificationRequest({
    required this.id,
    required this.userId,
    required this.status,
    required this.guardianName,
    required this.guardianRelation,
    required this.parentIdUrl,
    required this.parentVideoUrl,
    required this.createdAt,
    required this.rejectionReason,
  });

  factory AdminVerificationRequest.fromJson(Map<String, dynamic> json) {
    return AdminVerificationRequest(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      guardianName: json['guardianName']?.toString() ?? '',
      guardianRelation: json['guardianRelation']?.toString() ?? '',
      parentIdUrl: json['parentIdUrl']?.toString() ?? '',
      parentVideoUrl: json['parentVideoUrl']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
      rejectionReason: json['rejectionReason']?.toString() ?? '',
    );
  }
}
