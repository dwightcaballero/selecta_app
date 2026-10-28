import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/configuration_controller.dart';
import 'package:selecta_ops/controllers/dashboard_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/services/gemini_ai_service.dart';
import 'package:selecta_ops/views/dashboard_page.dart';
import 'package:selecta_ops/views/pages/dashboard/salesman_dashboard_page.dart';
import 'package:selecta_ops/views/pages/sidebar/error_logs_page.dart';
import 'package:selecta_ops/views/pages/sidebar/products_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/user_services.dart';
import 'package:selecta_ops/services/ai/gemini_text_provider.dart';
import 'package:selecta_ops/services/ai/groq_text_provider.dart';

/// Hidden Super Admin developer control panel for managing AI settings,
/// quota limits, API keys, and switching business roles.
class SuperAdminPage extends StatefulWidget {
  const SuperAdminPage({super.key});

  @override
  State<SuperAdminPage> createState() => _SuperAdminPageState();
}

class _SuperAdminPageState extends State<SuperAdminPage> {
  final ConfigurationController _configController = ConfigurationController();
  final DashboardController _dashboardController = DashboardController();

  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _groqApiKeyController = TextEditingController();
  final TextEditingController _monthlyLimitController = TextEditingController(text: '1000');
  final TextEditingController _newAdminPasswordController = TextEditingController();
  final TextEditingController _confirmAdminPasswordController = TextEditingController();
  bool _obscureNewAdminPassword = true;
  bool _obscureConfirmAdminPassword = true;
  bool _isSettingAdminPassword = false;
  bool _adminPasswordIsSet = false;

  Configuration? _originalConfig;
  bool _configExistsInDb = false;
  bool _obscureApiKey = true;
  bool _obscureGroqApiKey = true;
  bool _aiEnabled = true;
  String _aiScanMode = 'hybrid';
  String _primaryProvider = 'gemini';
  bool _isTestingGemini = false;
  bool _isTestingGroq = false;
  int _currentMonthUsage = 0;
  String _currentRole = BusinessRole.dealer;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSwitchingRole = false;
  int _pendingLogsCount = 0;
  bool _isUploadingLogs = false;

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _groqApiKeyController.dispose();
    _monthlyLimitController.dispose();
    _newAdminPasswordController.dispose();
    _confirmAdminPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadAllSettings() async {
    try {
      final configResult = await _configController.loadConfiguration();
      final apiKey = await _configController.getGeminiApiKey();
      final groqKey = await _configController.getGroqApiKey();
      final usage = await _configController.getCurrentAiUsage();
      final isDealer = await _dashboardController.isCurrentUserDealer();
      final pendingLogs = await ErrorLogService.getPendingLogCount();
      final currentUser = await KVariables.getUser();
      final currentRole = currentUser?.role ?? (isDealer ? BusinessRole.dealer : BusinessRole.salesman);

      if (mounted) {
        setState(() {
          _originalConfig = configResult.config;
          _configExistsInDb = configResult.existsInDb;
          _aiEnabled = configResult.config.aiEnabled;
          _monthlyLimitController.text = configResult.config.aiMonthlyRequestLimit.toString();
          _apiKeyController.text = apiKey ?? configResult.config.geminiApiKey;
          _groqApiKeyController.text = groqKey ?? configResult.config.groqApiKey;
          _aiScanMode = configResult.config.aiScanMode;
          _primaryProvider = configResult.config.aiProviderOrder.isNotEmpty
              ? configResult.config.aiProviderOrder.first
              : 'gemini';
          _currentMonthUsage = usage;
          _currentRole = currentRole;
          _pendingLogsCount = pendingLogs;
          _adminPasswordIsSet = configResult.config.superAdminPasswordHash.isNotEmpty;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ShowMessage.error(context, 'Failed to load developer settings: $e');
      }
    }
  }

  Future<void> _handleRoleSwitch() async {
    if (_isSwitchingRole) return;
    final selectedRole = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Switch Active Role', style: TextStyle(fontWeight: FontWeight.bold)),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, BusinessRole.admin),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF7C3AED).withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF7C3AED)),
                ),
                title: const Text('Admin', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Superuser: All dealer access + hard-delete testing permissions'),
                trailing: _currentRole == BusinessRole.admin ? const Icon(Icons.check, color: Color(0xFF7C3AED)) : null,
              ),
            ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, BusinessRole.dealer),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.store_rounded, color: Colors.blue),
                ),
                title: const Text('Dealer', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Operational dealer view: void-only protection for business safety'),
                trailing: _currentRole == BusinessRole.dealer ? const Icon(Icons.check, color: Colors.blue) : null,
              ),
            ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, BusinessRole.salesman),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.badge_outlined, color: Colors.teal),
                ),
                title: const Text('Salesman', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Salesman view: routes, store visits, and order booking'),
                trailing: _currentRole == BusinessRole.salesman ? const Icon(Icons.check, color: Colors.teal) : null,
              ),
            ),
          ],
        );
      },
    );

    if (selectedRole == null || selectedRole == _currentRole) return;

    setState(() => _isSwitchingRole = true);
    try {
      final newRole = await _dashboardController.switchUserRoleTo(selectedRole);
      if (!mounted) return;

      ShowMessage.success(context, 'Switched active role to $newRole');
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => (newRole == BusinessRole.dealer || newRole == BusinessRole.admin)
              ? const DashboardPage()
              : const SalesmanDashboardPage(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSwitchingRole = false);
        ShowMessage.error(context, 'Failed to switch role: $e');
      }
    }
  }

  Future<void> _handleDeleteUserAccount(BuildContext modalCtx, Users user, UserService userService) async {
    final displayName = user.username.isNotEmpty ? user.username : user.email;
    final confirmed = await ShowMessage.confirm(
      modalCtx,
      title: 'Delete Account',
      message: 'Are you sure you want to permanently delete the account for "$displayName" (${user.email})?\n\nThis will remove the user record from the database. This action cannot be undone.',
      confirmText: 'Delete Account',
      isDestructive: true,
      icon: Icons.person_remove_rounded,
    );

    if (confirmed != true) return;

    try {
      await userService.deleteUserAccount(user);
      if (modalCtx.mounted) {
        ShowMessage.success(modalCtx, 'Account for $displayName deleted successfully.');
      }
    } catch (e) {
      if (modalCtx.mounted) {
        ShowMessage.error(modalCtx, 'Failed to delete account: $e');
      }
    }
  }

  Future<void> _openManageUserRolesModal() async {
    final userService = UserService();
    final currentUser = await KVariables.getUser();
    final currentEmail = currentUser?.email.toLowerCase().trim() ?? '';
    String searchQuery = '';

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.manage_accounts_rounded, size: 24),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'User Accounts & Roles',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(modalCtx),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search username, email, or role...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.grey.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onChanged: (val) {
                          setModalState(() {
                            searchQuery = val.trim().toLowerCase();
                          });
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: StreamBuilder<List<Users>>(
                        stream: userService.getAllUsersStream(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final allUsers = snapshot.data ?? [];
                          final users = allUsers.where((u) {
                            if (searchQuery.isEmpty) return true;
                            return u.username.toLowerCase().contains(searchQuery) ||
                                u.email.toLowerCase().contains(searchQuery) ||
                                u.role.toLowerCase().contains(searchQuery) ||
                                u.dealerName.toLowerCase().contains(searchQuery);
                          }).toList();

                          if (users.isEmpty) {
                            return Center(
                              child: Text(
                                searchQuery.isNotEmpty
                                    ? 'No accounts match "$searchQuery"'
                                    : 'No users found in database.',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            );
                          }

                          return ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: users.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final user = users[index];
                              final role = user.role;
                              final isAdmin = user.isAdmin;
                              final isDealer = role == BusinessRole.dealer;
                              final isSelf = user.email.toLowerCase().trim() == currentEmail;

                              final badgeColor = isAdmin
                                  ? const Color(0xFF7C3AED)
                                  : (isDealer ? Colors.blue : Colors.teal);

                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: badgeColor.withValues(alpha: 0.15),
                                    child: Icon(
                                      isAdmin
                                          ? Icons.admin_panel_settings_rounded
                                          : (isDealer ? Icons.store_rounded : Icons.badge_outlined),
                                      color: badgeColor,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          user.username.isNotEmpty ? user.username : 'Unnamed User',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isSelf) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'You',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user.email,
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (user.dealerName.isNotEmpty)
                                        Text(
                                          'Dealer: ${user.dealerName}',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      PopupMenuButton<String>(
                                        initialValue: role,
                                        tooltip: 'Change Role',
                                        child: Chip(
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                          label: Text(
                                            role.isNotEmpty ? role : 'Unknown',
                                            style: TextStyle(
                                              color: badgeColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                          backgroundColor: badgeColor.withValues(alpha: 0.1),
                                          side: BorderSide(color: badgeColor.withValues(alpha: 0.3)),
                                        ),
                                        onSelected: (newRole) async {
                                          if (newRole == role) return;
                                          try {
                                            await userService.updateUserRoleByEmail(user.email, newRole);
                                            if (modalCtx.mounted) {
                                              ShowMessage.success(modalCtx, 'Updated ${user.username} to $newRole');
                                            }
                                          } catch (e) {
                                            if (modalCtx.mounted) {
                                              ShowMessage.error(modalCtx, 'Failed to update role: $e');
                                            }
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: BusinessRole.admin,
                                            child: Row(
                                              children: [
                                                Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF7C3AED), size: 18),
                                                SizedBox(width: 8),
                                                Text('Admin'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: BusinessRole.dealer,
                                            child: Row(
                                              children: [
                                                Icon(Icons.store_rounded, color: Colors.blue, size: 18),
                                                SizedBox(width: 8),
                                                Text('Dealer'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: BusinessRole.salesman,
                                            child: Row(
                                              children: [
                                                Icon(Icons.badge_outlined, color: Colors.teal, size: 18),
                                                SizedBox(width: 8),
                                                Text('Salesman'),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 4),
                                      if (!isSelf)
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                          tooltip: 'Delete Account',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                          onPressed: () => _handleDeleteUserAccount(modalCtx, user, userService),
                                        )
                                      else
                                        const SizedBox(
                                          width: 36,
                                          child: Tooltip(
                                            message: 'Current active session (cannot delete self)',
                                            child: Icon(Icons.shield_outlined, color: Colors.grey, size: 18),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _handleSetAdminPassword() async {
    if (_isSettingAdminPassword) return;
    final newPw = _newAdminPasswordController.text.trim();
    final confirmPw = _confirmAdminPasswordController.text.trim();

    if (newPw.isEmpty || confirmPw.isEmpty) {
      ShowMessage.error(context, 'Both password fields are required.');
      return;
    }
    if (newPw.length < 8) {
      ShowMessage.error(context, 'Password must be at least 8 characters.');
      return;
    }
    if (newPw != confirmPw) {
      ShowMessage.error(context, 'Passwords do not match.');
      return;
    }

    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Set Admin Password',
      message: 'This will update the super-admin password. Make sure you remember it.',
      confirmText: 'Set Password',
      icon: Icons.lock_reset_rounded,
    );
    if (!confirmed) return;

    setState(() => _isSettingAdminPassword = true);
    try {
      final hash = Configuration.hashPassword(newPw);
      final updatedConfig = (_originalConfig ?? Configuration.empty()).copyWith(superAdminPasswordHash: hash);
      await ConfigurationService().saveConfiguration(updatedConfig);
      _originalConfig = updatedConfig;
      _newAdminPasswordController.clear();
      _confirmAdminPasswordController.clear();
      if (mounted) {
        setState(() {
          _adminPasswordIsSet = true;
          _isSettingAdminPassword = false;
        });
        ShowMessage.success(context, 'Admin password updated successfully.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSettingAdminPassword = false);
        ShowMessage.error(context, 'Failed to set password: $e');
      }
    }
  }

  Future<void> _handleUploadPendingLogs() async {
    if (_isUploadingLogs) return;
    setState(() => _isUploadingLogs = true);
    try {
      final count = await ErrorLogService.uploadPendingLogs();
      final remaining = await ErrorLogService.getPendingLogCount();
      if (!mounted) return;
      setState(() => _pendingLogsCount = remaining);
      if (count > 0) {
        ShowMessage.success(context, 'Uploaded $count pending error log${count == 1 ? "" : "s"} to Firestore');
      } else {
        ShowMessage.alert(context, title: 'Error Logs', message: 'All error logs are already synced.');
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to upload error logs: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingLogs = false);
      }
    }
  }

  Future<void> _saveAiSettings() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final monthlyLimit = int.tryParse(_monthlyLimitController.text.trim()) ?? 1000;
      final startDate = _originalConfig?.merchBlitzStartDate.toDate() ?? DateTime.now();
      final endDate = _originalConfig?.merchBlitzEndDate.toDate() ?? DateTime.now().add(const Duration(days: 7));
      final providerOrder = _primaryProvider == 'gemini' ? ['gemini', 'groq'] : ['groq', 'gemini'];

      await _configController.saveConfiguration(
        startDate: startDate,
        endDate: endDate,
        originalConfig: _originalConfig,
        existsInDb: _configExistsInDb,
        aiEnabled: _aiEnabled,
        geminiApiKey: _apiKeyController.text.trim(),
        groqApiKey: _groqApiKeyController.text.trim(),
        aiScanMode: _aiScanMode,
        aiProviderOrder: providerOrder,
        aiMonthlyRequestLimit: monthlyLimit,
      );

      await _configController.saveGeminiApiKey(_apiKeyController.text);
      await _configController.saveGroqApiKey(_groqApiKeyController.text);
      GeminiAiService().invalidateCachedKey();

      _configExistsInDb = true;

      if (mounted) {
        ShowMessage.success(context, 'Superadmin AI settings saved successfully!');
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to save settings: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _testGeminiConnection() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      ShowMessage.error(context, 'Please enter a Gemini API Key first.');
      return;
    }
    setState(() => _isTestingGemini = true);
    try {
      final provider = GeminiTextProvider(getApiKey: () => key);
      final res = await provider.generateJson(
        'Respond with {"status": "ok", "provider": "gemini"}',
        schemaHint: '{"status": string, "provider": string}',
        timeout: const Duration(seconds: 10),
      );
      if (mounted) {
        ShowMessage.success(context, '✅ Gemini Connection Verified! Response: $res');
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, '❌ Gemini Test Failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isTestingGemini = false);
    }
  }

  Future<void> _testGroqConnection() async {
    final key = _groqApiKeyController.text.trim();
    if (key.isEmpty) {
      ShowMessage.error(context, 'Please enter a Groq API Key first.');
      return;
    }
    setState(() => _isTestingGroq = true);
    try {
      final provider = GroqTextProvider(getApiKey: () => key);
      final res = await provider.generateJson(
        'Respond with {"status": "ok", "provider": "groq"}',
        schemaHint: '{"status": string, "provider": string}',
        timeout: const Duration(seconds: 10),
      );
      if (mounted) {
        ShowMessage.success(context, '✅ Groq Connection Verified! Response: $res');
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, '❌ Groq Test Failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isTestingGroq = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: const CustomAppbar(title: 'Super Admin', subtitle: 'Developer & Infrastructure Controls'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Role Switching Control Card
                  Card(
                    elevation: 0,
                    color: colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: (_currentRole == BusinessRole.admin
                                          ? const Color(0xFF7C3AED)
                                          : (_currentRole == BusinessRole.dealer ? colorScheme.primary : colorScheme.tertiary))
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _currentRole == BusinessRole.admin
                                      ? Icons.admin_panel_settings_rounded
                                      : (_currentRole == BusinessRole.dealer ? Icons.store_rounded : Icons.badge_outlined),
                                  size: 22,
                                  color: _currentRole == BusinessRole.admin
                                      ? const Color(0xFF7C3AED)
                                      : (_currentRole == BusinessRole.dealer ? colorScheme.primary : colorScheme.tertiary),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Role Management', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Active Role: $_currentRole',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: _currentRole == BusinessRole.admin
                                            ? const Color(0xFF7C3AED)
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 28),
                          Row(
                            children: [
                              Expanded(
                                child: AsyncFilledButton.icon(
                                  onPressed: _handleRoleSwitch,
                                  loadingLabel: 'Switching...',
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 48),
                                    backgroundColor: _currentRole == BusinessRole.admin
                                        ? const Color(0xFF7C3AED)
                                        : colorScheme.primary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                                  label: const Text('Switch Role', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _openManageUserRolesModal,
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 48),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.manage_accounts_outlined, size: 20),
                                  label: const Text(
                                    'Manage Accounts',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 1b. Admin Password Card
                  Card(
                    elevation: 0,
                    color: colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.lock_rounded, size: 22, color: Colors.red),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Admin Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _adminPasswordIsSet ? 'Password is set ✓' : '⚠ No password configured yet',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _adminPasswordIsSet ? Colors.green : Colors.orange,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 28),
                          TextField(
                            controller: _newAdminPasswordController,
                            obscureText: _obscureNewAdminPassword,
                            decoration: InputDecoration(
                              labelText: 'New Password',
                              hintText: 'Minimum 8 characters',
                              prefixIcon: const Icon(Icons.lock_outline, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              suffixIcon: IconButton(
                                icon: Icon(_obscureNewAdminPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                                onPressed: () => setState(() => _obscureNewAdminPassword = !_obscureNewAdminPassword),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _confirmAdminPasswordController,
                            obscureText: _obscureConfirmAdminPassword,
                            decoration: InputDecoration(
                              labelText: 'Confirm Password',
                              hintText: 'Re-enter new password',
                              prefixIcon: const Icon(Icons.lock_outline, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              suffixIcon: IconButton(
                                icon: Icon(_obscureConfirmAdminPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                                onPressed: () => setState(() => _obscureConfirmAdminPassword = !_obscureConfirmAdminPassword),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          AsyncFilledButton.icon(
                            onPressed: _handleSetAdminPassword,
                            loadingLabel: 'Updating...',
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.lock_reset_rounded, size: 20),
                            label: Text(
                              _adminPasswordIsSet ? 'Change Admin Password' : 'Set Admin Password',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2. Selecta Product Catalog Management (Admin Mode) Card
                  Card(
                    elevation: 0,
                    color: colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1D4ED8).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.inventory_2_rounded, size: 22, color: Color(0xFF1D4ED8)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Selecta Product Catalog', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Admin mode to add, edit, and delete official Selecta products',
                                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 28),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProductsPage(userRole: 'Admin', initialIndex: 0)));
                            },
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                              backgroundColor: const Color(0xFF1D4ED8),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.admin_panel_settings_outlined, size: 20),
                            label: const Text('Manage Selecta Products (Admin)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3. Gemini AI Management Card
                  Card(
                    elevation: 0,
                    color: colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.auto_awesome, size: 22, color: colorScheme.primary),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Antigravity AI Infrastructure', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    SizedBox(height: 2),
                                    Text('Master Gemini settings & quota enforcement', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: _aiEnabled,
                                activeTrackColor: colorScheme.primary,
                                onChanged: (val) => setState(() => _aiEnabled = val),
                              ),
                            ],
                          ),
                          const Divider(height: 28),

                          // Live usage tracker
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: (_aiEnabled ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest).withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.data_usage_rounded, size: 20, color: _aiEnabled ? colorScheme.primary : colorScheme.onSurfaceVariant),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'This Month\'s AI Usage',
                                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                                      ),
                                      Text(
                                        '$_currentMonthUsage requests consumed',
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _aiEnabled ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _aiEnabled ? 'ACTIVE' : 'DISABLED',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _aiEnabled ? Colors.green[800] : Colors.red[800],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Monthly Quota Limit Field
                          TextField(
                            controller: _monthlyLimitController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Monthly Request Limit (Cap)',
                              hintText: 'e.g. 1000',
                              helperText: 'AI assistant automatically pauses when this cap is reached.',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.shield_outlined, size: 20),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // AI Scan Mode Selector
                          DropdownButtonFormField<String>(
                            initialValue: _aiScanMode,
                            decoration: InputDecoration(
                              labelText: 'AI Document Scan Mode',
                              helperText: 'Select default engine for invoice & receipt scanning.',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.document_scanner_outlined, size: 20),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'hybrid',
                                child: Text('Hybrid (\$0 Free Tier, On-Device OCR + LLM Fallback)', style: TextStyle(fontSize: 13)),
                              ),
                              DropdownMenuItem(
                                value: 'ocr_local',
                                child: Text('OCR Local Only (\$0 Offline, Pure On-Device)', style: TextStyle(fontSize: 13)),
                              ),
                              DropdownMenuItem(
                                value: 'cloud_vision',
                                child: Text('Cloud Vision (Gemini Multimodal, Emergency Fallback)', style: TextStyle(fontSize: 13)),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _aiScanMode = val);
                            },
                          ),

                          const SizedBox(height: 14),

                          // AI Provider Priority Selector
                          DropdownButtonFormField<String>(
                            initialValue: _primaryProvider,
                            decoration: InputDecoration(
                              labelText: 'Primary LLM Provider',
                              helperText: 'First provider called for ambiguous lines & AI chat.',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.swap_calls_rounded, size: 20),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'gemini',
                                child: Text('Google Gemini (Flash) -> Groq Fallback', style: TextStyle(fontSize: 13)),
                              ),
                              DropdownMenuItem(
                                value: 'groq',
                                child: Text('Groq (Llama 3.3) -> Gemini Fallback', style: TextStyle(fontSize: 13)),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _primaryProvider = val);
                            },
                          ),

                          const SizedBox(height: 14),

                          // Gemini API Key Field + Test Connection
                          TextField(
                            controller: _apiKeyController,
                            obscureText: _obscureApiKey,
                            decoration: InputDecoration(
                              labelText: 'Gemini API Key (Google AI Studio)',
                              hintText: 'Enter AI Studio API key',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.key_rounded, size: 20),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(_obscureApiKey ? Icons.visibility_off : Icons.visibility, size: 20),
                                    onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                                  ),
                                  TextButton(
                                    onPressed: _isTestingGemini ? null : _testGeminiConnection,
                                    child: _isTestingGemini
                                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Text('Test', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Groq API Key Field + Test Connection
                          TextField(
                            controller: _groqApiKeyController,
                            obscureText: _obscureGroqApiKey,
                            decoration: InputDecoration(
                              labelText: 'Groq API Key (Console.groq.com)',
                              hintText: 'Enter Groq Cloud API key (gsk_...)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(_obscureGroqApiKey ? Icons.visibility_off : Icons.visibility, size: 20),
                                    onPressed: () => setState(() => _obscureGroqApiKey = !_obscureGroqApiKey),
                                  ),
                                  TextButton(
                                    onPressed: _isTestingGroq ? null : _testGroqConnection,
                                    child: _isTestingGroq
                                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Text('Test', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Shared securely via Firestore config. Used for fast text LLM calls and chat.',
                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3. System Diagnostics & Error Logs Card
                  Card(
                    elevation: 0,
                    color: colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                                child: Icon(Icons.bug_report_rounded, size: 22, color: Colors.red.shade700),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Error Logs & Diagnostics', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Real-time Firestore logs, crash reports & device queue',
                                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 28),

                          // Live error stream tracker
                          StreamBuilder<List<ErrorLogItem>>(
                            stream: ErrorLogService.streamFirestoreLogs(limit: 50),
                            builder: (context, snapshot) {
                              final cloudCount = snapshot.data?.length ?? 0;
                              final hasErrors = cloudCount > 0;
                              final lastError = (snapshot.data != null && snapshot.data!.isNotEmpty) ? snapshot.data!.first : null;

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: (hasErrors ? Colors.red : Colors.green).withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: (hasErrors ? Colors.red : Colors.green).withValues(alpha: 0.25)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          hasErrors ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                                          size: 20,
                                          color: hasErrors ? Colors.red.shade700 : Colors.green.shade700,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            hasErrors ? '$cloudCount Error Log${cloudCount == 1 ? "" : "s"} in Cloud' : '0 Errors in Cloud (Healthy)',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: hasErrors ? Colors.red.shade900 : Colors.green.shade900,
                                            ),
                                          ),
                                        ),
                                        if (_pendingLogsCount > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '$_pendingLogsCount pending offline',
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (lastError != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Latest: ${lastError.page} - ${lastError.error}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 14),

                          // Open Error Logs Viewer Button
                          FilledButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ErrorLogsPage()));
                              if (mounted) {
                                final remaining = await ErrorLogService.getPendingLogCount();
                                setState(() => _pendingLogsCount = remaining);
                              }
                            },
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(double.infinity, 46),
                              backgroundColor: colorScheme.surfaceContainerHighest,
                              foregroundColor: colorScheme.onSurface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
                              ),
                            ),
                            icon: const Icon(Icons.list_alt_rounded, size: 20),
                            label: const Text('View Full Error Logs Console', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),

                          if (_pendingLogsCount > 0) ...[
                            const SizedBox(height: 8),
                            AsyncOutlinedButton.icon(
                              onPressed: _handleUploadPendingLogs,
                              loadingLabel: 'Uploading...',
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 44),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                              label: Text(
                                'Sync $_pendingLogsCount Offline Log${_pendingLogsCount == 1 ? "" : "s"} to Firestore',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Save Configurations Button
                  AsyncFilledButton.icon(
                    onPressed: _saveAiSettings,
                    loadingLabel: 'Saving...',
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.save_rounded, size: 20),
                    label: const Text(
                      'Save Superadmin Settings',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
