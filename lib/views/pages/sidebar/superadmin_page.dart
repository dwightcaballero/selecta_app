import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/configuration_controller.dart';
import 'package:flutter_app/controllers/dashboard_controller.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/models/configuration.dart';
import 'package:flutter_app/services/gemini_ai_service.dart';
import 'package:flutter_app/views/dashboard_page.dart';
import 'package:flutter_app/views/pages/dashboard/salesman_dashboard_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

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
  final TextEditingController _monthlyLimitController = TextEditingController(text: '1000');

  Configuration? _originalConfig;
  bool _configExistsInDb = false;
  bool _obscureApiKey = true;
  bool _aiEnabled = true;
  int _currentMonthUsage = 0;
  bool _isDealer = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSwitchingRole = false;

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _monthlyLimitController.dispose();
    super.dispose();
  }

  Future<void> _loadAllSettings() async {
    try {
      final configResult = await _configController.loadConfiguration();
      final apiKey = await _configController.getGeminiApiKey();
      final usage = await _configController.getCurrentAiUsage();
      final isDealer = await _dashboardController.isCurrentUserDealer();

      if (mounted) {
        setState(() {
          _originalConfig = configResult.config;
          _configExistsInDb = configResult.existsInDb;
          _aiEnabled = configResult.config.aiEnabled;
          _monthlyLimitController.text = configResult.config.aiMonthlyRequestLimit.toString();
          _apiKeyController.text = apiKey ?? configResult.config.geminiApiKey;
          _currentMonthUsage = usage;
          _isDealer = isDealer;
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
    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Switch Role',
      message: 'Switch active business role to ${_isDealer ? "Salesman" : "Dealer"}?',
      confirmText: 'Switch',
      icon: Icons.swap_horiz_rounded,
    );

    if (!confirmed) return;

    setState(() => _isSwitchingRole = true);
    try {
      final newRole = await _dashboardController.switchUserRole(_isDealer);
      if (!mounted) return;

      ShowMessage.success(context, 'Switched role to $newRole');
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => newRole == BusinessRole.dealer ? const DashboardPage() : const SalesmanDashboardPage(),
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

  Future<void> _saveAiSettings() async {
    setState(() => _isSaving = true);

    try {
      final monthlyLimit = int.tryParse(_monthlyLimitController.text.trim()) ?? 1000;
      final startDate = _originalConfig?.merchBlitzStartDate.toDate() ?? DateTime.now();
      final endDate = _originalConfig?.merchBlitzEndDate.toDate() ?? DateTime.now().add(const Duration(days: 7));

      await _configController.saveConfiguration(
        startDate: startDate,
        endDate: endDate,
        originalConfig: _originalConfig,
        existsInDb: _configExistsInDb,
        aiEnabled: _aiEnabled,
        geminiApiKey: _apiKeyController.text.trim(),
        aiMonthlyRequestLimit: monthlyLimit,
      );

      await _configController.saveGeminiApiKey(_apiKeyController.text);
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const CustomAppbar(
        title: 'Super Admin',
        subtitle: 'Developer & Infrastructure Controls',
      ),
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
                                  color: (_isDealer ? colorScheme.primary : colorScheme.tertiary).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _isDealer ? Icons.store_rounded : Icons.badge_outlined,
                                  size: 22,
                                  color: _isDealer ? colorScheme.primary : colorScheme.tertiary,
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
                                      'Current role: ${_isDealer ? "Dealer" : "Salesman"}',
                                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 28),
                          FilledButton.icon(
                            onPressed: _isSwitchingRole ? null : _handleRoleSwitch,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                              backgroundColor: _isDealer ? colorScheme.tertiary : colorScheme.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _isSwitchingRole
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.swap_horiz_rounded, size: 20),
                            label: Text(
                              _isSwitchingRole ? 'Switching Role...' : 'Switch to ${_isDealer ? "Salesman" : "Dealer"} View',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2. Gemini AI Management Card
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
                                    Text(
                                      'Master Gemini settings & quota enforcement',
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
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
                                Icon(
                                  Icons.data_usage_rounded,
                                  size: 20,
                                  color: _aiEnabled ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                ),
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

                          // Shared API Key Field
                          TextField(
                            controller: _apiKeyController,
                            obscureText: _obscureApiKey,
                            decoration: InputDecoration(
                              labelText: 'Gemini API Key (Shared for All Users)',
                              hintText: 'Enter your Google AI Studio API key',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.key_rounded, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(_obscureApiKey ? Icons.visibility_off : Icons.visibility, size: 20),
                                onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Hidden from salesmen and dealers. Distributed via Firestore config.',
                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Save Configurations Button
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _saveAiSettings,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded, size: 20),
                    label: Text(
                      _isSaving ? 'Saving...' : 'Save Superadmin Settings',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
