import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../state/auth_state.dart';
import '../theme.dart';
import '../widgets/auth_error_banner.dart';
import '../widgets/auth_shell.dart';
import '../widgets/auth_text_field.dart';

class SignUpScreen extends StatefulWidget {
  final AuthState authState;

  const SignUpScreen({super.key, required this.authState});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = await _authService.signUp(
        _usernameController.text,
        _emailController.text,
        _passwordController.text,
      );
      widget.authState.login(token);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      heading: 'Join Cro',
      subheading: 'Create an account and send your first cro on its way.',
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Already have an account?', style: TextStyle(fontSize: 12.5, color: CroColors.fog)),
          TextButton(
            key: const Key('goToLoginButton'),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Log in', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: CroColors.deepWaypoint)),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthTextField(
              fieldKey: const Key('usernameField'),
              controller: _usernameController,
              label: 'Username',
              icon: Icons.person_outline,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newUsername],
              autocorrect: false,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Choose a username' : null,
            ),
            const SizedBox(height: 14),
            AuthTextField(
              fieldKey: const Key('emailField'),
              controller: _emailController,
              label: 'Email',
              icon: Icons.alternate_email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: 14),
            AuthTextField(
              fieldKey: const Key('passwordField'),
              controller: _passwordController,
              label: 'Password',
              icon: Icons.lock_outline,
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              autocorrect: false,
              enableSuggestions: false,
              validator: (v) => (v == null || v.isEmpty) ? 'Choose a password' : null,
              onSubmitted: (_) => _isLoading ? null : _submit(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              AuthErrorBanner(message: _errorMessage!),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: CroColors.waypointBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Sign up', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
