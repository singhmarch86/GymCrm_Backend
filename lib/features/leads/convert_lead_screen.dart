import 'package:flutter/material.dart';

import '../../models/lead.dart';
import '../../models/plan.dart';
import '../../services/api_response.dart';
import '../../services/lead_service.dart';
import '../../services/plan_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/validators.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_spacing.dart';

/// Lead → Member conversion screen.
///
/// Pre-fills contact info from the lead so the gym owner doesn't re-enter
/// anything they already captured. The only new inputs are plan, amount,
/// and payment mode — the minimum needed to complete the financial transaction.
///
/// One tap runs a single atomic backend transaction:
///   1. Create Member
///   2. Create Payment (status = paid)
///   3. Create Renewal linked to that payment
///   4. Update Member expiry
///   5. Set lead.converted_member_id + lead.status = joined
class ConvertLeadScreen extends StatefulWidget {
  final Lead lead;

  const ConvertLeadScreen({super.key, required this.lead});

  @override
  State<ConvertLeadScreen> createState() => _ConvertLeadScreenState();
}

class _ConvertLeadScreenState extends State<ConvertLeadScreen> {
  final _formKey = GlobalKey<FormState>();

  // Pre-filled from lead — editable
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _amountController;
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  List<Plan> _plans = [];
  bool _loadingPlans = true;
  bool _saving = false;

  int? _selectedPlanId;
  String _paymentMode = 'cash';
  String? _error;

  static const _modes = [
    ('cash',          'Cash'),
    ('upi',           'UPI'),
    ('credit_card',   'Credit Card'),
    ('debit_card',    'Debit Card'),
    ('bank_transfer', 'Bank Transfer'),
  ];

  @override
  void initState() {
    super.initState();

    // Split name — best effort: first word = first name, rest = last name
    final parts = widget.lead.name.trim().split(' ');
    final firstName = parts.isNotEmpty ? parts.first : widget.lead.name;
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    _firstNameController = TextEditingController(text: firstName);
    _lastNameController  = TextEditingController(text: lastName);
    _phoneController     = TextEditingController(text: widget.lead.phone);
    _amountController    = TextEditingController();

    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      final plans = await PlanService().getActivePlans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loadingPlans = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPlans = false);
    }
  }

  void _onPlanChanged(int? id) {
    setState(() {
      _selectedPlanId = id;
      final match = _plans.where((p) => p.id == id);
      if (match.isNotEmpty) {
        _amountController.text =
            match.first.priceInRupees.toStringAsFixed(0);
      }
    });
  }

  Future<void> _convert() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text.trim());
    final firstName = _firstNameController.text.trim();
    final phone = _phoneController.text.trim();

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final result = await LeadService().convertToMember(
        widget.lead.id,
        {
          'first_name':      firstName,
          'last_name':       _lastNameController.text.trim(),
          'phone':           phone,
          'plan_id':         _selectedPlanId,
          'amount_in_paise': (amount * 100).round(),
          'payment_mode':    _paymentMode,
          if (_referenceController.text.trim().isNotEmpty)
            'reference_number': _referenceController.text.trim(),
          if (_notesController.text.trim().isNotEmpty)
            'notes': _notesController.text.trim(),
        },
      );

      if (!mounted) return;

      final memberId = result['member_id'] as int? ?? 0;
      Navigator.pop(context, memberId); // return member ID to caller

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is ApiException ? e.message : "Couldn't convert this lead. Please try again.";
      });
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Convert to Member')),
      body: Form(
        key: _formKey,
        child: ListView(
        padding: AppSpacing.screenPadding,
        children: [

          // ── Lead origin banner ─────────────────────────────────────────
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_add_rounded,
                    color: Colors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Converting: ${widget.lead.name}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'Source: ${widget.lead.sourceLabel}'
                        '${widget.lead.goalLabel != null ? ' · ${widget.lead.goalLabel}' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          AppSpacing.gapXl,

          // ── Contact — pre-filled, editable ────────────────────────────
          const Text(
            'Contact Information',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          AppSpacing.gapMd,

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _firstNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'First Name *'),
                  validator: (v) => Validators.required(v, 'First name'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _lastNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Last Name'),
                ),
              ),
            ],
          ),
          AppSpacing.gapMd,

          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Phone *',
              prefixIcon: Icon(Icons.phone_rounded),
            ),
            validator: Validators.phone,
          ),

          AppSpacing.gapXl,

          // ── Membership plan ────────────────────────────────────────────
          const Text(
            'Membership',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          AppSpacing.gapMd,

          _loadingPlans
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              : DropdownButtonFormField<int>(
                  initialValue: _selectedPlanId,
                  decoration: const InputDecoration(
                    labelText: 'Plan *',
                    prefixIcon: Icon(Icons.workspace_premium_rounded),
                  ),
                  items: _plans
                      .map((p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              '${p.name}  ·  ₹${p.priceInRupees.toStringAsFixed(0)}',
                            ),
                          ))
                      .toList(),
                  onChanged: _onPlanChanged,
                  validator: (v) => v == null ? 'Please select a plan' : null,
                ),

          AppSpacing.gapMd,

          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Amount (₹) *',
              prefixIcon: Icon(Icons.currency_rupee_rounded),
            ),
            validator: (v) => Validators.positiveNumber(v, 'Amount'),
          ),

          AppSpacing.gapXl,

          // ── Payment ───────────────────────────────────────────────────
          const Text(
            'Payment',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          AppSpacing.gapMd,

          DropdownButtonFormField<String>(
            initialValue: _paymentMode,
            decoration: const InputDecoration(
              labelText: 'Payment Mode *',
              prefixIcon: Icon(Icons.payment_rounded),
            ),
            items: _modes
                .map((m) => DropdownMenuItem(
                      value: m.$1,
                      child: Text(m.$2),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _paymentMode = v);
            },
          ),
          AppSpacing.gapMd,

          TextFormField(
            controller: _referenceController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Reference Number (optional)',
              hintText: 'UPI / bank transaction ID',
            ),
          ),
          AppSpacing.gapMd,

          TextFormField(
            controller: _notesController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
            ),
          ),

          if (_error != null) ...[
            AppSpacing.gapMd,
            Text(
              _error!,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 13,
              ),
            ),
          ],

          AppSpacing.gapXl,

          // ── Summary of what will happen ────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This will:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                _bullet('Create a Member profile'),
                _bullet('Record the payment'),
                _bullet('Create a Renewal and set expiry date'),
                _bullet('Mark this lead as Joined'),
              ],
            ),
          ),

          AppSpacing.gapXl,

          AppButton(
            text: 'Convert to Member',
            icon: Icons.how_to_reg_rounded,
            loading: _saving,
            onPressed: _convert,
          ),

          AppSpacing.gapXxl,
        ],
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 14,
            color: AppColors.success,
          ),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
