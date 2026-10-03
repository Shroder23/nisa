import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/server_config.dart';
import '../models/family_invitation.dart' as invitation_model;
import '../models/family_member.dart';

class FamilyService {
  FamilyService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _members =>
      _db.collection('family_members');

  static CollectionReference<Map<String, dynamic>> get _invitations =>
      _db.collection('family_invitations');

  static String normalizeEmail(String value) => value.trim().toLowerCase();

  static String normalizePhone(String value) =>
      value.replaceAll(RegExp(r'[^0-9+]'), '');

  static String contactKey({required String email, required String phone}) {
    final normalizedEmail = normalizeEmail(email);
    if (normalizedEmail.isNotEmpty) return 'email:$normalizedEmail';

    final normalizedPhone = normalizePhone(phone);
    if (normalizedPhone.isNotEmpty) return 'phone:$normalizedPhone';

    return '';
  }

  static Stream<List<FamilyMember>> watchMembers(String ownerUid) {
    if (ownerUid.isEmpty) return Stream.value(const <FamilyMember>[]);

    return _members.where('ownerUid', isEqualTo: ownerUid).snapshots().map((
      snapshot,
    ) {
      final members = snapshot.docs
          .map((doc) => FamilyMember.fromMap(doc.id, doc.data()))
          .toList();

      members.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return members;
    });
  }

  static Future<void> addMember({
    required String ownerUid,
    required String ownerName,
    required String name,
    required FamilyRole role,
    String email = '',
    String phone = '',
  }) async {
    if (ownerUid.isEmpty) throw StateError('You are not signed in.');
    if (name.trim().isEmpty) throw StateError('Please enter a name.');

    final normalizedEmail = normalizeEmail(email);
    final normalizedPhone = normalizePhone(phone);

    if (normalizedEmail.isEmpty && normalizedPhone.isEmpty) {
      throw StateError('Enter an email address or phone number.');
    }

    final key = contactKey(email: normalizedEmail, phone: normalizedPhone);

    final memberRef = _members.doc();
    final invitationRef = _invitations.doc();

    final batch = _db.batch();

    batch.set(memberRef, {
      'ownerUid': ownerUid,
      'name': name.trim(),
      'role': role.name,
      'email': normalizedEmail,
      'phone': normalizedPhone,
      'invitationStatus': FamilyInvitationStatus.pending.name,
      'invitationId': invitationRef.id,
      'linkedUid': null,
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.set(invitationRef, {
      'ownerUid': ownerUid,
      'ownerName': ownerName.trim().isEmpty ? 'Nisa Member' : ownerName.trim(),
      'familyMemberId': memberRef.id,
      'inviteeName': name.trim(),
      'role': role.name,
      'email': normalizedEmail,
      'phone': normalizedPhone,
      'contactKey': key,
      'inviteeUid': null,
      'status': invitation_model.FamilyInvitationStatus.pending.name,
      'createdAt': FieldValue.serverTimestamp(),
      'respondedAt': null,
    });

    await batch.commit();

    // The recipient is the email entered in the Family / Guardian form. It
    // must never be replaced with the owner's OTP/login email.
    if (normalizedEmail.isNotEmpty) {
      await sendEmailInvitation(invitationId: invitationRef.id);
    }
  }

  static Future<void> sendEmailInvitation({
    required String invitationId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('You are not signed in.');

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Your sign-in session expired. Please sign in again.');
    }

    final response = await http.post(
      Uri.parse('${ServerConfig.baseUrl}/api/family/invitations/email'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'invitationId': invitationId}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Could not send the family invitation email.';
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        message = data['detail']?.toString() ?? message;
      } catch (_) {
        // Keep the safe generic message when the server did not return JSON.
      }
      throw StateError(
        'Invitation saved, but the email could not be sent: $message',
      );
    }
  }

  static Future<void> cancelAndDeleteMember(FamilyMember member) async {
    final batch = _db.batch();

    if (member.invitationId.isNotEmpty &&
        member.invitationStatus == FamilyInvitationStatus.pending) {
      batch.update(_invitations.doc(member.invitationId), {
        'status': invitation_model.FamilyInvitationStatus.cancelled.name,
        'respondedAt': FieldValue.serverTimestamp(),
      });
    }

    batch.delete(_members.doc(member.id));
    await batch.commit();
  }

  static Future<void> deleteMember(String memberId) async {
    await _members.doc(memberId).delete();
  }

  static Stream<List<invitation_model.FamilyInvitation>>
  watchInvitationsForCurrentUser() {
    final user = FirebaseAuth.instance.currentUser;
    final email = normalizeEmail(user?.email ?? '');

    if (user == null || email.isEmpty) {
      return Stream.value(const <invitation_model.FamilyInvitation>[]);
    }

    final key = 'email:$email';

    return _invitations.where('contactKey', isEqualTo: key).snapshots().map((
      snapshot,
    ) {
      final invitations = snapshot.docs
          .map(
            (doc) =>
                invitation_model.FamilyInvitation.fromMap(doc.id, doc.data()),
          )
          .where(
            (invitation) =>
                invitation.status ==
                invitation_model.FamilyInvitationStatus.pending,
          )
          .toList();

      invitations.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return invitations;
    });
  }

  static Future<void> respondToInvitation({
    required invitation_model.FamilyInvitation invitation,
    required bool accept,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('You are not signed in.');

    final email = normalizeEmail(user.email ?? '');
    if (email.isEmpty) {
      throw StateError('Your signed-in Nisa account needs an email address.');
    }

    if (invitation.contactKey != 'email:$email') {
      throw StateError(
        'This invitation was not sent to your signed-in email address.',
      );
    }

    final invitationRef = _invitations.doc(invitation.id);
    final memberRef = _members.doc(invitation.familyMemberId);

    await _db.runTransaction((transaction) async {
      final invitationSnapshot = await transaction.get(invitationRef);

      if (!invitationSnapshot.exists) {
        throw StateError('This invitation no longer exists.');
      }

      final data = invitationSnapshot.data()!;
      if (data['status'] != 'pending') {
        throw StateError('This invitation has already been answered.');
      }

      if (data['contactKey'] != 'email:$email') {
        throw StateError('This invitation belongs to another account.');
      }

      transaction.update(invitationRef, {
        'status': accept ? 'accepted' : 'declined',
        'inviteeUid': user.uid,
        'respondedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(memberRef, {
        'invitationStatus': accept ? 'accepted' : 'declined',
        'linkedUid': accept ? user.uid : null,
      });
    });
  }
}
