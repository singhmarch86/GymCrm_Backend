import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../services/api_response.dart';
import '../../services/queue_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/member_picker.dart';

/// Record that a member owes money.
///
/// The gap this closes: every other way of entering a payment writes a *paid*
/// row. Until this existed the collections queue could only show dues that
/// some other process happened to create, so it looked emptier than reality —
/// and a gym that cannot raise a due cannot chase it.
Future<bool?> showRaiseDueSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _RaiseDueSheet(),
  );
}

class _RaiseDueSheet extends StatefulWidget {
  const _RaiseDueSheet();

  @override
  State<_RaiseDueSheet> createState() => _RaiseDueSheetState();
}

class _RaiseDueSheetState extends State<_RaiseDueSheet> {
  final _service = QueueService();
  final _amount = TextEditingController();
  final _notes = TextEditingController();

  Member? _member;

  /// No default. The due date decides which group the row lands in, and
  /// quietly assuming today would put somebody in "nobody has chased these"
  /// for a debt that is not due yet.
  DateTime? _due;

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _member != null &&
      _due != null &&
      (int.tryParse(_amount.text.trim()) ?? 0) > 0 &&
      !_saving;

  Future<void> _pickMember() async {
    final picked = await showMemberPicker(
      context,
      title: 'Who owes it?',
      subtitle: 'Search by name or phone',
      emptyHint: 'No matching member.',
    );
    if (picked != null && mounted) setState(() => _member = picked);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      // Backdating allowed: the common case is catching up on something that
      // was already owed last month.
      firstDate: DateTime(now.year - 2),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'When was it due?',
    );
    if (picked != null && mounted) setState(() => _due = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.raiseDue(
        memberId: _member!.id,
        amountInPaise: int.parse(_amount.text.trim()) * 100,
        dueDate: _due!,
        notes: _notes.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Raise a due',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  'Records that a member owes money. It does not take payment.',
                  style:
                      TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),

                const SizedBox(height: 16),
                _field(
                  label: 'Member',
                  value: _member == null
                      ? null
                      : '${_member!.firstName} ${_member!.lastName}'
                          '${_member!.phone.isEmpty ? '' : ' · ${_member!.phone}'}',
                  placeholder: 'Choose a member',
                  icon: Icons.person_search_rounded,
                  onTap: _saving ? null : _pickMember,
                ),

                const SizedBox(height: 10),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  enabled: !_saving,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Amount (₹)',
                    prefixText: '₹ ',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),

                const SizedBox(height: 10),
                _field(
                  label: 'Due date',
                  value: _due == null ? null : _formatDate(_due!),
                  placeholder: 'Choose a date',
                  icon: Icons.event_rounded,
                  onTap: _saving ? null : _pickDate,
                ),
                const SizedBox(height: 5),
                Text(
                  'Required. It decides where the due sits in the queue, so '
                  'guessing today would file it wrong.',
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),

                const SizedBox(height: 10),
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'What for? (optional)',
                    hintText: 'e.g. PT package balance',
                    hintStyle: TextStyle(
                        fontSize: 12.5, color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.danger)),
                ],

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canSave ? _save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Raise the due'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required String? value,
    required String placeholder,
    required IconData icon,
    required VoidCallback? onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey.shade600)),
                    const SizedBox(height: 1),
                    Text(
                      value ?? placeholder,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            value == null ? FontWeight.normal : FontWeight.w600,
                        color: value == null
                            ? Colors.grey.shade500
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: Colors.grey.shade400),
            ],
          ),
        ),
      );

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';
}
