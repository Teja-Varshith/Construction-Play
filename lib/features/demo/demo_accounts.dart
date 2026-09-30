import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase/firebase_providers.dart';
import '../auth/domain/app_user.dart';

/// Shared password for every demo login. Demo accounts only ever see demo
/// projects' data plus whatever their role allows, and are deactivated when
/// demo data is removed.
const demoPassword = 'Demo@2026';

class DemoAccount {
  const DemoAccount(this.role, this.name, this.email, this.designation);

  final UserRole role;
  final String name;
  final String email;
  final String designation;
}

const demoAccounts = [
  DemoAccount(UserRole.ceo, 'Arjun Rao (Demo CEO)', 'ceo.demo@chennapatanam.app', 'Chief Executive Officer'),
  DemoAccount(UserRole.admin, 'Priya Nair (Demo Admin)', 'admin.demo@chennapatanam.app', 'Office Administrator'),
  DemoAccount(UserRole.manager, 'Karthik Iyer (Demo Manager)', 'manager.demo@chennapatanam.app', 'Project Manager'),
  DemoAccount(UserRole.manager, 'Divya Menon (Demo Manager)', 'manager2.demo@chennapatanam.app', 'Project Manager'),
  DemoAccount(UserRole.supervisor, 'Suresh Kumar (Demo Supervisor)', 'supervisor.demo@chennapatanam.app', 'Site Supervisor'),
  DemoAccount(UserRole.staff, 'Meena Das (Demo Staff)', 'staff.demo@chennapatanam.app', 'Site Engineer'),
];

bool isDemoEmail(String email) =>
    demoAccounts.any((a) => a.email == email.trim().toLowerCase());

/// Public flag (readable before sign-in) that turns on the demo sign-in
/// buttons on the login screen. Written by an admin when demo data is loaded.
DocumentReference<Map<String, dynamic>> demoStateDoc(FirebaseFirestore db) =>
    db.collection('publicDemo').doc('state');

final demoLoginsEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    final snap = await demoStateDoc(ref.watch(firestoreProvider)).get();
    return snap.data()?['enabled'] == true;
  } catch (_) {
    return false;
  }
});
