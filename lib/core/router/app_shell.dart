import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/session.dart';
import '../../features/finance/data/finance_repository.dart';
import '../../features/home/data/my_day_provider.dart';
import '../../features/home/domain/my_day.dart';
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
    // On-site roles: how many "Do now" tasks wait on My day.
    final urgent = user.isCeo || user.isAdmin
        ? 0
        : (ref.watch(myDayProvider).value?.tasks.where((t) => t.urgency == DayUrgency.now).length ?? 0);
    int badgeFor(NavItem item) => switch (item.path) {
      '/approvals' => pending,
      '/home' => urgent,
      _ => 0,
    };

    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) {
      // A project has its own navy menu (with a way back), so the main
      // sidebar steps aside: one sidebar on screen at a time.
      if (_projectPage.hasMatch(location)) return child;
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(
              items: items,
              index: index,
              expanded: width >= 1100,
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
                    padding: const EdgeInsets.fromLTRB(14, 22, 12, 8),
                    child: Text(
                      item.group!.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF6F7BA0),
                      ),
                    ),
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                    child: Divider(height: 1, color: AppColors.navyRaised),
                  ),
          );
        }
      }
      children.add(
        SideNavItem(
          icon: item.icon,
          selectedIcon: item.selectedIcon,
          label: item.label,
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
      width: expanded ? 248 : 76,
      color: AppColors.navy,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => context.go('/home'),
              child: Padding(
                padding: EdgeInsets.fromLTRB(expanded ? 20 : 0, 22, expanded ? 14 : 0, 14),
                child: expanded
                    ? BrandLockup(name: company, tagline: 'Project control', onDark: true)
                    : const Center(child: BrandMark(size: 38)),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                children: children,
              ),
            ),
            SideUserCard(
              initials: user.initials,
              name: user.name.isEmpty ? user.email : user.name,
              role: user.role.label,
              expanded: expanded,
              selected: profileSelected,
              onTap: () => context.go('/profile'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the navy sidebar (also used by the project's own menu).
class SideNavItem extends StatefulWidget {
  const SideNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedIcon,
    this.expanded = true,
    this.badge = 0,
    this.badgeColor,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final bool selected;
  final bool expanded;
  final int badge;

  /// Defaults to red; the project menu uses amber for counts.
  final Color? badgeColor;
  final VoidCallback onTap;

  @override
  State<SideNavItem> createState() => _SideNavItemState();
}

class _SideNavItemState extends State<SideNavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final color = selected ? Colors.white : AppColors.navyText;
    final icon = Icon(selected ? (widget.selectedIcon ?? widget.icon) : widget.icon, color: color, size: 20);
    final badgeColor = widget.badgeColor ?? context.statusColors.bad;
    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 4),
          padding: EdgeInsets.symmetric(horizontal: widget.expanded ? 12 : 0, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.blue
                : _hover
                ? AppColors.navyRaised
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm + 2),
            boxShadow: selected ? const [BoxShadow(color: Color(0x553557D6), blurRadius: 14, offset: Offset(0, 4))] : null,
          ),
          child: Row(
            mainAxisAlignment: widget.expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              if (widget.expanded) icon else _Badged(count: widget.badge, child: icon),
              if (widget.expanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.badge > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : badgeColor,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${widget.badge}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? AppColors.blue : Colors.white,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    return widget.expanded ? tile : Tooltip(message: widget.label, child: tile);
  }
}

/// The signed-in person at the foot of the sidebar; opens their profile.
class SideUserCard extends StatelessWidget {
  const SideUserCard({
    super.key,
    required this.initials,
    required this.name,
    required this.role,
    required this.expanded,
    required this.selected,
    required this.onTap,
  });

  final String initials;
  final String name;
  final String role;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
    child: Material(
      color: selected ? AppColors.navyRaised : const Color(0xFF172142),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: expanded ? 10 : 0, vertical: 10),
          child: Row(
            mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [Color(0xFFFFC94D), Color(0xFFFF8A4C)]),
                ),
                child: Text(
                  initials,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navy),
                ),
              ),
              if (expanded) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white),
                      ),
                      Text(role, style: const TextStyle(color: AppColors.navyText, fontSize: 11.5)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: AppColors.navyText),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
