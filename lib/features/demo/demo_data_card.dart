import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/config_repository.dart';
import '../../core/widgets/common.dart';
import '../auth/data/session.dart';
import 'demo_accounts.dart';
import 'demo_seeder.dart';

/// Settings → Demo data. Loads or removes the demo portfolio.
class DemoDataCard extends ConsumerStatefulWidget {
  const DemoDataCard({super.key});

  @override
  ConsumerState<DemoDataCard> createState() => _DemoDataCardState();
}

class _DemoDataCardState extends ConsumerState<DemoDataCard> {
  bool _busy = false;
  String? _step;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Demo data',
    subtitle:
        'Six sample projects with phases, budgets, expenses, issues and daily reports, '
        'so the CEO dashboard can be tried before real projects are entered.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Loading also creates one demo login per role and shows one-tap demo sign-in on the login page. '
          'Removing demo data archives the demo projects and switches the demo logins off; nothing else is touched.',
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Demo logins · password $demoPassword', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final a in demoAccounts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: SelectableText('${a.role.label.padRight(11)}  ${a.email}'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('Load demo data'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _remove,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Remove demo data'),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          if (_step != null) ...[const SizedBox(height: 6), Text(_step!)],
        ],
      ],
    ),
  );

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _step = 'Starting…';
    });
    try {
      await ref.read(demoSeederProvider).seed(
        config: ref.read(appConfigProvider),
        admin: ref.read(currentUserProvider),
        onProgress: (step) {
          if (mounted) setState(() => _step = step);
        },
      );
      if (mounted) {
        showMessage(context, 'Demo portfolio loaded.');
        context.go('/projects');
      }
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (!await confirmAction(
      context,
      title: 'Remove demo data?',
      message: 'All demo projects will be archived.',
      confirmLabel: 'Remove',
      destructive: true,
    )) {
      return;
    }
    setState(() {
      _busy = true;
      _step = 'Archiving demo projects…';
    });
    try {
      final n = await ref.read(demoSeederProvider).removeDemoData(ref.read(currentUserProvider).uid);
      if (mounted) showMessage(context, n == 0 ? 'No demo data found.' : 'Removed $n demo projects.');
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
