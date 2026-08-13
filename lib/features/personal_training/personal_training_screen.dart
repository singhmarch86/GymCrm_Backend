import 'package:flutter/material.dart';

import '../../models/pt_package.dart';
import '../../models/trainer.dart';
import '../../services/api_response.dart';
import '../../services/pt_service.dart';
import '../../services/trainer_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/status_chip.dart';
import '../invoices/quick_invoice.dart';
import '../lifecycle/lifecycle_shared.dart' show formatDate, formatRupees;
import 'book_appointment_dialog.dart';
import 'sell_package_dialog.dart';

/// Personal training: packages sold to members and the 1:1 appointments
/// booked against them. See FR-03-trainers-pt-appointments.md — packages are
/// session-credit counters, and only completing an appointment consumes one.
class PersonalTrainingScreen extends StatefulWidget {
  const PersonalTrainingScreen({super.key});

  @override
  State<PersonalTrainingScreen> createState() => _PersonalTrainingScreenState();
}

class _PersonalTrainingScreenState extends State<PersonalTrainingScreen> {
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
        length: 2,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Personal Training'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Packages'),
                Tab(text: 'Appointments'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _PackagesTab(onChanged: _markChanged),
              _AppointmentsTab(onChanged: _markChanged),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Packages ─────────────────────────────────────────────────────────────────

class _PackagesTab extends StatefulWidget {
  final VoidCallback onChanged;
  const _PackagesTab({required this.onChanged});

  @override
  State<_PackagesTab> createState() => _PackagesTabState();
}

class _PackagesTabState extends State<_PackagesTab> {
  final _service = PtService();
  final _trainerService = TrainerService();
  List<PtPackage> _packages = [];
  List<Trainer> _trainers = [];
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
        _service.getPackages(),
        _trainerService.getTrainers(),
      ]);
      if (!mounted) return;
      setState(() {
        _packages = results[0] as List<PtPackage>;
        _trainers = (results[1] as List<Trainer>)
            .where((t) => t.status == 'active')
            .toList();
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

  Future<void> _sell() async {
    if (_trainers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an active trainer first.')),
      );
      return;
    }
    final created = await showSellPackageDialog(context, trainers: _trainers);
    if (created != null) {
      widget.onChanged();
      _load();
    }
  }

  Future<void> _cancelPackage(PtPackage p) async {
    try {
      await _service.updatePackageStatus(p.id, 'cancelled');
      widget.onChanged();
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Selling a package is a sale, so it needs to be invoiceable from here —
  /// staff shouldn't have to go to the Invoices screen and retype what they
  /// just sold.
  Future<void> _invoice(PtPackage p) async {
    final created = await QuickInvoice.createAndOpen(
      context,
      memberId: p.memberId,
      description:
          '${p.packageName} — ${p.totalSessions} PT sessions with ${p.trainerName}',
      amountInPaise: p.amountInPaise,
      itemType: 'pt_package',
      referenceId: p.id,
    );
    if (created) {
      widget.onChanged();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sell,
        icon: const Icon(Icons.add),
        label: const Text('Sell package'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
          ? ErrorBanner(message: _error!, onRetry: _load)
          : _packages.isEmpty
          ? const EmptyStateView(
              icon: Icons.fitness_center_rounded,
              title: 'No PT packages yet',
              body: 'Sell a session package to a member to get started.',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: _packages.length,
                separatorBuilder: (_, __) => AppSpacing.gapSm,
                itemBuilder: (_, i) => _PackageCard(
                  package: _packages[i],
                  onInvoice: () => _invoice(_packages[i]),
                  onCancel: _packages[i].status == 'active'
                      ? () => _cancelPackage(_packages[i])
                      : null,
                ),
              ),
            ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final PtPackage package;
  final VoidCallback onInvoice;
  final VoidCallback? onCancel;
  const _PackageCard({
    required this.package,
    required this.onInvoice,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${package.memberName} · ${package.packageName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              StatusChip(status: package.status),
            ],
          ),
          AppSpacing.gapXs,
          Text(
            'with ${package.trainerName} · ${package.sessionsUsed}/${package.totalSessions} used · '
            '${formatRupees(package.amountInRupees)}'
            '${package.expiryDate != null ? ' · expires ${package.expiryDate!.substring(0, 10)}' : ''}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          AppSpacing.gapSm,
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onCancel != null)
                TextButton(
                  onPressed: onCancel,
                  child: const Text('Cancel package'),
                ),
              TextButton.icon(
                onPressed: onInvoice,
                icon: const Icon(Icons.receipt_long_rounded, size: 16),
                label: const Text('Invoice'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Appointments ─────────────────────────────────────────────────────────────

class _AppointmentsTab extends StatefulWidget {
  final VoidCallback onChanged;
  const _AppointmentsTab({required this.onChanged});

  @override
  State<_AppointmentsTab> createState() => _AppointmentsTabState();
}

class _AppointmentsTabState extends State<_AppointmentsTab> {
  final _service = PtService();
  List<PtAppointment> _appointments = [];
  List<PtPackage> _activePackages = [];
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
      final results = await Future.wait([
        _service.getAppointments(
          from: from,
          to: from.add(const Duration(days: 14)),
        ),
        _service.getPackages(),
      ]);
      if (!mounted) return;
      setState(() {
        _appointments = results[0] as List<PtAppointment>;
        _activePackages = (results[1] as List<PtPackage>)
            .where((p) => p.status == 'active')
            .toList();
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

  Future<void> _book() async {
    if (_activePackages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sell an active PT package first.')),
      );
      return;
    }
    final booked = await showBookAppointmentDialog(
      context,
      activePackages: _activePackages,
    );
    if (booked != null) {
      widget.onChanged();
      _load();
    }
  }

  Future<void> _setOutcome(PtAppointment a, String status) async {
    try {
      await _service.setOutcome(a.id, status);
      widget.onChanged();
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openOutcomeSheet(PtAppointment a) async {
    if (a.status != 'scheduled') return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.check_circle_outline,
                color: AppColors.success,
              ),
              title: const Text('Completed'),
              subtitle: const Text('Consumes one session credit'),
              onTap: () => Navigator.pop(context, 'completed'),
            ),
            ListTile(
              leading: const Icon(
                Icons.person_off_outlined,
                color: AppColors.danger,
              ),
              title: const Text('No-show'),
              onTap: () => Navigator.pop(context, 'no_show'),
            ),
            ListTile(
              leading: const Icon(Icons.block, color: AppColors.textSecondary),
              title: const Text('Cancelled'),
              onTap: () => Navigator.pop(context, 'cancelled'),
            ),
          ],
        ),
      ),
    );
    if (choice != null) _setOutcome(a, choice);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _book,
        icon: const Icon(Icons.add),
        label: const Text('Book appointment'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
          ? ErrorBanner(message: _error!, onRetry: _load)
          : _appointments.isEmpty
          ? const EmptyStateView(
              icon: Icons.event_available,
              title: 'Nothing booked',
              body: 'Book a 1:1 session against an active PT package.',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: _appointments.length,
                separatorBuilder: (_, __) => AppSpacing.gapSm,
                itemBuilder: (_, i) => _AppointmentCard(
                  appointment: _appointments[i],
                  onTap: () => _openOutcomeSheet(_appointments[i]),
                ),
              ),
            ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final PtAppointment appointment;
  final VoidCallback onTap;
  const _AppointmentCard({required this.appointment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dt = appointment.scheduledAtDate.toLocal();
    return InkWell(
      onTap: appointment.status == 'scheduled' ? onTap : null,
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
                    appointment.memberName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatDate(dt)} · ${TimeOfDay.fromDateTime(dt).format(context)} · '
                    '${appointment.durationMinutes} min · ${appointment.trainerName}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            StatusChip(status: appointment.status),
          ],
        ),
      ),
    );
  }
}
