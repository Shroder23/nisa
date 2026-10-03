import 'app_language_service.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'notification_service.dart';
import '../models/notification_item.dart';
import 'candidate_service.dart';
import '../models/interest.dart';

class InterestService {
  static Future<T> _acceptanceStep<T>(
    String stage,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on FirebaseException catch (e) {
      throw FirebaseException(
        plugin: e.plugin,
        code: e.code,
        message: '$stage: ${e.message ?? e.code}',
      );
    }
  }

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('interests');

  static String _interestId(String senderId, String receiverId) {
    return '${senderId}_$receiverId';
  }

  static Stream<int> pendingIncomingCount(String receiverId) {
    return _collection
        .where('receiverId', isEqualTo: receiverId)
        .where('status', isEqualTo: InterestStatus.pending.name)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  static Future<Interest?> findInterest(
    String senderId,
    String receiverId,
  ) async {
    final doc = await _collection.doc(_interestId(senderId, receiverId)).get();

    if (!doc.exists) {
      return null;
    }

    final data = doc.data();

    if (data == null) {
      return null;
    }

    return _fromData(data, doc.id);
  }

  static Future<void> sendInterest({
    required String senderId,
    required String receiverId,
  }) async {
    if (senderId.isEmpty || receiverId.isEmpty) {
      throw ArgumentError('Invalid user ID.');
    }

    if (senderId == receiverId) {
      throw StateError('You cannot send interest to yourself.');
    }

    final id = _interestId(senderId, receiverId);

    final existing = await _collection.doc(id).get();

    if (existing.exists) {
      final data = existing.data();

      if (data != null) {
        final status = data['status'] as String?;

        if (status == 'pending' || status == 'accepted') {
          throw StateError('Interest already exists.');
        }
      }
    }

    await _collection.doc(id).set({
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'status': InterestStatus.pending.name,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final sender = await CandidateService.getCandidateById(senderId);

    await NotificationService.create(
      recipientId: receiverId,
      senderId: senderId,
      type: NotificationType.interestReceived,
      title: AppLanguageService.translate('New Interest'),
      body: '${sender?.name ?? "Someone"} has shown interest in your profile.',
      entityId: id,
    );
  }

  static Future<List<Interest>> interestsForSender(String senderId) async {
    final snapshot = await _collection
        .where('senderId', isEqualTo: senderId)
        .get();

    return snapshot.docs.map((doc) => _fromData(doc.data(), doc.id)).toList();
  }

  static Future<List<Interest>> interestsForReceiver(String receiverId) async {
    final snapshot = await _collection
        .where('receiverId', isEqualTo: receiverId)
        .get();

    return snapshot.docs.map((doc) => _fromData(doc.data(), doc.id)).toList();
  }

  static Future<void> acceptInterest(String interestId) async {
    final ref = _collection.doc(interestId);

    final snapshot = await _acceptanceStep(
      'Reading incoming interest',
      () => ref.get(),
    );

    if (!snapshot.exists) {
      throw StateError('Interest no longer exists.');
    }

    final data = snapshot.data()!;

    await _acceptanceStep(
      'Saving acceptance',
      () => ref.update({
        'status': InterestStatus.accepted.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
    );

    try {
      final receiver = await CandidateService.getCandidateById(
        data['receiverId'],
      );

      await NotificationService.create(
        recipientId: data['senderId'],
        senderId: data['receiverId'],
        type: NotificationType.interestAccepted,
        title: AppLanguageService.translate('Interest Accepted'),
        body: '${receiver?.name ?? "A member"} accepted your interest.',
        entityId: interestId,
      );
    } on FirebaseException catch (e) {
      // Acceptance is already committed. A notification failure must not make
      // the UI report that accepting the interest itself failed.
      // ignore: avoid_print
      print(
        'InterestService: acceptance saved, but notification failed: '
        '${e.code} ${e.message}',
      );
    } catch (e) {
      // ignore: avoid_print
      print('InterestService: acceptance saved, but notification failed: $e');
    }
  }

  static Future<void> declineInterest(String interestId) async {
    final ref = _collection.doc(interestId);

    final snapshot = await ref.get();

    if (!snapshot.exists) {
      throw StateError('Interest no longer exists.');
    }

    final data = snapshot.data()!;

    await ref.update({
      'status': InterestStatus.declined.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final receiver = await CandidateService.getCandidateById(
      data['receiverId'],
    );

    await NotificationService.create(
      recipientId: data['senderId'],
      senderId: data['receiverId'],
      type: NotificationType.interestDeclined,
      title: AppLanguageService.translate('Interest Declined'),
      body: '${receiver?.name ?? "A member"} declined your interest.',
      entityId: interestId,
    );
  }

  static Future<void> cancelInterest(String interestId) async {
    final ref = _collection.doc(interestId);

    final snapshot = await ref.get();

    if (!snapshot.exists) {
      throw StateError('Interest no longer exists.');
    }

    await ref.update({
      'status': InterestStatus.cancelled.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Interest _fromData(Map<String, dynamic> data, String documentId) {
    return Interest(
      id: data['id'] as String? ?? documentId,
      senderId: data['senderId'] as String? ?? '',
      receiverId: data['receiverId'] as String? ?? '',
      status: _statusFromString(data['status'] as String?),
    );
  }

  static InterestStatus _statusFromString(String? value) {
    switch (value) {
      case 'accepted':
        return InterestStatus.accepted;

      case 'declined':
        return InterestStatus.declined;

      case 'cancelled':
        return InterestStatus.cancelled;

      case 'pending':
      default:
        return InterestStatus.pending;
    }
  }
}
