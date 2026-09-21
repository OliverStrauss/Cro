import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/auth_error_banner.dart';
import '../widgets/auth_shell.dart';
import '../widgets/auth_text_field.dart';

// Same two-step-in-one-screen shape as ForgotPasswordScreen. Reached two ways: right after
// sign-up, where a code has already been emailed and initialEmail is known (skips straight to
// the code-entry step), or from a login blocked on an unverified account, where the email
// isn't known yet and the first step asks for it before a code can be sent.
class VerifyEmailScreen extends StatefulWidget {
  final String? initialEmail;

  const VerifyEmailScreen({super.key, this.initialEmail});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(text: widget.initialEmail);
  final _codeController = TextEditingController();
  final _authService = AuthService();

  late bool _codeSent = widget.initialEmail != null;
  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_emailController.text.trim().isEmpty || !_emailController.text.contains('@')) {
      setState(() => _errorMessage = 'Enter a valid email');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _authService.resendVerificationEmail(_emailController.text);
      if (mounted) setState(() => _codeSent = true);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    try {
      await _authService.resendVerificationEmail(_emailController.text);
      if (mounted) setState(() => _infoMessage = 'Sent a new code to ${_emailController.text}.');
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verify() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    try {
      await _authService.verifyEmail(_emailController.text, _codeController.text);
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
      heading: 'Verify your email',
      subheading: _codeSent
          ? 'Enter the code we emailed to ${_emailController.text}.'
          : 'Enter your account email and we\'ll send you a verification code.',
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Back to', style: TextStyle(fontSize: 12.5, color: CroColors.fog)),
          TextButton(
            key: const Key('backToLoginButton'),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('log in', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: CroColors.deepWaypoint)),
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
                  textInputAction: TextInputAction.done,
                  validator: (v) => (v == null || v.trim().length != 6) ? 'Enter the 6-digit code' : null,
                  onSubmitted: (_) => _isLoading ? null : _verify(),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('resendCodeButton'),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                    onPressed: _isLoading ? null : _resendCode,
                    child: const Text('Resend code', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: CroColors.deepWaypoint)),
                  ),
                ),
              ],
              if (_infoMessage != null) ...[
                const SizedBox(height: 8),
                Text(_infoMessage!, style: const TextStyle(fontSize: 12.5, color: CroColors.fog)),
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
                  onPressed: _isLoading ? null : (_codeSent ? _verify : _sendCode),
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
                      : Text(_codeSent ? 'Verify' : 'Send code', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
