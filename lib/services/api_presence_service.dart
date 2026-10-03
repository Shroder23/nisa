import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_auth_service.dart';

class ApiUserPresence {
  final bool isOnline;
  final bool visible;
  final DateTime? lastSeenAt;

  const ApiUserPresence({
    this.isOnline = false,
    this.visible = true,
    this.lastSeenAt,
  });

  factory ApiUserPresence.fromMap(Map<String, dynamic> data) {
    final raw = data['last_seen_at'] ?? data['lastSeenAt'];
    DateTime? lastSeen;
    if (raw is String) lastSeen = DateTime.tryParse(raw)?.toLocal();
    return ApiUserPresence(
      isOnline: data['is_online'] == true || data['isOnline'] == true,
      visible: data['visible'] != false,
      lastSeenAt: lastSeen,
    );
  }

  String get label {
    if (isOnline) return 'Online';
    final seen = lastSeenAt;
    if (seen == null) return 'Last seen recently';
    final elapsed = DateTime.now().difference(seen);
    if (elapsed.inMinutes < 1) return 'Last seen just now';
    if (elapsed.inMinutes < 60) return 'Last seen ${elapsed.inMinutes}m ago';
    if (elapsed.inHours < 24) return 'Last seen ${elapsed.inHours}h ago';
    return 'Last seen ${seen.day}/${seen.month}';
  }
}

class ApiPresenceService {
  ApiPresenceService._();

  static Future<ApiUserPresence?> getPresence(String userId) async {
    if (userId.isEmpty) return null;
    final response = await ApiAuthService.get(
      '/api/users/${Uri.encodeComponent(userId)}/presence',
    );
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final payload = decoded['presence'];
    return ApiUserPresence.fromMap(
      payload is Map<String, dynamic> ? payload : decoded,
    );
  }

  static Future<void> setOnline(bool online) async {
    final response = await ApiAuthService.postJson('/api/presence', {
      'is_online': online,
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Could not update online status.');
    }
  }
}

/// Small live label shared by the Messages list and chat header.
class ApiPresenceLabel extends StatefulWidget {
  final String userId;
  final TextStyle? style;
  final bool compact;

  const ApiPresenceLabel({
    super.key,
    required this.userId,
    this.style,
    this.compact = false,
  });

  @override
  State<ApiPresenceLabel> createState() => _ApiPresenceLabelState();
}

class _ApiPresenceLabelState extends State<ApiPresenceLabel> {
  ApiUserPresence? _presence;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant ApiPresenceLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final value = await ApiPresenceService.getPresence(widget.userId);
      if (mounted) setState(() => _presence = value);
    } catch (_) {
      // Presence is supplemental UI; keep the rest of the chat available.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presence = _presence;
    if (presence == null || !presence.visible) {
      return const SizedBox.shrink();
    }
    final online = presence.isOnline;
    final label = presence.label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (online) ...[
          const Icon(Icons.circle, size: 8, color: Color(0xFF2EAD67)),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            widget.compact && label.startsWith('Last seen ')
                ? label.replaceFirst('Last seen ', '')
                : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style ?? Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
