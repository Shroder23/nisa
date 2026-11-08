import 'package:flutter/material.dart';
import 'nisa_premium_theme.dart';

/// All labels and content come from the host app, already localized.
class NisaSurface extends StatelessWidget {
  const NisaSurface({super.key, required this.child,
    this.padding = const EdgeInsets.all(20), this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Card(
    color: color, child: Padding(padding: padding, child: child),
  );
}

class NisaSectionHeading extends StatelessWidget {
  const NisaSectionHeading({super.key, required this.title, this.subtitle,
    this.icon, this.actionLabel, this.onAction});
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Wrap keeps a long translation from pushing the action out of bounds.
      Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, color: NisaPremiumTheme.plum, size: 22),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(title,
              style: Theme.of(context).textTheme.titleMedium)),
          ]),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
      if (subtitle != null) Text(subtitle!,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: NisaPremiumTheme.muted)),
    ],
  );
}

/// This is a true unavailable-photo fallback, not a fabricated person.
/// Supply a localized description such as "Photo unavailable".
class NisaPhotoFallback extends StatelessWidget {
  const NisaPhotoFallback({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label, image: true,
    child: const ExcludeSemantics(child: ColoredBox(
      color: NisaPremiumTheme.blush,
      child: Center(child: Icon(Icons.image_outlined,
        color: NisaPremiumTheme.muted, size: 28)),
    )),
  );
}

class NisaWelcomeCard extends StatelessWidget {
  const NisaWelcomeCard({super.key, required this.greeting,
    required this.name, required this.subtitle, required this.avatar});
  final String greeting, name, subtitle;
  final Widget avatar;
  @override
  Widget build(BuildContext context) => NisaSurface(
    color: NisaPremiumTheme.blush,
    child: LayoutBuilder(builder: (context, box) {
      final content = Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(greeting, style: Theme.of(context).textTheme.bodyMedium),
          if (name.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(name, style: Theme.of(context).textTheme.titleLarge),
          ],
          const SizedBox(height: 8),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        ],
      );
      final photo = ClipOval(child: SizedBox.square(dimension: 64, child: avatar));
      if (box.maxWidth < 270 || MediaQuery.textScalerOf(context).scale(16) > 24) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [photo, const SizedBox(height: 16), content]);
      }
      return Row(children: [photo, const SizedBox(width: 16), Expanded(child: content)]);
    }),
  );
}

/// A bounded, small preview rail. Its natural height follows its tallest card.
/// Pass a small preview set, not the entire paginated discovery result.
class NisaNearbyRail extends StatelessWidget {
  const NisaNearbyRail({super.key, required this.children, required this.empty});
  final List<Widget> children;
  final Widget empty;
  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return empty;
    return LayoutBuilder(builder: (context, box) {
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;
      final width = largeText ? 176.0 : ((box.maxWidth - 24) / 3).clamp(112.0, 152.0).toDouble();
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            SizedBox(width: width, child: children[i]),
          ],
        ]),
      );
    });
  }
}

/// Receives real data and the existing authorization-aware photo widget.
/// Does not fetch data, make an interest request, or invent local profile data.
class NisaProfileCard extends StatelessWidget {
  const NisaProfileCard({super.key, required this.title, required this.photo,
    required this.openLabel, required this.onOpen, this.location, this.detail,
    this.compact = false, this.actionLabel, this.actionIcon,
    this.onAction, this.actionBusy = false});
  final String title, openLabel;
  final String? location, detail, actionLabel;
  final Widget photo;
  final bool compact, actionBusy;
  final VoidCallback onOpen;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    final information = Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        if (location?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text(location!, style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: NisaPremiumTheme.muted)),
        ],
        if (!compact && detail?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text(detail!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
    final action = actionLabel == null || actionIcon == null ? null : IconButton(
      tooltip: actionLabel,
      onPressed: actionBusy ? null : onAction,
      style: IconButton.styleFrom(
        backgroundColor: NisaPremiumTheme.surface,
        foregroundColor: NisaPremiumTheme.plum,
        minimumSize: const Size(48, 48),
      ),
      icon: actionBusy
          ? const SizedBox.square(dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(actionIcon),
    );
    final body = compact
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Stack(children: [
              AspectRatio(aspectRatio: 1, child: photo),
              if (action != null) PositionedDirectional(top: 2, end: 2, child: action),
            ]),
            Padding(padding: const EdgeInsets.all(10), child: information),
          ])
        : Padding(padding: const EdgeInsets.all(12),
            child: LayoutBuilder(builder: (context, box) {
              final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
              final thumb = ClipRRect(borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(dimension: 80, child: photo));
              if (box.maxWidth < 280 || largeText) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [thumb, const Spacer(), if (action != null) action]),
                    const SizedBox(height: 12), information,
                  ]);
              }
              return Row(children: [thumb, const SizedBox(width: 14),
                Expanded(child: information), if (action != null) action]);
            }));
    return Card(clipBehavior: Clip.antiAlias,
      child: Semantics(label: openLabel,
        child: InkWell(onTap: onOpen, child: body)),
    );
  }
}

/// Use for genuine empty, permission or failure states. Not a permanent skeleton.
class NisaStateCard extends StatelessWidget {
  const NisaStateCard({super.key, required this.title, required this.message,
    this.icon = Icons.info_outline, this.actionLabel, this.onAction});
  final String title, message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => NisaSurface(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: NisaPremiumTheme.plum), const SizedBox(height: 12),
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8), Text(message),
      if (onAction != null && actionLabel != null) ...[
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    ],
  ));
}
