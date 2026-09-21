import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/auth_error_banner.dart';
import '../widgets/auth_shell.dart';
import '../widgets/auth_text_field.dart';

// Two-step reset in one screen (request code, then redeem it) rather than a
// second pushed route - keeps the email address in one place and avoids an
// extra file for what's really one flow with two button presses.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _codeSent = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.forgotPassword(_emailController.text);
      if (mounted) setState(() => _codeSent = true);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.resetPassword(_emailController.text, _codeController.text, _newPasswordController.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      heading: 'Reset your password',
      subheading: _codeSent
          ? 'Enter the code we emailed to ${_emailController.text} and choose a new password.'
          : 'Enter your account email and we\'ll send you a reset code.',
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Remembered it?', style: TextStyle(fontSize: 12.5, color: CroColors.fog)),
          TextButton(
            key: const Key('backToLoginButton'),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Log in', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: CroColors.deepWaypoint)),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              if (_codeSent) ...[
                const SizedBox(height: 14),
                AuthTextField(
                  fieldKey: const Key('codeField'),
                  controller: _codeController,
                  label: '6-digit code',
                  icon: Icons.pin_outlined,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().length != 6) ? 'Enter the 6-digit code' : null,
                ),
                const SizedBox(height: 14),
                AuthTextField(
                  fieldKey: const Key('newPasswordField'),
                  controller: _newPasswordController,
                  label: 'New password',
                  icon: Icons.lock_outline,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  autocorrect: false,
                  enableSuggestions: false,
                  validator: (v) => (v == null || v.isEmpty) ? 'Choose a new password' : null,
                  onSubmitted: (_) => _isLoading ? null : _resetPassword(),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                AuthErrorBanner(message: _errorMessage!),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  key: const Key('submitButton'),
                  onPressed: _isLoading ? null : (_codeSent ? _resetPassword : _requestCode),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CroColors.waypointBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: CroBorders.radius),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_codeSent ? 'Reset password' : 'Send code', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
