import 'package:flutter/material.dart';

import '../../models/import_batch.dart';
import '../../services/api_response.dart';
import '../../services/import_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../lifecycle/lifecycle_shared.dart';

/// Import wizard. See docs/FR-05-data-import.md.
///
/// The design assumption is that the person doing this is nervous: they're
/// moving their business's records into software they don't yet trust. So the
/// wizard never writes anything until they've seen exactly what will happen,
/// and the preview leads with problems rather than burying them.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _changed = false;

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
            title: const Text('Import data'),
            bottom: const TabBar(
              tabs: [Tab(text: 'New import'), Tab(text: 'History')],
            ),
          ),
          body: TabBarView(
            children: [
              _NewImportTab(onImported: () => _changed = true),
              const _HistoryTab(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── New import ──────────────────────────────────────────────────────────────

enum _Step { paste, preview, done }

class _NewImportTab extends StatefulWidget {
  final VoidCallback onImported;
  const _NewImportTab({required this.onImported});

  @override
  State<_NewImportTab> createState() => _NewImportTabState();
}

class _NewImportTabState extends State<_NewImportTab> {
  final _service = ImportService();
  final _controller = TextEditingController();

  String _entity = 'members';
  String _policy = 'skip';
  _Step _step = _Step.paste;
  ImportBatch? _batch;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    try {
      final csv = await _service.template(_entity);
      if (!mounted) return;
      setState(() => _controller.text = csv);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _validate() async {
    final content = _controller.text.trim();
    if (content.isEmpty) {
      setState(() => _error = 'Paste your data first, or load the template to see the format.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final batch = await _service.validate(entityType: _entity, content: content);
      if (!mounted) return;
      setState(() {
        _batch = batch;
        _step = _Step.preview;
        _busy = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  Future<void> _commit() async {
    final batch = _batch;
    if (batch == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.commit(batch.id, duplicatePolicy: _policy);
      if (!mounted) return;
      setState(() {
        _batch = result;
        _step = _Step.done;
        _busy = false;
      });
      widget.onImported();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  Future<void> _discard() async {
    final batch = _batch;
    if (batch != null && !batch.isCommitted) {
      try {
        await _service.discard(batch.id);
      } on ApiException {
        // Discarding is best-effort: nothing was written either way.
      }
    }
    if (!mounted) return;
    setState(() {
      _batch = null;
      _step = _Step.paste;
      _controller.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          AppSpacing.gapMd,
        ],
        switch (_step) {
          _Step.paste => _pasteStep(),
          _Step.preview => _previewStep(),
          _Step.done => _doneStep(),
        },
      ],
    );
  }

  Widget _pasteStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LifecycleFieldLabel('What are you importing?'),
        AppSpacing.gapXs,
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'plans', label: Text('Plans')),
            ButtonSegment(value: 'members', label: Text('Members')),
            ButtonSegment(value: 'payments', label: Text('Payments')),
          ],
          selected: {_entity},
          onSelectionChanged: (s) => setState(() => _entity = s.first),
        ),
        AppSpacing.gapSm,
        // Order matters and isn't obvious: members reference plans, payments
        // reference members.
        const LifecycleNotice(
          tone: LifecycleTone.info,
          text: 'Import in this order: plans first, then members, then payments — '
              'members are matched to plans by name, and payments to members by phone.',
        ),
        AppSpacing.gapLg,

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const LifecycleFieldLabel('Paste your data'),
            TextButton.icon(
              onPressed: _loadTemplate,
              icon: const Icon(Icons.description_outlined, size: 16),
              label: const Text('Load example'),
            ),
          ],
        ),
        AppSpacing.gapXs,
        TextField(
          controller: _controller,
          maxLines: 12,
          autofillHints: const [],
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
          decoration: const InputDecoration(
            hintText: 'Paste straight from Excel or a CSV file, including the header row…',
          ),
        ),
        AppSpacing.gapSm,
        const LifecycleNotice(
          tone: LifecycleTone.info,
          text: 'Column names are matched loosely — "Mobile No", "phone" and "Contact Number" '
              'all work. Extra columns are ignored. Dates are read day-first (31/03/2027).',
        ),
        AppSpacing.gapLg,

        AppButton(
          text: 'Check my data',
          loading: _busy,
          onPressed: _busy ? null : _validate,
        ),
        AppSpacing.gapSm,
        const Center(
          child: Text(
            'Nothing is saved yet — you will see exactly what happens before anything changes.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _previewStep() {
    final b = _batch!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('What will happen',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        AppSpacing.gapSm,

        _CountsGrid(batch: b),
        AppSpacing.gapMd,

        if (b.validRows == 0 && b.duplicateRows == 0)
          const LifecycleNotice(
            tone: LifecycleTone.blocked,
            text: 'Nothing in this file can be imported. Fix the problems below and paste it again.',
          )
        else
          LifecycleNotice(
            tone: LifecycleTone.positive,
            text: '${b.validRows} new record${b.validRows == 1 ? '' : 's'} will be created.'
                '${b.invalidRows > 0 ? ' ${b.invalidRows} broken row${b.invalidRows == 1 ? '' : 's'} will be skipped.' : ''}',
          ),

        if (b.duplicateRows > 0) ...[
          AppSpacing.gapLg,
          const LifecycleFieldLabel('Records that already exist'),
          AppSpacing.gapXs,
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'skip', label: Text('Leave them alone')),
              ButtonSegment(value: 'update', label: Text('Update them')),
            ],
            selected: {_policy},
            onSelectionChanged: (s) => setState(() => _policy = s.first),
          ),
          AppSpacing.gapXs,
          Text(
            _policy == 'skip'
                ? '${b.duplicateRows} existing record${b.duplicateRows == 1 ? '' : 's'} will be left exactly as they are.'
                : '${b.duplicateRows} existing record${b.duplicateRows == 1 ? '' : 's'} will be overwritten with the values in your file. '
                    'Status and expiry are only changed if your file has those columns.',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],

        if (b.problems.isNotEmpty) ...[
          AppSpacing.gapLg,
          Text('Rows needing attention (${b.problems.length})',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          AppSpacing.gapXs,
          for (final row in b.problems.take(50)) _ProblemRow(row: row),
          if (b.problems.length > 50)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('…and ${b.problems.length - 50} more',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
        ],

        AppSpacing.gapXl,
        Row(
          children: [
            TextButton(onPressed: _busy ? null : _discard, child: const Text('Start over')),
            AppSpacing.gapMd,
            Expanded(
              child: AppButton(
                text: 'Import ${b.validRows + (_policy == 'update' ? b.duplicateRows : 0)} records',
                loading: _busy,
                onPressed: (_busy || !b.canCommit) ? null : _commit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _doneStep() {
    final b = _batch!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle_outline, size: 44, color: AppColors.success),
        AppSpacing.gapSm,
        const Text('Import complete', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        AppSpacing.gapMd,
        LifecycleOutcome(
          emphasisColor: AppColors.success,
          rows: [
            ('Created', '${b.importedRows}'),
            if (b.updatedRows > 0) ('Updated', '${b.updatedRows}'),
            ('Skipped', '${b.skippedRows}'),
            if (b.invalidRows > 0) ('Could not be read', '${b.invalidRows}'),
            ('Rows in your file', '${b.totalRows}'),
          ],
        ),
        AppSpacing.gapLg,
        AppButton(text: 'Import something else', onPressed: _discard),
      ],
    );
  }
}

class _CountsGrid extends StatelessWidget {
  final ImportBatch batch;
  const _CountsGrid({required this.batch});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Count(label: 'Rows read', value: batch.totalRows, color: AppColors.textSecondary),
        _Count(label: 'Ready to import', value: batch.validRows, color: AppColors.success),
        _Count(label: 'Already exist', value: batch.duplicateRows, color: AppColors.warning),
        _Count(label: 'Problems', value: batch.invalidRows, color: AppColors.danger),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _Count({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
          Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _ProblemRow extends StatelessWidget {
  final ImportRowResult row;
  const _ProblemRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final isDuplicate = row.status == 'duplicate';
    final color = isDuplicate ? AppColors.warning : AppColors.danger;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The line number is the point: it maps straight back to their file.
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('Line ${row.lineNumber}',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                if (row.errorMessage != null)
                  Text(row.errorMessage!,
                      style: TextStyle(fontSize: 12, color: color, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── History ─────────────────────────────────────────────────────────────────

class _HistoryTab extends StatefulWidget {
  const _HistoryTab();

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  final _service = ImportService();
  List<ImportBatch> _batches = [];
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
      final list = await _service.history();
      if (!mounted) return;
      setState(() {
        _batches = list;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _load);
    if (_batches.isEmpty) {
      return const EmptyStateView(
        icon: Icons.upload_file_outlined,
        title: 'No imports yet',
        body: 'Every import is kept here as a record of what was brought in, and when.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _batches.length,
        separatorBuilder: (_, __) => AppSpacing.gapSm,
        itemBuilder: (_, i) {
          final b = _batches[i];
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
                        '${b.entityType[0].toUpperCase()}${b.entityType.substring(1)}'
                        '${b.filename != null ? ' · ${b.filename}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                    Text(
                      b.isCommitted ? 'Imported' : (b.status == 'discarded' ? 'Discarded' : 'Not committed'),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: b.isCommitted ? AppColors.success : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                AppSpacing.gapXs,
                Text(
                  '${b.importedRows} created'
                  '${b.updatedRows > 0 ? ' · ${b.updatedRows} updated' : ''}'
                  '${b.skippedRows > 0 ? ' · ${b.skippedRows} skipped' : ''}'
                  ' · ${b.totalRows} rows read',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                if (b.createdAt.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    formatDate(DateTime.parse(b.createdAt).toLocal()),
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
