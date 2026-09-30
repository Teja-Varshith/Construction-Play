import '../../../core/data/json_read.dart';

enum UserRole {
  ceo('CEO', 'Sees everything, approves expenses and bonuses'),
  admin('Admin / Office', 'Enters data, manages users and settings'),
  manager('Project manager', 'Runs their assigned projects'),
  supervisor('Site supervisor', 'Daily reports and attendance on site'),
  staff('Engineer / Staff', 'Own tasks and check-in'),
  unknown('Unknown', 'Role not recognised by this app version');

  const UserRole(this.label, this.description);
  final String label;
  final String description;

  static UserRole fromName(String? name) =>
      UserRole.values.firstWhere((r) => r.name == name, orElse: () => UserRole.unknown);

  /// Roles an admin can assign.
  static const assignable = [ceo, admin, manager, supervisor, staff];
}

class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
    this.phone = '',
    this.designation = '',
    this.createdAt,
  });

  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final bool active;
  final String phone;
  final String designation;
  final DateTime? createdAt;

  bool get isAdmin => role == UserRole.admin;
  bool get isCeo => role == UserRole.ceo;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return email.isEmpty ? '?' : email[0].toUpperCase();
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  factory AppUser.fromMap(String uid, Map<String, dynamic> m) => AppUser(
        uid: uid,
        name: m.readString('name'),
        email: m.readString('email'),
        role: UserRole.fromName(m.readStringOrNull('role')),
        active: m.readBool('active'),
        phone: m.readString('phone'),
        designation: m.readString('designation'),
        createdAt: m.readDateTime('createdAt'),
      );
}
