import 'package:flutter/material.dart';

import '../../models/class_models.dart';
import '../../services/api_response.dart';
import '../../services/classes_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/status_chip.dart';
import '../lifecycle/lifecycle_shared.dart' show formatDate;
import 'class_type_dialog.dart';
import 'schedule_dialog.dart';
import 'session_detail_screen.dart';

/// Top-level Classes screen — the dashboard quick-action entry point.
/// Three tabs: what's on this week, the recurring schedules behind it, and
/// the class types on offer. Each tab owns its own create action, since
/// they're independent objects (FR-02 §0.1) rather than steps in one flow.
class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  bool _changed = false;

  void _markChanged() => _changed = true;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Classes'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'This Week'),
                Tab(text: 'Schedules'),
                Tab(text: 'Class Types'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _SessionsTab(onChanged: _markChanged),
              _SchedulesTab(onChanged: _markChanged),
              _ClassTypesTab(onChanged: _markChanged),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── This Week ────────────────────────────────────────────────────────────────

class _SessionsTab extends StatefulWidget {
  final VoidCallback onChanged;
  const _SessionsTab({required this.onChanged});

  @override
  State<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<_SessionsTab> {
  final _service = ClassesService();
  List<ClassSession> _sessions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final today = DateTime.now();
      final from = DateTime(today.year, today.month, today.day);
      final sessions = await _service.getSessions(
        from: from,
        to: from.add(const Duration(days: 7)),
      );
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _openSession(int id) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SessionDetailScreen(sessionId: id)),
    );
    if (changed == true) {
      widget.onChanged();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _load);
    if (_sessions.isEmpty) {
      return const EmptyStateView(
        icon: Icons.event_busy,
        title: 'Nothing scheduled this week',
        body:
            'Create a schedule from the Schedules tab — sessions generate automatically.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sessions.length,
        separatorBuilder: (_, __) => AppSpacing.gapSm,
        itemBuilder: (_, i) {
          final s = _sessions[i];
          return _SessionCard(session: s, onTap: () => _openSession(s.id));
        },
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final ClassSession session;
  final VoidCallback onTap;

  const _SessionCard({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: session.isFull ? AppColors.warning : AppColors.success,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            AppSpacing.gapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.classTypeName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatDate(session.sessionDate)} · ${session.startTime.substring(0, 5)}'
                    '${session.trainerName != null ? ' · ${session.trainerName}' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusChip(status: session.status),
                const SizedBox(height: 4),
                Text(
                  '${session.bookedCount}/${session.capacity}'
                  '${session.waitlistCount > 0 ? ' · +${session.waitlistCount}' : ''}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Schedules ────────────────────────────────────────────────────────────────

class _SchedulesTab extends StatefulWidget {
  final VoidCallback onChanged;
  const _SchedulesTab({required this.onChanged});

  @override
  State<_SchedulesTab> createState() => _SchedulesTabState();
}

class _SchedulesTabState extends State<_SchedulesTab> {
  final _service = ClassesService();
  List<ClassSchedule> _schedules = [];
  List<ClassType> _classTypes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.getSchedules(),
        _service.getClassTypes(activeOnly: true),
      ]);
      if (!mounted) return;
      setState(() {
        _schedules = results[0] as List<ClassSchedule>;
        _classTypes = results[1] as List<ClassType>;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    if (_classTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a class type first.')),
      );
      return;
    }
    final created = await showCreateScheduleDialog(
      context,
      classTypes: _classTypes,
    );
    if (created != null) {
      widget.onChanged();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New schedule'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
          ? ErrorBanner(message: _error!, onRetry: _load)
          : _schedules.isEmpty
          ? const EmptyStateView(
              icon: Icons.repeat,
              title: 'No schedules yet',
              body:
                  'Create a recurring schedule — sessions are generated automatically.',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: _schedules.length,
                separatorBuilder: (_, __) => AppSpacing.gapSm,
                itemBuilder: (_, i) => _ScheduleCard(schedule: _schedules[i]),
              ),
            ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final ClassSchedule schedule;
  const _ScheduleCard({required this.schedule});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schedule.classTypeName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${schedule.dayName} · ${schedule.startTime.substring(0, 5)} · '
                  'cap ${schedule.capacity}'
                  '${schedule.trainerName != null ? ' · ${schedule.trainerName}' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (!schedule.isActive)
            const StatusChip(status: 'cancelled', label: 'Inactive'),
        ],
      ),
    );
  }
}

// ─── Class Types ──────────────────────────────────────────────────────────────

class _ClassTypesTab extends StatefulWidget {
  final VoidCallback onChanged;
  const _ClassTypesTab({required this.onChanged});

  @override
  State<_ClassTypesTab> createState() => _ClassTypesTabState();
}

class _ClassTypesTabState extends State<_ClassTypesTab> {
  final _service = ClassesService();
  List<ClassType> _classTypes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final types = await _service.getClassTypes();
      if (!mounted) return;
      setState(() {
        _classTypes = types;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final created = await showCreateClassTypeDialog(context);
    if (created != null) {
      widget.onChanged();
      _load();
    }
  }

  Future<void> _edit(ClassType classType) async {
    final updated = await showEditClassTypeDialog(context, classType);
    if (updated != null) {
      widget.onChanged();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New class type'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
          ? ErrorBanner(message: _error!, onRetry: _load)
          : _classTypes.isEmpty
          ? const EmptyStateView(
              icon: Icons.self_improvement,
              title: 'No class types yet',
              body: 'Add Yoga, Zumba, HIIT — whatever your gym offers.',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: _classTypes.length,
                separatorBuilder: (_, __) => AppSpacing.gapSm,
                itemBuilder: (_, i) => _ClassTypeCard(
                  classType: _classTypes[i],
                  onTap: () => _edit(_classTypes[i]),
                ),
              ),
            ),
    );
  }
}

class _ClassTypeCard extends StatelessWidget {
  final ClassType classType;
  final VoidCallback onTap;
  const _ClassTypeCard({required this.classType, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    classType.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${classType.durationMinutes} min · capacity ${classType.defaultCapacity}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (classType.description != null &&
                      classType.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      classType.description!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!classType.isActive) ...[
              const StatusChip(status: 'cancelled', label: 'Inactive'),
              const SizedBox(width: 8),
            ],
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
