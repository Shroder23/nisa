import 'presentation/nisa_premium/nisa_premium.dart';

import 'package:flutter/material.dart';

import 'services/api_safety_service.dart';
import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';

class ApiModeratorRecommendationsScreen extends StatefulWidget {
  const ApiModeratorRecommendationsScreen({
    super.key,
    this.administrator = false,
  });
  final bool administrator;

  @override
  State<ApiModeratorRecommendationsScreen> createState() =>
      _ApiModeratorRecommendationsScreenState();
}

class _ApiModeratorRecommendationsScreenState
    extends State<ApiModeratorRecommendationsScreen> {
  final _title = TextEditingController();
  final _details = TextEditingController();
  String _category = 'security';
  bool _busy = false;
  late Future<List<Map<String, dynamic>>> _items =
      ApiSafetyService.getModeratorRecommendations();

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  String _categoryLabel(String raw) => switch (raw) {
    'security' => 'Security',
    'member_safety' => 'Safety',
    'verification' => 'Verification',
    'workflow' => 'Workflow',
    _ => 'Other',
  };

  String _statusLabel(String raw) => switch (raw) {
    'new' => 'New',
    'reviewing' => 'Reviewing',
    'planned' => 'Planned',
    'declined' => 'Declined',
    'completed' => 'Completed',
    _ => raw,
  };

  void _refresh() {
    final request = ApiSafetyService.getModeratorRecommendations();
    setState(() {
      _items = request;
    });
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: LocalizedText(text)));

  Future<void> _submit() async {
    if (_title.text.trim().length < 5 || _details.text.trim().length < 10) {
      _message(
        'Add a title and at least 10 characters describing the improvement.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiSafetyService.submitModeratorRecommendation(
        category: _category,
        title: _title.text.trim(),
        details: _details.text.trim(),
      );
      if (!mounted) {
        return;
      }
      _title.clear();
      _details.clear();
      _refresh();
      _message('Recommendation sent to platform administrators.');
    } catch (error) {
      _message(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _update(Map<String, dynamic> item) async {
    var noteText = item['admin_note']?.toString() ?? '';
    String status = item['status']?.toString() ?? 'new';
    final form = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const LocalizedText('Review'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                itemHeight: null,
                isDense: false,
                initialValue: status,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Status'),
                ),
                items: const [
                  DropdownMenuItem(value: 'new', child: LocalizedText('New')),
                  DropdownMenuItem(
                    value: 'reviewing',
                    child: LocalizedText('Reviewing'),
                  ),
                  DropdownMenuItem(
                    value: 'planned',
                    child: LocalizedText('Planned'),
                  ),
                  DropdownMenuItem(
                    value: 'declined',
                    child: LocalizedText('Declined'),
                  ),
                  DropdownMenuItem(
                    value: 'completed',
                    child: LocalizedText('Completed'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialog(() => status = value);
                  }
                },
              ),
              TextFormField(
                initialValue: noteText,
                onChanged: (value) => noteText = value,
                minLines: 2,
                maxLines: 4,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate(
                    'Private moderator note',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const LocalizedText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'status': status,
                'note': noteText.trim(),
              }),
              child: const LocalizedText('Save'),
            ),
          ],
        ),
      ),
    );
    if (form == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiSafetyService.updateModeratorRecommendation(
        recommendationId: item['id'].toString(),
        status: form['status']!,
        adminNote: form['note']!,
      );
      if (!mounted) {
        return;
      }
      _refresh();
    } catch (error) {
      _message(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('Moderator recommendation'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: NisaPageBody(
      form: false,
      child: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!widget.administrator) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                itemHeight: null,
                isDense: false,
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Category'),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'security',
                    child: LocalizedText('Security'),
                  ),
                  DropdownMenuItem(
                    value: 'member_safety',
                    child: LocalizedText('Safety'),
                  ),
                  DropdownMenuItem(
                    value: 'verification',
                    child: LocalizedText('Verification'),
                  ),
                  DropdownMenuItem(
                    value: 'workflow',
                    child: LocalizedText('Workflow'),
                  ),
                  DropdownMenuItem(
                    value: 'other',
                    child: LocalizedText('Other'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _title,
                maxLength: 140,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Title'),
                ),
              ),
              TextField(
                controller: _details,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Recommendation'),
                ),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: const Icon(Icons.send),
                label: const LocalizedText('Submit'),
              ),
              const SizedBox(height: 20),
              Text(
                AppLanguageService.translate('My recommendations'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ] else ...[
              const SizedBox(height: 12),
            ],
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _items,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(snapshot.error.toString());
                }
                if (!snapshot.hasData) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.data!.isEmpty) {
                  return const LocalizedText(
                    'No recommendations have been submitted.',
                  );
                }
                return Column(
                  children: snapshot.data!
                      .map(
                        (item) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item['title']?.toString() ?? '',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                    ),
                                    Chip(
                                      label: LocalizedText(
                                        _statusLabel(
                                          item['status']?.toString() ?? 'new',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    LocalizedText(
                                      _categoryLabel(
                                        item['category']?.toString() ?? 'other',
                                      ),
                                    ),
                                    const Text(' · '),
                                    Text(
                                      item['author_name']?.toString() ?? 'You',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(item['details']?.toString() ?? ''),
                                if (widget.administrator &&
                                    (item['admin_note']?.toString() ?? '')
                                        .isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const LocalizedText(
                                      'Private moderator note',
                                    ),
                                    subtitle: Text(
                                      item['admin_note']?.toString() ?? '',
                                    ),
                                  ),
                                ],
                                if (widget.administrator)
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: TextButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () => _update(item),
                                      icon: const Icon(Icons.edit_outlined),
                                      label: const LocalizedText(
                                        'Save decision',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}
