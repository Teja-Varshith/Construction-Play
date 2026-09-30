import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_repository.dart';
import '../../../core/utils/work_day.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/session.dart';
import '../../projects/data/project_detail_repository.dart';
import '../../projects/domain/project.dart';
import '../data/inventory_repository.dart';
import '../domain/inventory.dart';
import 'material_form_dialog.dart';

/// Shows [error] without the "Bad state:" / "Invalid argument(s):" prefix.
String friendlyError(Object error) =>
    '$error'.replaceFirst(RegExp(r'^(Bad state|Invalid argument\(s\)): '), '');

/// Raise an indent on [project] from anywhere (Materials tab, My day). Uses
/// the stock already loaded for the project to suggest materials.
Future<void> raiseIndentFlow(
  BuildContext context,
  WidgetRef ref,
  Project project, {
  List<MaterialLine> prefill = const [],
  String? phaseId,
}) async {
  final summary = ref.read(projectInventoryProvider(project.id)).value;
  if (summary == null) {
    showMessage(context, 'Still loading this project\'s stock. Try again in a moment.');
    return;
  }
  final config = ref.read(appConfigProvider);
  final result = await showMaterialForm(
    context,
    kind: MaterialFormKind.indent,
    summary: summary,
    today: WorkDay.today(utcOffsetMinutes: config.company.utcOffsetMinutes),
    phases: ref.read(projectPhasesProvider(project.id)).value ?? const [],
    prefill: prefill,
    phaseId: phaseId,
  );
  if (result == null || !context.mounted) return;
  try {
    await ref.read(inventoryRepositoryProvider).raiseIndent(
      projectId: project.id,
      items: result.lines,
      neededBy: result.date,
      phaseId: result.phaseId,
      note: result.note,
      uid: ref.read(currentUserProvider).uid,
    );
    if (context.mounted) showMessage(context, 'Indent sent for approval');
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
  }
}
