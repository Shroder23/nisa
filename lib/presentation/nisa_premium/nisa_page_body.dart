import 'package:flutter/material.dart';

/// Constrains the existing route body without adding a scroll or navigation
/// owner. Existing controllers, SafeAreas, forms and async state stay inside.
class NisaPageBody extends StatelessWidget {
  const NisaPageBody({super.key, required this.child, this.form = false});
  final Widget child;
  final bool form;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: form ? 600 : 1120),
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: child,
      ),
    ),
  );
}
