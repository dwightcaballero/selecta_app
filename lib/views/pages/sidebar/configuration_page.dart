import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/configuration_controller.dart';
import 'package:flutter_app/models/configuration.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

/// Presentation page for configuring app-wide settings such as Merch Blitz campaign schedules.
class ConfigurationPage extends StatefulWidget {
  const ConfigurationPage({super.key});

  @override
  State<ConfigurationPage> createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> {
  // Controller managing configuration fetching, validation, and audit logging
  final ConfigurationController _controller = ConfigurationController();

  Configuration? _originalConfig;
  bool _configExistsInDb = false;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _endDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).add(const Duration(days: 7));
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
  }

  /// Loads current configuration via controller
  Future<void> _loadConfiguration() async {
    try {
      final result = await _controller.loadConfiguration();

      if (mounted) {
        setState(() {
          _originalConfig = result.config;
          _configExistsInDb = result.existsInDb;
          _startDate = result.startDate;
          _endDate = result.endDate;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ShowMessage.error(context, 'Failed to load configurations: $e');
      }
    }
  }

  /// Opens date picker for Merch Blitz start date
  Future<void> _pickStartDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2050),
    );

    if (pickedDate != null && mounted) {
      setState(() {
        _startDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day);
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate.add(const Duration(days: 7));
        }
      });
    }
  }

  /// Opens date picker for Merch Blitz end date
  Future<void> _pickEndDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _endDate.isAfter(_startDate) ? _endDate : _startDate,
      firstDate: _startDate,
      lastDate: DateTime(2050),
    );

    if (pickedDate != null && mounted) {
      setState(() {
        _endDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day);
      });
    }
  }

  /// Saves updated configuration through controller
  Future<void> _saveConfiguration() async {
    setState(() => _isSaving = true);

    try {
      await _controller.saveConfiguration(
        startDate: _startDate,
        endDate: _endDate,
        originalConfig: _originalConfig,
        existsInDb: _configExistsInDb,
        aiEnabled: _originalConfig?.aiEnabled ?? true,
        geminiApiKey: _originalConfig?.geminiApiKey ?? '',
        aiMonthlyRequestLimit: _originalConfig?.aiMonthlyRequestLimit ?? 3000,
      );

      _configExistsInDb = true;

      if (mounted) {
        ShowMessage.success(context, 'Configuration saved successfully!');
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, e is ArgumentError ? e.message.toString() : 'Failed to save configuration: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Helper widget for rendering interactive date selection cards
  Widget _buildDateField({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final formattedDate = DateFormat('EEE, d MMM yyyy').format(date);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(12),
          color: colorScheme.surface,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(formattedDate, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Icon(Icons.edit_calendar_outlined, size: 20, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const CustomAppbar(title: 'Configurations', subtitle: 'App & Campaign Settings'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Merch Blitz Settings Card
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
                                  color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.campaign_outlined, size: 22, color: Color(0xFF0284C7)),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Merch Blitz Schedule', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    SizedBox(height: 2),
                                    Text(
                                      'Configure the campaign duration for store merchandising',
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 28),

                          // Start Date Picker
                          _buildDateField(
                            label: 'Merch Blitz Start Date *',
                            date: _startDate,
                            onTap: _pickStartDate,
                            icon: Icons.calendar_today_rounded,
                          ),

                          const SizedBox(height: 14),

                          // End Date Picker
                          _buildDateField(
                            label: 'Merch Blitz End Date *',
                            date: _endDate,
                            onTap: _pickEndDate,
                            icon: Icons.event_available_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Save Configurations Button
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _saveConfiguration,
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
                      _isSaving ? 'Saving...' : 'Save Configurations',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
