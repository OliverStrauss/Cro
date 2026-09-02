import 'package:flutter/material.dart';

import '../theme.dart';

// Shared field styling for the login/sign-up forms - a filled, rounded field with a leading
// icon, matching this app's card-and-soft-shadow language instead of Material's default
// underline/outline field. `obscureText: true` gets a show/hide toggle for free rather than
// needing every caller to wire its own.
class AuthTextField extends StatefulWidget {
  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final List<String>? autofillHints;
  final bool autocorrect;
  final bool enableSuggestions;

  const AuthTextField({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.onSubmitted,
    this.textInputAction,
    this.autofillHints,
    this.autocorrect = true,
    this.enableSuggestions = true,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: widget.fieldKey,
      controller: widget.controller,
      obscureText: _obscured,
      keyboardType: widget.keyboardType,
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      autocorrect: widget.autocorrect,
      enableSuggestions: widget.enableSuggestions,
      style: const TextStyle(fontSize: 14.5),
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: Icon(widget.icon, size: 19, color: CroColors.fog),
        suffixIcon: widget.obscureText
            ? IconButton(
                key: Key('${widget.fieldKey.toString()}VisibilityToggle'),
                icon: Icon(_obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 19, color: CroColors.fog),
                onPressed: () => setState(() => _obscured = !_obscured),
              )
            : null,
        filled: true,
        fillColor: CroColors.background.withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: CroColors.waypointBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 1.2),
        ),
      ),
    );
  }
}
