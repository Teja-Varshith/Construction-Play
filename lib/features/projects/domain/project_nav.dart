/// The tabs of the project screen, in display order. [slug] is what appears in
/// the URL (`/projects/:id?tab=reports`).
enum ProjectTab {
  overview('overview', 'Insight'),
  reports('reports', 'Reports'),
  timeline('timeline', 'Timeline'),
  team('team', 'Team'),
  daily('daily', 'Daily progress'),
  materials('materials', 'Materials'),
  issues('issues', 'Issues'),
  documents('documents', 'Documents & photos'),
  money('money', 'Money'),
  info('info', 'Info'),
  activity('activity', 'Activity');

  const ProjectTab(this.slug, this.label);
  final String slug;
  final String label;

  static ProjectTab fromSlug(String? slug) =>
      ProjectTab.values.firstWhere((t) => t.slug == slug, orElse: () => ProjectTab.overview);
}

/// Where to go to investigate something: a tab, plus what to focus on in it.
///
/// Focus values each tab understands:
/// - timeline: `phase:<phaseId>`
/// - daily: `missing` (days with no report), `output` (output vs target)
/// - materials: `pending`, `late`, `low` (stock), `indent:<id>`, `phase:<phaseId>`
/// - issues: `urgent` (open high/critical), `open`, `issue:<issueId>`, `phase:<phaseId>`
/// - money: `pending` (awaiting approval), `payables`, `phase:<phaseId>`, `overspend`
/// - info: `holds`
class ProjectLink {
  const ProjectLink(this.tab, [this.focus]);

  final ProjectTab tab;
  final String? focus;

  static const overview = ProjectLink(ProjectTab.overview);

  /// The id after `prefix:` in [focus], e.g. the phase id in `phase:abc`.
  String? focusId(String prefix) =>
      focus != null && focus!.startsWith('$prefix:') ? focus!.substring(prefix.length + 1) : null;

  String path(String projectId) {
    final query = {
      if (tab != ProjectTab.overview) 'tab': tab.slug,
      'focus': ?focus,
    };
    return Uri(path: '/projects/$projectId', queryParameters: query.isEmpty ? null : query).toString();
  }
}
