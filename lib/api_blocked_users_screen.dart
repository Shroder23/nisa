import 'package:flutter/material.dart';

import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';

import 'services/api_safety_service.dart';

/// PostgreSQL-backed list of accounts blocked by the signed-in member.
class ApiBlockedUsersScreen extends StatefulWidget {
  const ApiBlockedUsersScreen({super.key});

  @override
  State<ApiBlockedUsersScreen> createState() => _ApiBlockedUsersScreenState();
}

class _ApiBlockedUsersScreenState extends State<ApiBlockedUsersScreen> {
  List<Map<String, dynamic>> _blocks = const [];
  final Set<String> _unblocking = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final blocks = await ApiSafetyService.getMyBlocks();
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _unblock(String userId) async {
    if (!_unblocking.add(userId)) return;
    setState(() {});
    try {
      await ApiSafetyService.unblockUser(userId);
      if (!mounted) return;
      setState(
        () => _blocks.removeWhere(
          (block) => block['blocked_id']?.toString() == userId,
        ),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LocalizedText('User unblocked.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText('Something went wrong. Please try again.'),
          ),
        );
      }
    } finally {
      _unblocking.remove(userId);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Blocked users'),
        actions: [
          IconButton(
            tooltip: AppLanguageService.translate('Refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _Message(message: _error!, onRetry: _load)
          : _blocks.isEmpty
          ? const _Message(message: 'You have not blocked anyone.')
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _blocks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final block = _blocks[index];
                  final id = block['blocked_id']?.toString() ?? '';
                  final name = block['blocked_name']?.toString().trim();
                  final location =
                      [
                            block['blocked_city']?.toString(),
                            block['blocked_country']?.toString(),
                          ]
                          .where((value) => value?.trim().isNotEmpty == true)
                          .join(', ');
                  final busy = _unblocking.contains(id);
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.block_outlined),
                      ),
                      title: Text(
                        name?.isNotEmpty == true ? name! : 'Nisa member',
                      ),
                      subtitle: Text(location.isEmpty ? id : location),
                      trailing: TextButton(
                        onPressed: busy ? null : () => _unblock(id),
                        child: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const LocalizedText('Unblock'),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _Message extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;

  const _Message({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LocalizedText(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const LocalizedText('Try again'),
            ),
          ],
        ],
      ),
    ),
  );
}
