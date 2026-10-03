class UserPhoto {
  final String url;

  final int order;

  final bool approved;

  final bool blurred;

  const UserPhoto({
    required this.url,
    required this.order,
    this.approved = true,
    this.blurred = false,
  });

  factory UserPhoto.fromMap(Map<String, dynamic> json) {
    return UserPhoto(
      url: json['url'] ?? '',
      order: json['order'] ?? 0,
      approved: json['approved'] ?? true,
      blurred: json['blurred'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'order': order,
      'approved': approved,
      'blurred': blurred,
    };
  }
}
