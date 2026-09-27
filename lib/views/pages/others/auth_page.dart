import 'package:flutter/material.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/views/dashboard_page.dart';
import 'package:flutter_app/views/pages/dashboard/salesman_dashboard_page.dart';
import 'package:flutter_app/views/pages/others/loading_page.dart';
import 'package:flutter_app/views/pages/others/welcome_page.dart';

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: authService,
      builder: (context, authService, child) {
        return StreamBuilder(
          stream: authService.authStateChanges,
          builder: (BuildContext context, AsyncSnapshot snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingPage();
            } else if (snapshot.hasData) {
              return const _RoleBasedDashboardRouter();
            } else {
              return const WelcomePage();
            }
          },
        );
      },
    );
  }
}

class _RoleBasedDashboardRouter extends StatelessWidget {
  const _RoleBasedDashboardRouter();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: KVariables.getIsDealer(),
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
