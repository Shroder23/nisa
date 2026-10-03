import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';

import 'models/candidate_profile.dart';
import 'models/user_block.dart';
import 'services/app_state.dart';
import 'services/block_service.dart';
import 'services/candidate_service.dart';

class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = AppState.firebaseUser?.uid;
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Blocked Users'),
        centerTitle: true,
        actions: const [LanguageSelectorButton()],
      ),
      body: uid == null || uid.isEmpty
          ? const Center(child: LocalizedText('You are not signed in.'))
          : StreamBuilder<List<UserBlock>>(
              stream: BlockService.watchMyBlocks(uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: LocalizedText(
                      'Something went wrong. Please try again.',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final blocks = snapshot.data!;
                if (blocks.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: LocalizedText(
                        'You have not blocked anyone.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: blocks.length,
                  itemBuilder: (context, index) {
                    final block = blocks[index];
                    return _BlockedUserTile(block: block, currentUserId: uid);
                  },
                );
              },
            ),
    );
  }
}

class _BlockedUserTile extends StatefulWidget {
  final UserBlock block;
  final String currentUserId;

  const _BlockedUserTile({required this.block, required this.currentUserId});

  @override
  State<_BlockedUserTile> createState() => _BlockedUserTileState();
}

class _BlockedUserTileState extends State<_BlockedUserTile> {
  CandidateProfile? _candidate;
  bool _loading = true;
  bool _unblocking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _candidate = await CandidateService.getCandidateById(
        widget.block.blockedId,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock() async {
    setState(() => _unblocking = true);
    try {
      await BlockService.unblockUser(
        blockerId: widget.currentUserId,
        blockedId: widget.block.blockedId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LocalizedText('User unblocked.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
      setState(() => _unblocking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: ListTile(
          leading: CircleAvatar(child: CircularProgressIndicator()),
          title: LocalizedText('Loading...'),
        ),
      );
    }
    final candidate = _candidate;
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.block)),
        title: LocalizedText(candidate?.name ?? 'Nisa Member'),
        subtitle: candidate == null
            ? const LocalizedText('Profile unavailable')
            : LocalizedText(
                [
                  candidate.city,
                  candidate.country,
                ].where((e) => e.isNotEmpty).join(', '),
              ),
        trailing: TextButton(
          onPressed: _unblocking ? null : _unblock,
          child: _unblocking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const LocalizedText('Unblock'),
        ),
      ),
    );
  }
}
