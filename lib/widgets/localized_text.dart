import 'package:flutter/material.dart';

import '../services/app_language_service.dart';

/// A const-safe Text replacement that resolves its displayed text at build
/// time. Keeping the widget const-compatible lets it be used inside existing
/// const widget trees while still responding when the app locale changes.
class LocalizedText extends StatelessWidget {
  final String? data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;
  final Map<String, Object?>? substitutions;

  const LocalizedText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
    this.substitutions,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLanguageService.selectedCode,
      builder: (context, _, _) {
        final translated = data == null
            ? null
            : substitutions == null
            ? AppLanguageService.translate(data!)
            : AppLanguageService.translateTemplate(data!, substitutions!);

        return Text(
          translated ?? '',
          style: style,
          strutStyle: strutStyle,
          textAlign: textAlign,
          textDirection: textDirection,
          locale: locale,
          softWrap: softWrap,
          overflow: overflow,
          textScaler: textScaler,
          maxLines: maxLines,
          semanticsLabel: semanticsLabel,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior,
          selectionColor: selectionColor,
        );
      },
    );
  }
}

/// A locale-aware rich text container for screens that combine translated
/// labels with user data such as names, locations, counts, or dates.
class LocalizedRichText extends StatelessWidget {
  final InlineSpan Function() spanBuilder;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final int? maxLines;
  final TextOverflow? overflow;

  const LocalizedRichText({
    super.key,
    required this.spanBuilder,
    this.style,
    this.textAlign,
    this.textDirection,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLanguageService.selectedCode,
      builder: (context, _, _) => Text.rich(
        spanBuilder(),
        style: style,
        textAlign: textAlign,
        textDirection: textDirection,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}

/// Localized text containing the app's age threshold, with language-specific
/// numerals and an English fallback for spoken-only language codes.
class LocalizedAgeText extends StatelessWidget {
  final String template;
  final int age;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;

  const LocalizedAgeText(
    this.template, {
    super.key,
    this.age = 18,
    this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLanguageService.selectedCode,
      builder: (context, _, _) => Text(
        AppLanguageService.translateAge(template, age: age),
        style: style,
        textAlign: textAlign,
        overflow: overflow,
        maxLines: maxLines,
      ),
    );
  }
}

/// Displays a canonical stored height such as 5'7" without allowing RTL
/// layout to reverse the feet/inches order.
class LocalizedHeightText extends StatelessWidget {
  final String value;
  final TextStyle? style;
  final TextOverflow? overflow;
  final int? maxLines;

  const LocalizedHeightText(
    this.value, {
    super.key,
    this.style,
    this.overflow,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLanguageService.selectedCode,
      builder: (context, _, _) => Text(
        AppLanguageService.formatHeight(value),
        style: style,
        textDirection: TextDirection.ltr,
        overflow: overflow,
        maxLines: maxLines,
      ),
    );
  }
}
