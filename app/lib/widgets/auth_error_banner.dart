import 'package:flutter/material.dart';

// Shared error display for the login/sign-up forms - a tinted banner instead of bare red text,
// used identically by both screens.
class AuthErrorBanner extends StatelessWidget {
  final String message;

  const AuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: error),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(fontSize: 12.5, color: error, height: 1.4))),
        ],
      ),
    );
  }
}
