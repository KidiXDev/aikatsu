import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';

/// Sync's sign-in page; true once signed in.
Future<bool> signIn(BuildContext context, {required bool create}) async =>
    await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AccountPage(create: create))) ?? false;

/// Only once the repeat can no longer turn into a match, so typing it doesn't flash an error.
bool mismatched(String password, String repeat) =>
    repeat != password && repeat.isNotEmpty && (repeat.length >= password.length || !password.startsWith(repeat));

/// Signs in to sync or creates an account; the link at the bottom switches between the two.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.create});

  final bool create;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late bool _create = widget.create;
  final _user = TextEditingController(), _password = TextEditingController(), _repeat = TextEditingController();
  final _shown = [false, false];
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  bool get _ready =>
      !_busy &&
      _user.text.trim().isNotEmpty &&
      _password.text.trim().isNotEmpty &&
      (!_create || _repeat.text == _password.text);

  void _switch() => setState(() {
    _create = !_create;
    _repeat.clear();
    _error = '';
  });

  Future<void> _submit() async {
    if (!_ready) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await Api.call('syncSignIn', {'username': _user.text.trim(), 'password': _password.text, 'create': _create});
      if (!mounted) return;
      toast(_create ? 'Account created' : 'Signed in');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    required bool last,
    int? secret,
    String? error,
    Iterable<String>? hints,
  }) => TextField(
        controller: controller,
        autocorrect: false,
        enableSuggestions: secret == null,
        obscureText: secret != null && !_shown[secret],
        autofillHints: hints,
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          errorMaxLines: 3,
          suffixIcon: secret == null ? null : revealButton(_shown[secret], () => setState(() => _shown[secret] = !_shown[secret])),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: last ? (_) => _submit() : null,
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: SakuraBlossom(size: 56, petalColor: c.primary, centerColor: c.secondary)),
                    const SizedBox(height: 20),
                    Text(
                      _create ? 'はじめまして · HELLO' : 'おかえり · WELCOME',
                      textAlign: TextAlign.center,
                      style: t.textTheme.labelMedium?.copyWith(color: c.primary, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _create ? 'Create account' : 'Sign in',
                      textAlign: TextAlign.center,
                      style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sync history and settings across devices.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant, height: 1.4),
                    ),
                    const SizedBox(height: 28),
                    _field(_user, 'Username', last: false, hints: const [AutofillHints.username]),
                    const SizedBox(height: 12),
                    _field(
                      _password,
                      'Password',
                      secret: 0,
                      last: !_create,
                      hints: [_create ? AutofillHints.newPassword : AutofillHints.password],
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _create
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _field(
                                _repeat,
                                'Confirm password',
                                secret: 1,
                                last: true,
                                error: mismatched(_password.text, _repeat.text) ? "Passwords don't match" : null,
                                hints: const [AutofillHints.newPassword],
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 18, color: c.error),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error, style: t.textTheme.bodyMedium?.copyWith(color: c.error))),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    PillButton(
                      icon: _create ? Icons.person_add_rounded : Icons.login_rounded,
                      label: _busy ? 'Please wait…' : (_create ? 'Create account' : 'Sign in'),
                      filled: true,
                      onTap: _ready ? _submit : null,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _create ? 'Have an account?' : 'New here?',
                          style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                        ),
                        TextButton(onPressed: _busy ? null : _switch, child: Text(_create ? 'Sign in' : 'Create account')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
