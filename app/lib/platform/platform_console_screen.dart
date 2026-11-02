import 'package:flutter/material.dart';

import '../login_screen.dart';
import '../services/api_response.dart';
import '../services/entitlements_service.dart';
import '../services/storage_service.dart';
import '../shell/app_shell.dart';
import '../theme/app_colors.dart';
import 'platform_service.dart';

final _brand = FilledButton.styleFrom(
  backgroundColor: AppColors.primary,
  foregroundColor: Colors.white,
);

String _err(Object e) =>
    e is ApiException ? e.message : 'Something went wrong.';

String _when(dynamic iso) {
  if (iso == null) return 'never';
  final d = DateTime.parse(iso as String).toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.day}/${d.month}/${d.year} ${p(d.hour)}:${p(d.minute)}';
}

const _tiers = {'normal': 'Normal', 'medium': 'Medium', 'premium': 'Premium'};

/// Asks for a mandatory free-text reason; null if cancelled.
Future<String?> _askReason(BuildContext context, String title, String hint) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: _brand,
          onPressed: () => c.text.trim().length < 5
              ? null
              : Navigator.pop(ctx, c.text.trim()),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
}

class PlatformConsoleScreen extends StatefulWidget {
  const PlatformConsoleScreen({super.key});

  @override
  State<PlatformConsoleScreen> createState() => _PlatformConsoleScreenState();
}

class _PlatformConsoleScreenState extends State<PlatformConsoleScreen> {
  void _signOut() {
    PlatformService.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformService.signedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _signOut());
      return const Scaffold();
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            'Vendor console · ${PlatformService.admin?['name'] ?? ''}',
          ),
          actions: [
            TextButton(onPressed: _signOut, child: const Text('Sign out')),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Gyms'),
              Tab(text: 'Activity log'),
              Tab(text: 'Admins'),
            ],
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: const TabBarView(
              children: [_GymsTab(), _ActivityTab(), _AdminsTab()],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Gyms ─────────────────────────────────────────────────────────────────────

class _GymsTab extends StatefulWidget {
  const _GymsTab();
  @override
  State<_GymsTab> createState() => _GymsTabState();
}

class _GymsTabState extends State<_GymsTab> {
  late Future<List<Map<String, dynamic>>> _f = PlatformService.gyms();

  void _reload() => setState(() => _f = PlatformService.gyms());

  Future<void> _create() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _CreateGymDialog(),
    );
    if (ok == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New gym'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(_err(snap.error!)));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final gyms = snap.data!;
          if (gyms.isEmpty) return const Center(child: Text('No gyms yet.'));
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              itemCount: gyms.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final g = gyms[i];
                final suspended = g['status'] == 'suspended';
                return Card(
                  child: ListTile(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlatformGymScreen(gymId: g['id']),
                        ),
                      );
                      _reload();
                    },
                    title: Text(
                      g['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${g['city']} · ${g['members']} members · last login ${_when(g['last_login'])}',
                    ),
                    trailing: Wrap(
                      spacing: 6,
                      children: [
                        Chip(
                          label: Text(_tiers[g['plan_tier']] ?? g['plan_tier']),
                        ),
                        Chip(
                          label: Text(
                            suspended ? 'Suspended' : g['subscription_status'],
                          ),
                          backgroundColor: suspended
                              ? AppColors.dangerLight
                              : AppColors.successLight,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CreateGymDialog extends StatefulWidget {
  const _CreateGymDialog();
  @override
  State<_CreateGymDialog> createState() => _CreateGymDialogState();
}

class _CreateGymDialogState extends State<_CreateGymDialog> {
  final _c = {
    for (final k in [
      'gym_name',
      'owner_name',
      'phone',
      'email',
      'city',
      'password',
    ])
      k: TextEditingController(),
  };
  String _tier = 'normal';
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PlatformService.createGym({
        for (final e in _c.entries) e.key: e.value.text.trim(),
        'plan_tier': _tier,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _err(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    Widget f(String k, String label, {bool pw = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _c[k],
        obscureText: pw,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
    return AlertDialog(
      title: const Text('New gym and its owner'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            children: [
              f('gym_name', 'Gym name'),
              f('owner_name', 'Owner name'),
              f('phone', 'Owner phone (login ID)'),
              f('email', 'Email (optional)'),
              f('city', 'City (default Ludhiana)'),
              f(
                'password',
                "Owner's starting password (8+ characters)",
                pw: true,
              ),
              DropdownButtonFormField<String>(
                initialValue: _tier,
                decoration: const InputDecoration(
                  labelText: 'Plan',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final e in _tiers.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _tier = v!),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: _brand,
          onPressed: _busy ? null : _save,
          child: const Text('Create gym'),
        ),
      ],
    );
  }
}

// ── One gym ──────────────────────────────────────────────────────────────────

class PlatformGymScreen extends StatefulWidget {
  final int gymId;
  const PlatformGymScreen({super.key, required this.gymId});
  @override
  State<PlatformGymScreen> createState() => _PlatformGymScreenState();
}

class _PlatformGymScreenState extends State<PlatformGymScreen> {
  late Future<Map<String, dynamic>> _f = PlatformService.gym(widget.gymId);

  void _reload() => setState(() => _f = PlatformService.gym(widget.gymId));

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      _reload();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_err(e))));
    }
  }

  Future<void> _enter(Map<String, dynamic> g) async {
    final reason = await _askReason(
      context,
      'Enter ${g['name']}',
      'Why are you looking at this gym? (the owner can see this)',
    );
    if (reason == null || !mounted) return;
    try {
      final s = await PlatformService.enter(widget.gymId, reason);
      await StorageService.saveAuthData(
        accessToken: s['access_token'],
        refreshToken: '',
        userId: s['user']['id'],
        gymId: s['user']['gym_id'],
        role: 'owner',
        userName: s['user']['name'],
        planTier: s['gym']['plan_tier'],
      );
      await StorageService.saveSupportExpiry(DateTime.parse(s['expires_at']));
      EntitlementsService.setTier(s['gym']['plan_tier'] as String?);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AppShell()),
        (_) => false,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_err(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Gym')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(_err(snap.error!)));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final g = snap.data!;
          final suspended = g['status'] == 'suspended';
          Widget stat(String l, Object v) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(l)),
                Text('$v', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          );
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    g['name'],
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${g['city']} · customer since ${_when(g['created_at'])}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Counts only — no member names, phones or payments are shown here. To look at their screens, enter the gym (read-only, logged, visible to the owner).',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          stat(
                            'Members (active / total)',
                            '${g['active_members']} / ${g['members']}',
                          ),
                          stat('Staff accounts', g['staff']),
                          stat('Payments, last 30 days', g['payments_30_days']),
                          stat(
                            'Check-ins, last 30 days',
                            g['check_ins_30_days'],
                          ),
                          stat('Last login', _when(g['last_login'])),
                          stat('Last check-in', _when(g['last_check_in'])),
                          stat(
                            'Times the vendor entered',
                            g['support_accesses'],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Plan and subscription',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: g['plan_tier'],
                            decoration: const InputDecoration(
                              labelText: 'Plan',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              for (final e in _tiers.entries)
                                DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                            ],
                            onChanged: (v) => _run(
                              () => PlatformService.patchGym(widget.gymId, {
                                'plan_tier': v,
                              }),
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: g['subscription_status'],
                            decoration: const InputDecoration(
                              labelText: 'Subscription',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              for (final s in const [
                                'trial',
                                'active',
                                'past_due',
                                'cancelled',
                              ])
                                DropdownMenuItem(value: s, child: Text(s)),
                            ],
                            onChanged: (v) => _run(
                              () => PlatformService.patchGym(widget.gymId, {
                                'subscription_status': v,
                              }),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'A plan change takes effect the next time the gym owner signs in.',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (suspended)
                    Card(
                      color: AppColors.dangerLight,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          'Suspended: ${g['suspended_reason'] ?? ''}',
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: _brand,
                    onPressed: () => _enter(g),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Enter gym (read-only, 30 min)'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: suspended
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                    onPressed: () async {
                      final reason = await _askReason(
                        context,
                        suspended
                            ? 'Resume ${g['name']}'
                            : 'Suspend ${g['name']}',
                        suspended
                            ? 'Why is it being restored?'
                            : 'Reason (shown to the gym at sign-in)',
                      );
                      if (reason == null) return;
                      _run(
                        () => suspended
                            ? PlatformService.resume(widget.gymId, reason)
                            : PlatformService.suspend(widget.gymId, reason),
                      );
                    },
                    icon: Icon(
                      suspended
                          ? Icons.play_circle_outline
                          : Icons.pause_circle_outline,
                    ),
                    label: Text(
                      suspended
                          ? 'Resume gym'
                          : 'Suspend gym (nothing is deleted)',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Activity log ─────────────────────────────────────────────────────────────

class _ActivityTab extends StatelessWidget {
  const _ActivityTab();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: PlatformService.accessLog(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text(_err(snap.error!)));
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final acc = (snap.data!['support_access'] as List?) ?? [];
        final act = (snap.data!['actions'] as List?) ?? [];
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Text(
              'Support access (entered a gym)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (acc.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('None yet.'),
              ),
            for (final a in acc)
              ListTile(
                dense: true,
                leading: const Icon(Icons.visibility_outlined),
                title: Text('${a['admin_name']} → ${a['gym_name']}'),
                subtitle: Text('${_when(a['started_at'])} · ${a['reason']}'),
              ),
            const Divider(height: 28),
            const Text(
              'Actions',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final a in act)
              ListTile(
                dense: true,
                leading: const Icon(Icons.history),
                title: Text(
                  '${a['admin_name']}: ${a['action']}${a['gym_name'] != null ? ' · ${a['gym_name']}' : ''}',
                ),
                subtitle: Text(
                  '${_when(a['created_at'])}${(a['detail'] ?? '').toString().isEmpty ? '' : ' · ${a['detail']}'}',
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'This log is insert-only. Nobody — including platform admins — can edit or delete it.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}

// ── Admins ───────────────────────────────────────────────────────────────────

class _AdminsTab extends StatefulWidget {
  const _AdminsTab();
  @override
  State<_AdminsTab> createState() => _AdminsTabState();
}

class _AdminsTabState extends State<_AdminsTab> {
  late Future<List<Map<String, dynamic>>> _f = PlatformService.admins();
  void _reload() => setState(() => _f = PlatformService.admins());

  Future<void> _showPassword(String who, String pw) => showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('One-time password for $who'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            pw,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            'Shown once. They sign in with it and must set up two-factor before anything else works.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
      ],
    ),
  );

  Future<void> _add() async {
    final email = TextEditingController();
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New platform admin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: _brand,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await PlatformService.createAdmin(
        email.text.trim(),
        name.text.trim(),
      );
      _reload();
      if (mounted)
        await _showPassword(name.text.trim(), r['temporary_password']);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_err(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = PlatformService.admin?['id'];
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('New admin'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(_err(snap.error!)));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final admins = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              if (admins.length < 2)
                Card(
                  color: AppColors.warningLight,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Only one platform admin. Create a second now: if the only admin loses their phone and recovery codes, nobody can reach this console again.',
                    ),
                  ),
                ),
              for (final a in admins)
                Card(
                  child: ListTile(
                    title: Text('${a['name']}${a['id'] == me ? ' (you)' : ''}'),
                    subtitle: Text(
                      '${a['email']} · ${a['enrolled'] == true ? 'two-factor on' : 'not enrolled yet'}',
                    ),
                    trailing: a['id'] == me
                        ? null
                        : TextButton(
                            onPressed: () async {
                              final sure = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text('Reset ${a['name']}?'),
                                  content: const Text(
                                    'Clears their two-factor and recovery codes and issues a new one-time password. Logged.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      style: _brand,
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Reset'),
                                    ),
                                  ],
                                ),
                              );
                              if (sure != true) return;
                              try {
                                final pw = await PlatformService.resetAdmin(
                                  a['id'],
                                );
                                _reload();
                                if (mounted) await _showPassword(a['name'], pw);
                              } catch (e) {
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(_err(e))),
                                  );
                              }
                            },
                            child: const Text('Reset'),
                          ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
