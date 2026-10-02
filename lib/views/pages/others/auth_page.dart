import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/auth_controller.dart';
import 'package:selecta_ops/services/push_notification_service.dart';
import 'package:selecta_ops/views/dashboard_page.dart';
import 'package:selecta_ops/views/pages/dashboard/salesman_dashboard_page.dart';
import 'package:selecta_ops/views/pages/others/loading_page.dart';
import 'package:selecta_ops/views/pages/others/selecta_catalog_sync_gate_page.dart';
import 'package:selecta_ops/views/pages/others/welcome_page.dart';

/// Top-level authentication gateway that listens to auth state changes
/// and routes the user to WelcomePage, DashboardPage, or SalesmanDashboardPage.
class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  static final AuthController _controller = AuthController();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _controller.authStateChanges,
      builder: (BuildContext context, AsyncSnapshot<User?> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPage();
        } else if (snapshot.hasData) {
          return _RoleBasedDashboardRouter(controller: _controller);
        } else {
          return const WelcomePage();
        }
      },
    );
  }
}

class _RoleBasedDashboardRouter extends StatelessWidget {
  final AuthController controller;

  const _RoleBasedDashboardRouter({required this.controller});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: controller.checkIsDealer(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPage();
        }
        final isDealer = snapshot.data ?? true;

        // Auto-register FCM device token and sync topic subscriptions for current user role
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final role = isDealer ? 'Dealer' : 'Salesman';
          PushNotificationService().saveTokenForUser(email: user.email, uid: user.uid, role: role);
          PushNotificationService().syncRoleTopics(role);
        }

        return SelectaCatalogSyncGatePage(
          child: isDealer ? const DashboardPage() : const SalesmanDashboardPage(),
        );
      },
    );
  }
}
