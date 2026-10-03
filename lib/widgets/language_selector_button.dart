import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_language_service.dart';
import 'localized_text.dart';

/// Reusable app-language picker for onboarding and major screens.
class LanguageSelectorButton extends StatelessWidget {
  const LanguageSelectorButton({super.key});

  Future<void> _openPicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: const LocalizedText(
                      'Choose language',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: AppLanguageService.languages.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final language = AppLanguageService.languages[index];
                      return ValueListenableBuilder<String>(
                        valueListenable: AppLanguageService.selectedCode,
                        builder: (context, selectedCode, _) {
                          final selected = language.code == selectedCode;
                          return ListTile(
                            leading: const Icon(Icons.language_rounded),
                            title: LocalizedText(language.name),
                            subtitle: Text(language.nativeName),
                            trailing: selected
                                ? const Icon(Icons.check_circle_rounded)
                                : null,
                            onTap: () {
                              unawaited(
                                AppLanguageService.setLanguage(language),
                              );
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLanguageService.selectedCode,
      builder: (context, _, _) => IconButton(
        tooltip: AppLanguageService.translate('Choose language'),
        icon: const Icon(Icons.language_rounded),
        onPressed: () => _openPicker(context),
      ),
    );
  }
}
