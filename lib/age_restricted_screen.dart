import 'widgets/localized_text.dart';

import 'package:flutter/material.dart';

class AgeRestrictedScreen extends StatelessWidget {
  const AgeRestrictedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.lock_person, size: 80, color: Colors.red),
                SizedBox(height: 24),
                LocalizedText(
                  'Account Restricted',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                LocalizedText(
                  'Nisa is intended for adults (18 years and older). '
                  'Your account cannot access matrimonial features at this time.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
