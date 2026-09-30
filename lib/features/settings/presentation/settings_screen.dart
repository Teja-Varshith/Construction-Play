import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/config_models.dart';
import '../../../core/config/config_repository.dart';
import '../../../core/widgets/common.dart';
import '../../demo/demo_data_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    Widget tile(String title, String subtitle, String path, IconData icon) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go(path),
        );

    return PageScaffold(
      title: 'Settings',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          'Change the words and lists the app uses without waiting for a new version.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Card(
          child: tile('Company', config.company.name, '/settings/company', Icons.business_outlined),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Lists',
          child: Column(children: [
            for (final l in ConfigList.values)
              tile(l.title, '${config.activeOf(l).length} in use · ${l.description}', '/settings/lists/${l.name}',
                  Icons.list_alt_outlined),
            tile('Phase templates', '${config.phaseTemplates.where((t) => !t.archived).length} template(s) · standard phases for new projects',
                '/settings/phase-templates', Icons.view_timeline_outlined),
          ]),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Extra fields',
          subtitle: 'Add your own fields to records, such as RERA number or plot area.',
          child: Column(children: [
            for (final e in FieldEntity.values)
              tile(e.title, '${config.activeFieldsFor(e).length} extra field(s)', '/settings/fields/${e.name}',
                  Icons.dashboard_customize_outlined),
          ]),
        ),
        const SizedBox(height: 16),
        const DemoDataCard(),
      ]),
    );
  }
}
