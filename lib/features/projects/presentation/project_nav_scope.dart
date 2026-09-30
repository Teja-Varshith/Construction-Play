import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/project_nav.dart';

/// Shared by every tab of one project screen: which tab/focus was last asked
/// for, and a way to ask for another. [seq] increases on every request, so a
/// tab can tell a fresh "investigate this" from a rebuild.
class ProjectNavScope extends InheritedWidget {
  const ProjectNavScope({
    super.key,
    required this.projectId,
    required this.current,
    required this.seq,
    required this.onOpen,
    required super.child,
  });

  final String projectId;
  final ProjectLink current;
  final int seq;
  final void Function(ProjectLink link) onOpen;

  static ProjectNavScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProjectNavScope>();

  /// The focus requested for [tab], or null when the request was for another tab.
  String? focusFor(ProjectTab tab) => current.tab == tab ? current.focus : null;

  @override
  bool updateShouldNotify(ProjectNavScope old) => seq != old.seq || projectId != old.projectId;
}

/// Opens [link] on [projectId]: switches tab in place when already on that
/// project's screen, otherwise navigates there (keeping Back history).
void openProjectLink(BuildContext context, String projectId, ProjectLink link) {
  final scope = ProjectNavScope.maybeOf(context);
  if (scope != null && scope.projectId == projectId) {
    scope.onOpen(link);
  } else {
    context.push(link.path(projectId));
  }
}

/// Outlines [child] when it is the thing being investigated, and scrolls it
/// into view once per request.
class FocusHighlight extends StatefulWidget {
  const FocusHighlight({
    super.key,
    required this.active,
    required this.child,
    this.seq = 0,
    this.radius = 12,
  });

  final bool active;
  final int seq;
  final double radius;
  final Widget child;

  @override
  State<FocusHighlight> createState() => _FocusHighlightState();
}

class _FocusHighlightState extends State<FocusHighlight> {
  int? _scrolledFor;

  @override
  void initState() {
    super.initState();
    _maybeScroll();
  }

  @override
  void didUpdateWidget(covariant FocusHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeScroll();
  }

  void _maybeScroll() {
    if (!widget.active || _scrolledFor == widget.seq) return;
    _scrolledFor = widget.seq;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: EdgeInsets.all(widget.active ? 3 : 0),
      decoration: BoxDecoration(
        color: widget.active ? primary.withValues(alpha: 0.03) : Colors.transparent,
        borderRadius: BorderRadius.circular(widget.radius + 3),
        border: Border.all(color: widget.active ? primary.withValues(alpha: 0.7) : Colors.transparent, width: 2),
        boxShadow: widget.active ? appSoftShadow : const [],
      ),
      child: widget.child,
    );
  }
}
