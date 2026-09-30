import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/dynamic_form/dynamic_fields.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import 'settings_common.dart';

class CompanySettingsScreen extends StatelessWidget {
  const CompanySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => ConfigGate(
        title: 'Company',
        builder: (config) => _CompanyForm(config: config),
      );
}

class _CompanyForm extends ConsumerStatefulWidget {
  const _CompanyForm({required this.config});

  final AppConfig config;

  @override
  ConsumerState<_CompanyForm> createState() => _CompanyFormState();
}

class _CompanyFormState extends ConsumerState<_CompanyForm> {
  final _form = GlobalKey<FormState>();
  late CompanySettings _initial = widget.config.company;
  late int _rev = widget.config.revisions['company'] ?? 0;
  late final _name = TextEditingController(text: _initial.name);
  late int? _thresholdPaise = _initial.approvalThresholdPaise;
  late final _backdate = TextEditingController(text: '${_initial.dprBackdateDays}');
  int _formVersion = 0;
  bool _dirty = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _backdate.dispose();
    super.dispose();
  }

  void _reset(AppConfig config) {
    setState(() {
      _initial = config.company;
      _rev = config.revisions['company'] ?? 0;
      _name.text = _initial.name;
      _thresholdPaise = _initial.approvalThresholdPaise;
      _backdate.text = '${_initial.dprBackdateDays}';
      _formVersion++;
      _dirty = false;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final updated = CompanySettings(
      name: _name.text.trim(),
      utcOffsetMinutes: _initial.utcOffsetMinutes,
      currency: _initial.currency,
      approvalThresholdPaise: _thresholdPaise!,
      dprBackdateDays: int.parse(_backdate.text.trim()),
    );
    final ok = await runConfigSave(
      context,
      () => ref.read(configRepositoryProvider).saveCompany(updated, expectedRev: _rev, uid: ref.read(currentUserProvider).uid),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      setState(() {
        _initial = updated;
        _rev++;
        _dirty = false;
      });
    } else {
      final latest = ref.read(appConfigStreamProvider).value;
      if (latest != null) _reset(latest);
    }
  }

  @override
  Widget build(BuildContext context) {
    return UnsavedGuard(
      dirty: _dirty,
      child: PageScaffold(
        title: 'Company',
        maxWidth: 640,
        body: Form(
          key: _form,
          onChanged: () => setState(() => _dirty = true),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Company name'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the company name' : null,
                ),
                const SizedBox(height: 16),
                MoneyFormField(
                  key: ValueKey('threshold-$_formVersion'),
                  label: 'Expenses above this need the CEO\'s approval',
                  helperText: 'Smaller expenses are approved automatically but still visible.',
                  initialPaise: _thresholdPaise,
                  onChanged: (p) => _thresholdPaise = p,
                  validator: (p) => p == null ? 'Enter an amount' : (p < 0 ? 'Can\'t be negative' : null),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _backdate,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Daily reports can be entered up to this many days late',
                  ),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n < 0 || n > 60) return 'Enter a number from 0 to 60';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                const InputDecorator(
                  decoration: InputDecoration(labelText: 'Time zone and currency', enabled: false),
                  child: Text('India Standard Time (UTC+5:30) · Indian rupee (₹)'),
                ),
              ]),
            ),
            SaveBar(
              dirty: _dirty,
              busy: _busy,
              onSave: _save,
              onDiscard: () => _reset(ref.read(appConfigProvider)),
            ),
          ]),
        ),
      ),
    );
  }
}
