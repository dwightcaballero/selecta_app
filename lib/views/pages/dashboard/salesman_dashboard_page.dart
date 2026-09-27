import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/dashboard_controller.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/dto/dashboard_dto.dart';
import 'package:flutter_app/models/users.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/views/pages/dashboard/deliverylist_page.dart';
import 'package:flutter_app/views/pages/dashboard/pjplist_page.dart';
import 'package:flutter_app/views/pages/dashboard/returnlist_page.dart';
import 'package:flutter_app/views/pages/dashboard/scanninglist_page.dart';
import 'package:flutter_app/views/pages/others/auth_page.dart';
import 'package:flutter_app/views/pages/sidebar/badorderlist_page.dart';
import 'package:flutter_app/views/pages/sidebar/endofday_page.dart';
import 'package:flutter_app/views/pages/sidebar/expenselist_page.dart';
import 'package:flutter_app/views/pages/sidebar/tasklist_page.dart';
import 'package:flutter_app/views/pages/sidebar/transactionlist_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SalesmanDashboardPage extends StatefulWidget {
  const SalesmanDashboardPage({super.key});

  @override
  State<SalesmanDashboardPage> createState() => _SalesmanDashboardPageState();
}

class _SalesmanDashboardPageState extends State<SalesmanDashboardPage> {
  Users? _currentUser;
  DashboardDTO _dashboardDTO = DashboardDTO.empty();
  bool _isLoading = true;
  bool _isSyncing = false;
  String _lastSyncDateTime = '';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final user = await KVariables.getUser();
      final lastSync = await DashboardController.getLastSync();
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('dashboard_DTO');

      DashboardDTO dto = DashboardDTO.empty();
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          dto = DashboardDTO.fromJson(jsonDecode(cachedJson));
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _currentUser = user;
          _lastSyncDateTime = lastSync;
          _dashboardDTO = dto;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _syncDashboard() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final latestDto = await DashboardController.getLatestDashboardData();
      final lastSync = await DashboardController.getLastSync();

      if (mounted) {
        setState(() {
          _dashboardDTO = latestDto;
          _lastSyncDateTime = lastSync;
        });
        ShowMessage.success(context, 'Salesman dashboard synced successfully.');
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Sync failed. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _onLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.logout_rounded, color: colorScheme.error),
              const SizedBox(width: 10),
              const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: const Text('Are you sure you want to sign out of your salesman account?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      try {
        await authService.value.signOut();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthPage()),
            (_) => false,
          );
        }
      } on FirebaseAuthException catch (e) {
        if (mounted) {
          ShowMessage.error(context, e.message ?? 'Error signing out.');
        }
      }
    }
  }

  Widget _buildWelcomeBanner() {
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = _currentUser?.username ?? authService.value.currentUser?.displayName ?? 'Salesman';
    final hasSyncTime = _lastSyncDateTime.isNotEmpty && _lastSyncDateTime != 'Never';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.tertiary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.badge_outlined,
              color: colorScheme.tertiary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Welcome, $displayName!',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Salesman',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.tertiary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.sync_rounded, size: 15, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        hasSyncTime ? 'Last synced: $_lastSyncDateTime' : 'Not synced yet',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildQuickAccessCard({
    required String label,
    required IconData icon,
    required Widget nextPage,
    int count = 0,
    Color? iconColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = iconColor ?? colorScheme.primary;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Helperfunctions.navigateThenWait(context, nextPage);
          if (mounted) {
            final prefs = await SharedPreferences.getInstance();
            final cachedJson = prefs.getString('dashboard_DTO');
            if (cachedJson != null && cachedJson.isNotEmpty) {
              try {
                setState(() {
                  _dashboardDTO = DashboardDTO.fromJson(jsonDecode(cachedJson));
                });
              } catch (_) {}
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: count > 0,
                label: Text(
                  '$count',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                backgroundColor: colorScheme.error,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: effectiveColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 26, color: effectiveColor),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(
        title: 'Salesman Dashboard',
        subtitle: 'Field Sales Operations',
        showBackButton: false,
        centerTitle: false,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
          ),
          child: const Icon(Icons.person_rounded, size: 22, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync_rounded, color: Colors.white),
            onPressed: _isSyncing ? null : _syncDashboard,
            tooltip: 'Sync Dashboard',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            onPressed: _onLogout,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _syncDashboard,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Salesman Welcome Banner
                    _buildWelcomeBanner(),

                    const SizedBox(height: 20),

                    // 2. Primary Operations Quick Access
                    _buildSectionHeader('Operations Quick Access', 'Deliveries, store scanning, and journey plans'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildQuickAccessCard(
                            label: 'Deliveries',
                            icon: Icons.local_shipping_outlined,
                            count: _dashboardDTO.pendingDeliveryCount,
                            iconColor: const Color(0xFF2563EB),
                            nextPage: const DeliveryListPage(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildQuickAccessCard(
                            label: 'Scanning',
                            icon: Icons.qr_code_scanner_outlined,
                            count: _dashboardDTO.totalNotScannedCount + _dashboardDTO.totalUnassignedCount,
                            iconColor: const Color(0xFFD97706),
                            nextPage: const ScanninglistPage(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildQuickAccessCard(
                            label: 'PJP',
                            icon: Icons.map_outlined,
                            count: _dashboardDTO.pendingPjpCount,
                            iconColor: const Color(0xFF0F766E),
                            nextPage: const PjpListPage(),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // 3. Drawer Replacement: Field Activities & Reports
                    _buildSectionHeader('Field Activities & Reports', 'Orders, records, daily tracking, and expenses'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildQuickAccessCard(
                            label: 'Tasks',
                            icon: Icons.task_alt_outlined,
                            iconColor: const Color(0xFF059669),
                            nextPage: TaskListPage(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildQuickAccessCard(
                            label: 'Transactions',
                            icon: Icons.swap_horiz_outlined,
                            iconColor: const Color(0xFF4F46E5),
                            nextPage: const TransactionListPage(storeName: ''),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildQuickAccessCard(
                            label: 'End of Day',
                            icon: Icons.today_outlined,
                            iconColor: const Color(0xFFD97706),
                            nextPage: const EndofdayPage(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildQuickAccessCard(
                            label: 'Bad Orders',
                            icon: Icons.assignment_late_outlined,
                            iconColor: const Color(0xFFDC2626),
                            nextPage: BadOrderlistPage(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildQuickAccessCard(
                            label: 'Expenses',
                            icon: Icons.receipt_long_outlined,
                            iconColor: const Color(0xFF7C3AED),
                            nextPage: const ExpenselistPage(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildQuickAccessCard(
                            label: 'Returns',
                            icon: Icons.assignment_return_outlined,
                            count: _dashboardDTO.returnedDeliveryCount,
                            iconColor: const Color(0xFFE11D48),
                            nextPage: const ReturnlistPage(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
