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
      url:
          (json['url'] ??
                  json['photoUrl'] ??
                  json['photoURL'] ??
                  json['imageUrl'] ??
                  '')
              .toString(),
      order: json['order'] is num ? (json['order'] as num).toInt() : 0,
      approved: json['approved'] as bool? ?? true,
      blurred: json['blurred'] as bool? ?? false,
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
