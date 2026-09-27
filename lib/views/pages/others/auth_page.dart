import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/auth_controller.dart';
import 'package:flutter_app/views/dashboard_page.dart';
import 'package:flutter_app/views/pages/dashboard/salesman_dashboard_page.dart';
import 'package:flutter_app/views/pages/others/loading_page.dart';
import 'package:flutter_app/views/pages/others/welcome_page.dart';

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
        return isDealer ? const DashboardPage() : const SalesmanDashboardPage();
      },
    );
  }
}
