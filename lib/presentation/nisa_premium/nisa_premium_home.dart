import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'nisa_premium_theme.dart';

/// Home-only brand header. Keep the existing shell's navigation and badge logic.
class NisaBrandAppBar extends StatelessWidget implements PreferredSizeWidget {
  const NisaBrandAppBar({
    super.key,
    required this.title,
    required this.menuLabel,
    required this.onMenu,
    required this.notificationLabel,
    required this.onNotifications,
    this.brandMark,
    this.notificationIcon,
    this.actions = const [],
  });
  final String title, menuLabel, notificationLabel;
  final VoidCallback onMenu, onNotifications;
  final Widget? brandMark, notificationIcon;
  final List<Widget> actions;
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: NisaPremiumTheme.plum,
    foregroundColor: Colors.white,
    systemOverlayStyle: SystemUiOverlayStyle.light,
    titleTextStyle: Theme.of(context).textTheme.titleLarge
        ?.copyWith(color: Colors.white),
    leading: IconButton(
      tooltip: menuLabel,
      onPressed: onMenu,
      icon: const Icon(Icons.menu_rounded),
    ),
    title: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (brandMark != null) ...[
          SizedBox.square(dimension: 28, child: brandMark!),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
    actions: [
      ...actions,
      IconButton(
        tooltip: notificationLabel,
        onPressed: onNotifications,
        icon: notificationIcon ?? const Icon(Icons.notifications_outlined),
      ),
    ],
  );
}

/// Body only: place directly in the existing five-tab shell.
/// The host owns requests, location permission, pagination and route actions.
class NisaPremiumHomeBody extends StatelessWidget {
  const NisaPremiumHomeBody({
    super.key,
    required this.welcome,
    required this.nearbyHeading,
    required this.nearbyContent,
    required this.recommendationHeading,
    required this.recommendationCount,
    required this.recommendationBuilder,
    required this.recommendationEmpty,
    this.recommendationStatus,
    this.onRefresh,
    this.recommendationNotice,
  });
  final Widget welcome, nearbyHeading, nearbyContent, recommendationHeading;
  final int recommendationCount;
  final IndexedWidgetBuilder recommendationBuilder;
  final Widget recommendationEmpty;

  /// Non-null replaces the list (e.g. loading or error); host clears when ready.
  final Widget? recommendationStatus;
  final Widget? recommendationNotice;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scroll = CustomScrollView(
      key: const PageStorageKey<String>('nisa-premium-home'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                welcome,
                const SizedBox(height: 28),
                nearbyHeading,
                const SizedBox(height: 12),
                nearbyContent,
                const SizedBox(height: 24),
                const Divider(height: 1),
                const SizedBox(height: 24),
                recommendationHeading,
                const SizedBox(height: 16),
                ?recommendationNotice,
              ],
            ),
          ),
        ),
        if (recommendationStatus != null || recommendationCount == 0)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: recommendationStatus ?? recommendationEmpty,
            ),
          ),
        if (recommendationStatus == null && recommendationCount > 0)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: recommendationBuilder(context, index),
                ),
                childCount: recommendationCount,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
    return onRefresh == null
        ? scroll
        : RefreshIndicator(onRefresh: onRefresh!, child: scroll);
  }
}
