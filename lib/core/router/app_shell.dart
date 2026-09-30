import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/session.dart';
import '../../features/finance/data/finance_repository.dart';
import '../../features/inventory/data/inventory_repository.dart';
import '../config/config_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_mark.dart';
import 'nav.dart';

/// Sidebar on wide screens (office computers), bottom bar on phones.
///
/// Inside a project the sidebar collapses to icons so the project's own
/// section list has room.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static final _projectPage = RegExp(r'^/projects/(?!new$|stage/)[^/]+$');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final items = navItemsFor(user.role);
    var index = items.indexWhere((i) => location == i.path || location.startsWith('${i.path}/'));
    if (index < 0) index = 0;
    final pending = user.isCeo || user.isAdmin
        ? (ref.watch(visiblePendingExpensesProvider).value?.length ?? 0) +
              (ref.watch(visiblePendingIndentsProvider).value?.length ?? 0)
        : 0;
    int badgeFor(NavItem item) => item.path == '/approvals' ? pending : 0;

    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) {
      final inProject = _projectPage.hasMatch(location);
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(
              items: items,
              index: index,
              expanded: width >= 1200 && !inProject,
              badgeFor: badgeFor,
            ),
            Expanded(child: child),
          ],
        ),
      );
    }

    // Phones: up to four destinations, the rest behind "More".
    final primary = items.where((i) => i.path != '/profile').take(3).toList();
    final more = items.where((i) => !primary.contains(i)).toList();
    final selected = primary.indexOf(items[index]);
    return Scaffold(
      body: child,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
        child: NavigationBar(
          selectedIndex: selected < 0 ? primary.length : selected,
          onDestinationSelected: (n) => n < primary.length
              ? context.go(primary[n].path)
              : _showMore(context, more, badgeFor),
          destinations: [
            for (final i in primary)
              NavigationDestination(
                icon: _Badged(count: badgeFor(i), child: Icon(i.icon)),
                selectedIcon: _Badged(count: badgeFor(i), child: Icon(i.selectedIcon)),
                label: i.label,
              ),
            NavigationDestination(
              icon: _Badged(count: more.fold(0, (s, i) => s + badgeFor(i)), child: const Icon(Icons.menu)),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }

  static void _showMore(BuildContext context, List<NavItem> items, int Function(NavItem) badgeFor) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final i in items)
              ListTile(
                leading: _Badged(count: badgeFor(i), child: Icon(i.icon)),
                title: Text(i.label),
                onTap: () {
                  Navigator.pop(sheet);
                  context.go(i.path);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Badged extends StatelessWidget {
  const _Badged({required this.count, required this.child});
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      count > 0 ? Badge(label: Text('$count'), child: child) : child;
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.items,
    required this.index,
    required this.expanded,
    required this.badgeFor,
  });

  final List<NavItem> items;
  final int index;
  final bool expanded;
  final int Function(NavItem) badgeFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(currentUserProvider);
    final company = ref.watch(appConfigProvider).company.name;
    final listed = items.where((i) => i.path != '/profile').toList();
    final profileSelected = items[index].path == '/profile';

    final children = <Widget>[];
    String? lastGroup;
    for (final item in listed) {
      if (item.group != lastGroup) {
        lastGroup = item.group;
        if (item.group != null) {
          children.add(
            expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
                    child: Text(
                      item.group!.toUpperCase(),
                      style: const TextStyle(fontSize: 11, letterSpacing: 0.9, fontWeight: FontWeight.w700, color: AppColors.muted),
                    ),
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    child: Divider(height: 1),
                  ),
          );
        }
      }
      children.add(
        _SideItem(
          item: item,
          selected: items[index] == item,
          expanded: expanded,
          badge: badgeFor(item),
          onTap: () => context.go(item.path),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: expanded ? 252 : 76,
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFC),
        border: Border(right: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => context.go('/home'),
              child: Padding(
                padding: EdgeInsets.fromLTRB(expanded ? 18 : 0, 20, expanded ? 14 : 0, 18),
                child: expanded
                    ? BrandLockup(name: company, tagline: 'Project control')
                    : const Center(child: BrandMark(size: 38)),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 12),
                children: children,
              ),
            ),
            const Divider(height: 1),
            Material(
              color: profileSelected ? scheme.primary.withValues(alpha: 0.08) : Colors.transparent,
              child: InkWell(
                onTap: () => context.go('/profile'),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 0, vertical: 14),
                  child: Row(
                    mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 17,
                        backgroundColor: scheme.primary.withValues(alpha: 0.12),
                        foregroundColor: scheme.primary,
                        child: Text(user.initials, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                      ),
                      if (expanded) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.name.isEmpty ? user.email : user.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              Text(user.role.label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(Icons.unfold_more, size: 18, color: AppColors.muted),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideItem extends StatefulWidget {
  const _SideItem({
    required this.item,
    required this.selected,
    required this.expanded,
    required this.badge,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final bool expanded;
  final int badge;
  final VoidCallback onTap;

  @override
  State<_SideItem> createState() => _SideItemState();
}

class _SideItemState extends State<_SideItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final color = selected ? scheme.primary : AppColors.muted;
    final icon = Icon(selected ? widget.item.selectedIcon : widget.item.icon, color: color, size: 21);
    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 3),
          padding: EdgeInsets.symmetric(horizontal: widget.expanded ? 12 : 0, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white
                : _hover
                ? const Color(0xFFEFF2F6)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? AppColors.line : Colors.transparent),
            boxShadow: selected ? const [BoxShadow(color: Color(0x0A16202A), blurRadius: 6, offset: Offset(0, 2))] : null,
          ),
          child: Row(
            mainAxisAlignment: widget.expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              if (widget.expanded) icon else _Badged(count: widget.badge, child: icon),
              if (widget.expanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: TextStyle(
                      color: selected ? AppColors.ink : const Color(0xFF3A4755),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (widget.badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(99)),
                    child: Text(
                      '${widget.badge}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    return widget.expanded ? tile : Tooltip(message: widget.item.label, child: tile);
  }
}
