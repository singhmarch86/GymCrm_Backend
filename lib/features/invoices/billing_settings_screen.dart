import 'package:flutter/material.dart';

import '../../models/invoice.dart';
import '../../services/api_response.dart';
import '../../services/invoice_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_spacing.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_state.dart';
import '../lifecycle/lifecycle_shared.dart';

/// Per-gym invoicing configuration: the identity printed on invoices, the tax
/// basis, and the number series prefix.
///
/// This is onboarding, not admin trivia — a gym cannot issue a compliant
/// invoice until its GSTIN and legal name are set, and the tax basis decides
/// every total the gym will ever produce.
class BillingSettingsScreen extends StatefulWidget {
  const BillingSettingsScreen({super.key});

  @override
  State<BillingSettingsScreen> createState() => _BillingSettingsScreenState();
}

class _BillingSettingsScreenState extends State<BillingSettingsScreen> {
  final _service = InvoiceService();
  final _legalNameController = TextEditingController();
  final _gstinController = TextEditingController();
  final _addressController = TextEditingController();
  final _stateController = TextEditingController();
  final _prefixController = TextEditingController();
  final _taxRateController = TextEditingController();

  bool _pricesIncludeTax = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _legalNameController.dispose();
    _gstinController.dispose();
    _addressController.dispose();
    _stateController.dispose();
    _prefixController.dispose();
    _taxRateController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await _service.getSettings();
      if (!mounted) return;
      setState(() {
        _apply(s);
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

  void _apply(BillingSettings s) {
    _legalNameController.text = s.legalName ?? '';
    _gstinController.text = s.gstin ?? '';
    _addressController.text = s.addressLine ?? '';
    _stateController.text = s.stateName ?? '';
    _prefixController.text = s.invoicePrefix;
    _taxRateController.text = s.defaultTaxRate.toStringAsFixed(
        s.defaultTaxRate.truncateToDouble() == s.defaultTaxRate ? 0 : 2);
    _pricesIncludeTax = s.pricesIncludeTax;
  }

  Future<void> _save() async {
    final rate = double.tryParse(_taxRateController.text.trim());
    if (rate == null || rate < 0 || rate > 100) {
      setState(() => _error = 'Tax rate must be a number between 0 and 100');
      return;
    }
    if (_prefixController.text.trim().isEmpty) {
      setState(() => _error = 'Invoice prefix cannot be empty');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _saved = null;
    });
    try {
      final s = await _service.updateSettings(
        legalName: _legalNameController.text.trim(),
        gstin: _gstinController.text.trim(),
        addressLine: _addressController.text.trim(),
        stateName: _stateController.text.trim(),
        invoicePrefix: _prefixController.text.trim(),
        defaultTaxRate: rate,
        pricesIncludeTax: _pricesIncludeTax,
      );
      if (!mounted) return;
      setState(() {
        _apply(s);
        _saving = false;
        _saved = 'Saved. New invoices will use these settings.';
      });
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Billing settings')),
      body: _loading
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  AppSpacing.gapMd,
                ],
                if (_saved != null) ...[
                  LifecycleNotice(tone: LifecycleTone.positive, text: _saved!),
                  AppSpacing.gapMd,
                ],

                const Text('Your business',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                AppSpacing.gapXs,
                const Text('Printed on every invoice you issue.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                AppSpacing.gapMd,

                const LifecycleFieldLabel('Legal business name'),
                AppSpacing.gapXs,
                TextField(
                  controller: _legalNameController,
                  autofillHints: const [],
                  decoration: const InputDecoration(hintText: 'e.g. FitZone Gym Pvt Ltd'),
                ),
                AppSpacing.gapLg,

                const LifecycleFieldLabel('GSTIN'),
                AppSpacing.gapXs,
                TextField(
                  controller: _gstinController,
                  autofillHints: const [],
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'e.g. 03ABCDE1234F1Z5'),
                ),
                AppSpacing.gapXs,
                const Text('Leave blank if your gym is not GST-registered.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                AppSpacing.gapLg,

                const LifecycleFieldLabel('Address'),
                AppSpacing.gapXs,
                TextField(controller: _addressController, autofillHints: const [], maxLines: 2),
                AppSpacing.gapLg,

                const LifecycleFieldLabel('State (place of supply)'),
                AppSpacing.gapXs,
                TextField(
                  controller: _stateController,
                  autofillHints: const [],
                  decoration: const InputDecoration(hintText: 'e.g. Punjab'),
                ),

                AppSpacing.gapXxl,
                const Text('Tax', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                AppSpacing.gapMd,

                const LifecycleFieldLabel('GST rate (%)'),
                AppSpacing.gapXs,
                TextField(
                  controller: _taxRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofillHints: const [],
                ),
                AppSpacing.gapXs,
                const Text('18% is standard for gym and fitness services. Set 0 if you are not registered.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                AppSpacing.gapLg,

                const LifecycleFieldLabel('How your prices are quoted'),
                AppSpacing.gapXs,
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Tax included')),
                    ButtonSegment(value: false, label: Text('Tax added on top')),
                  ],
                  selected: {_pricesIncludeTax},
                  onSelectionChanged: (s) => setState(() => _pricesIncludeTax = s.first),
                ),
                AppSpacing.gapSm,
                // Worked example, because this is the setting most likely to be
                // chosen wrongly and the consequence is every total in the system.
                LifecycleNotice(
                  tone: _pricesIncludeTax ? LifecycleTone.info : LifecycleTone.warning,
                  text: _pricesIncludeTax
                      ? 'A ₹12,000 plan means the member pays ₹12,000. The tax is calculated '
                          'out of that (₹10,169.49 + ₹1,830.51 GST). This matches how most gyms quote.'
                      : 'A ₹12,000 plan means the member pays ₹14,160 — tax is added on top. '
                          'Choose this only if you quote pre-tax prices, typically for corporate clients. '
                          'If members pay the advertised ₹12,000, invoices will show a balance still owing.',
                ),

                AppSpacing.gapXxl,
                const Text('Invoice numbering',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                AppSpacing.gapMd,

                const LifecycleFieldLabel('Prefix'),
                AppSpacing.gapXs,
                TextField(
                  controller: _prefixController,
                  autofillHints: const [],
                  decoration: const InputDecoration(hintText: 'e.g. INV'),
                ),
                AppSpacing.gapXs,
                Text(
                  'Invoices will be numbered ${_prefixController.text.trim().isEmpty ? 'INV' : _prefixController.text.trim()}/2026-27/0001, '
                  'restarting each financial year. Numbers already issued never change.',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                ),

                AppSpacing.gapXxl,
                AppButton(text: 'Save settings', loading: _saving, onPressed: _saving ? null : _save),
                AppSpacing.gapMd,
                const LifecycleNotice(
                  tone: LifecycleTone.info,
                  text: 'Changing these affects invoices issued from now on. '
                      'Invoices already issued keep the details they were issued with.',
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
