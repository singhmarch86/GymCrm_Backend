import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api_response.dart';
import '../theme/app_colors.dart';
import 'platform_console_screen.dart';
import 'platform_service.dart';

final _brand = FilledButton.styleFrom(
  backgroundColor: AppColors.primary,
  foregroundColor: Colors.white,
);

/// Vendor sign-in: password, then a six-digit authenticator code. A first
/// login (or one after a reset) can only enrol two-factor (FR-12 §10).
class PlatformLoginScreen extends StatefulWidget {
  const PlatformLoginScreen({super.key});

  @override
  State<PlatformLoginScreen> createState() => _PlatformLoginScreenState();
}

class _PlatformLoginScreenState extends State<PlatformLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _needCode = false;
  bool _useRecovery = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = _code.text.trim();
      final r = await PlatformService.login(
        _email.text.trim(),
        _password.text,
        code: _useRecovery ? '' : code,
        recoveryCode: _useRecovery ? code : '',
      );
      if (!mounted) return;
      if (r['enrolment_required'] == true) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PlatformEnrolScreen(enrolToken: r['token']),
          ),
        );
      } else if (r['totp_required'] == true) {
        setState(() => _needCode = true);
      } else {
        PlatformService.useToken(
          r['token'],
          Map<String, dynamic>.from(r['admin'] ?? {}),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PlatformConsoleScreen()),
        );
      }
    } catch (e) {
      setState(
        () => _error = e is ApiException ? e.message : 'Something went wrong.',
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Vendor console')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Platform sign-in',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'For the people who run MOKA CRM. Gym accounts do not sign in here.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _email,
                  enabled: !_needCode,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  enabled: !_needCode,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _needCode ? null : _submit(),
                ),
                if (_needCode) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    keyboardType: _useRecovery
                        ? TextInputType.text
                        : TextInputType.number,
                    maxLength: _useRecovery ? 9 : 6,
                    decoration: InputDecoration(
                      labelText: _useRecovery
                          ? 'Recovery code'
                          : 'Authenticator code (6 digits)',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _useRecovery = !_useRecovery;
                      _code.clear();
                    }),
                    child: Text(
                      _useRecovery
                          ? 'Use my authenticator app'
                          : 'Lost my phone — use a recovery code',
                    ),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  style: _brand,
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_needCode ? 'Verify and sign in' : 'Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Forced enrolment: scan, prove it with a code, then keep the recovery codes.
class PlatformEnrolScreen extends StatefulWidget {
  final String enrolToken;
  const PlatformEnrolScreen({super.key, required this.enrolToken});

  @override
  State<PlatformEnrolScreen> createState() => _PlatformEnrolScreenState();
}

class _PlatformEnrolScreenState extends State<PlatformEnrolScreen> {
  Map<String, dynamic>? _setup;
  Map<String, dynamic>? _done;
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    PlatformService.startEnrolment(
      widget.enrolToken,
    ).then((v) => mounted ? setState(() => _setup = v) : null).catchError((e) {
      if (mounted)
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Could not start enrolment.',
        );
    });
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await PlatformService.confirmEnrolment(
        widget.enrolToken,
        _code.text.trim(),
      );
      PlatformService.useToken(
        r['token'],
        Map<String, dynamic>.from(r['admin'] ?? {}),
      );
      if (mounted) setState(() => _done = r);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'That code did not work.',
        );
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final codes = (_done?['recovery_codes'] as List?)?.cast<String>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Set up two-factor'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: codes != null ? _recovery(codes) : _scan(),
          ),
        ),
      ),
    );
  }

  Widget _scan() {
    final s = _setup;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Two-factor is required for every platform admin. Scan this with Google Authenticator, Microsoft Authenticator or Authy, then enter the 6-digit code it shows.',
        ),
        const SizedBox(height: 16),
        if (s == null && _error == null)
          const Center(child: CircularProgressIndicator()),
        if (s != null) ...[
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(data: s['otpauth_uri'], size: 200),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Or type this key into the app:',
            textAlign: TextAlign.center,
          ),
          SelectableText(
            s['secret'],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Code from the app',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _confirm(),
          ),
        ],
        if (_error != null)
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        const SizedBox(height: 12),
        if (s != null)
          FilledButton(
            style: _brand,
            onPressed: _busy ? null : _confirm,
            child: const Text('Confirm and finish'),
          ),
      ],
    );
  }

  Widget _recovery(List<String> codes) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Save your recovery codes',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'Each works once if you lose your phone. They are shown only now and cannot be shown again. Keep them somewhere safe and OFF this computer. Create a second platform admin today.',
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: SelectableText(
          codes.join('\n'),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 16,
            height: 1.6,
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        style: _brand,
        onPressed: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PlatformConsoleScreen()),
        ),
        child: const Text("I've saved them — open the console"),
      ),
    ],
  );
}
