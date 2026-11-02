import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../login_screen.dart';
import '../platform/platform_console_screen.dart';
import '../platform/platform_service.dart';
import '../services/api_config.dart';
import '../services/api_response.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';

/// Shown above the whole shell while a platform admin is viewing this gym
/// through a support token (FR-12 §4–5). The server enforces read-only; this
/// only makes the state impossible to miss and gives a way out.
class SupportBanner extends StatefulWidget {
  final Widget child;
  const SupportBanner({super.key, required this.child});

  @override
  State<SupportBanner> createState() => _SupportBannerState();
}

class _SupportBannerState extends State<SupportBanner> {
  DateTime? _until;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    StorageService.getSupportExpiry().then((d) {
      if (!mounted || d == null) return;
      setState(() => _until = d);
      _tick = Timer.periodic(const Duration(seconds: 20), (_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _exit() async {
    await StorageService.clearAll();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => PlatformService.signedIn
            ? const PlatformConsoleScreen()
            : const LoginScreen(),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final until = _until;
    if (until == null) return widget.child;
    final left = until.difference(DateTime.now());
    final label = left.isNegative
        ? 'expired'
        : '${left.inMinutes + 1} min left';
    return Column(
      children: [
        Material(
          color: AppColors.danger,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Vendor support view · read-only · $label',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _exit,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Exit'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// Owner-facing record of every time the vendor entered this gym (FR-12 §6).
class SupportAccessScreen extends StatelessWidget {
  const SupportAccessScreen({super.key});

  Future<List<dynamic>> _load() async {
    final token = await StorageService.getAccessToken();
    final res = await guardRequest(
      () => http.get(
        Uri.parse('$kBaseUrl/api/v1/gyms/support-access'),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    return unwrapJson(res)['data'] as List? ?? [];
  }

  String _when(String iso) {
    final d = DateTime.parse(iso).toLocal();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} ${p(d.hour)}:${p(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Vendor support access')),
      body: FutureBuilder<List<dynamic>>(
        future: _load(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                snap.error is ApiException
                    ? (snap.error as ApiException).message
                    : 'Could not load.',
              ),
            );
          }
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final rows = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text(
                'If you report a problem, someone from MOKA CRM may look at your account to help. It is always read-only, lasts at most 30 minutes, needs a stated reason — and it is listed here every time.',
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Nobody from MOKA CRM has ever entered your account.',
                    ),
                  ),
                ),
              for (final r in rows)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.visibility_outlined),
                    title: Text(
                      '${r['admin_name']} · ${_when(r['started_at'])}',
                    ),
                    subtitle: Text(
                      'Reason: ${r['reason']}\nAccess ended by ${_when(r['expires_at'])}',
                    ),
                    isThreeLine: true,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
