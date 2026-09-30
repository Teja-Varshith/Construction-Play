import 'package:flutter/material.dart';

import '../../features/auth/domain/app_user.dart';

class NavItem {
  const NavItem(this.path, this.label, this.icon, this.selectedIcon, {this.group});

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Sidebar section heading; null for the top group.
  final String? group;
}

/// Each role sees only its own short menu. Home is the project list for
/// everyone except the office admin, whose home is the setup checklist.
List<NavItem> navItemsFor(UserRole role) {
  final leader = role == UserRole.ceo || role == UserRole.admin;
  final lead = leader || role == UserRole.manager;
  return [
    const NavItem('/home', 'Home', Icons.space_dashboard_outlined, Icons.space_dashboard),
    if (role == UserRole.admin)
      const NavItem('/projects', 'Projects', Icons.apartment_outlined, Icons.apartment),
    if (lead) ...const [
      NavItem('/insights', 'Insights', Icons.insights_outlined, Icons.insights, group: 'Portfolio'),
      NavItem('/watchlist', 'Delay watchlist', Icons.crisis_alert_outlined, Icons.crisis_alert, group: 'Portfolio'),
    ],
    if (leader) ...const [
      NavItem('/organisation', 'Organisation', Icons.groups_outlined, Icons.groups, group: 'Portfolio'),
      NavItem('/approvals', 'Approvals', Icons.task_alt_outlined, Icons.task_alt, group: 'Finance'),
    ],
    if (role == UserRole.admin) ...const [
      NavItem('/users', 'Users', Icons.people_outline, Icons.people, group: 'Admin'),
      NavItem('/settings', 'Settings', Icons.tune_outlined, Icons.tune, group: 'Admin'),
    ],
    const NavItem('/profile', 'Profile', Icons.person_outline, Icons.person),
  ];
}

/// Which roles may open a route. Routes not listed are open to every
/// signed-in, active user.
const Map<String, Set<UserRole>> routeAccess = {
  '/projects/new': {UserRole.admin},
  '/users': {UserRole.admin},
  '/settings': {UserRole.admin},
  '/approvals': {UserRole.ceo, UserRole.admin},
  '/organisation': {UserRole.ceo, UserRole.admin},
  '/insights': {UserRole.ceo, UserRole.admin, UserRole.manager},
  '/watchlist': {UserRole.ceo, UserRole.admin, UserRole.manager},
};

bool canAccess(UserRole role, String location) {
  for (final entry in routeAccess.entries) {
    if (location == entry.key || location.startsWith('${entry.key}/')) {
      return entry.value.contains(role);
    }
  }
  return true;
}
