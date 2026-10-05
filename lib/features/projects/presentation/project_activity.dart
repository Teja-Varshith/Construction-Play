import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/widgets/common.dart';
import '../../users/data/user_repository.dart';
import '../../../core/widgets/art.dart';

final projectActivityProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>(
      (ref, id) => ref
          .watch(firestoreProvider)
          .collection('activity')
          .where('projectId', isEqualTo: id)
          .snapshots()
          .map((snapshot) {
            final items = snapshot.docs.map((d) => d.data()).toList();
            items.sort(
              (a, b) => (b['at']?.millisecondsSinceEpoch ?? 0).compareTo(
                a['at']?.millisecondsSinceEpoch ?? 0,
              ) as int,
            );
            return items;
          }),
    );

class ProjectActivity extends ConsumerWidget {
  const ProjectActivity({super.key, required this.projectId});
  final String projectId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(allUsersProvider).value ?? [];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: AsyncView(
        value: ref.watch(projectActivityProvider(projectId)),
        data: (items) => Column(
          children: [
            if (items.isEmpty)
              const MessageView(
                icon: Icons.history,
                art: Art.emptyBlueprint,
                title: 'No changes recorded yet',
              ),
            for (final item in items)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text('${item['summary'] ?? item['action']}'),
                subtitle: Text(
                  '${people.where((p) => p.uid == item['actorId']).firstOrNull?.name ?? 'Team member'} · ${item['at']?.toDate().toLocal().toString().split('.').first ?? 'Syncing'}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
