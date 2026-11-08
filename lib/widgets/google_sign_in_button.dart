import 'package:flutter/material.dart';

import 'localized_text.dart';

/// Uses Google's supplied asset; no font glyph or generated brand substitute.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.busy = false,
  });
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: busy ? null : onPressed,
    style: OutlinedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF1F1F1F),
      side: const BorderSide(color: Color(0xFF747775)),
    ),
    icon: busy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Image.asset(
            'assets/icons/google-g.png',
            width: 20,
            height: 20,
            excludeFromSemantics: true,
          ),
    label: const LocalizedText('Continue with Google'),
  );
}
