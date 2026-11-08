import 'presentation/nisa_premium/nisa_premium.dart';

import 'package:flutter/material.dart';

import 'services/api_safety_service.dart';
import 'widgets/localized_text.dart';

/// Destination for member-facing moderation notices. The API returns only the
/// signed-in member's active restrictions and notice text.
class ApiAccountRestrictionsScreen extends StatefulWidget {
  const ApiAccountRestrictionsScreen({
    super.key,
    this.notificationTitle,
    this.notificationBody,
  });

  final String? notificationTitle;
  final String? notificationBody;

  @override
  State<ApiAccountRestrictionsScreen> createState() =>
      _ApiAccountRestrictionsScreenState();
}

class _ApiAccountRestrictionsScreenState
    extends State<ApiAccountRestrictionsScreen> {
  late Future<List<Map<String, dynamic>>> _restrictions =
      ApiSafetyService.getAccountRestrictions();

  Future<void> _refresh() async {
    final request = ApiSafetyService.getAccountRestrictions();
    setState(() {
      _restrictions = request;
    });
    await request;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('Account restriction active')),
    body: NisaPageBody(
      form: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _restrictions,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(snapshot.error.toString()),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final restrictions = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if ((widget.notificationTitle ?? '').isNotEmpty ||
                    (widget.notificationBody ?? '').isNotEmpty)
                  Card(
                    child: ListTile(
                      title: Text(widget.notificationTitle ?? ''),
                      subtitle: Text(widget.notificationBody ?? ''),
                    ),
                  ),
                if (restrictions.isEmpty &&
                    (widget.notificationTitle ?? '').isEmpty &&
                    (widget.notificationBody ?? '').isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: LocalizedText('No active account restrictions.'),
                  ),
                ...restrictions.map((item) {
                  final expiry = item['expires_at']?.toString();
                  return Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_rounded),
                      title: const LocalizedText('Account restriction active'),
                      subtitle: Text(
                        [
                          item['user_notice']?.toString(),
                          if (expiry != null && expiry.isNotEmpty) expiry,
                        ].whereType<String>().join('\n'),
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    ),
  );
}
