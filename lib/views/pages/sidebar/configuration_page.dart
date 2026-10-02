import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/configuration_controller.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/services/thermal_printer_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/models/app_version_info.dart';
import 'package:selecta_ops/services/app_update_service.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/views/widgets/digital_receipt_dialog.dart';

/// Presentation page for configuring app-wide settings such as Merch Blitz campaign schedules.
class ConfigurationPage extends StatefulWidget {
  const ConfigurationPage({super.key});

  @override
  State<ConfigurationPage> createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> {
  // Controller managing configuration fetching, validation, and audit logging
  final ConfigurationController _controller = ConfigurationController();
  final ThermalPrinterService _printerService = ThermalPrinterService();

  Configuration? _originalConfig;
  bool _configExistsInDb = false;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _endDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).add(const Duration(days: 7));
  bool _isLoading = true;
  bool _isSaving = false;

  ThermalPaperSize _thermalPaperSize = ThermalPaperSize.mm58;
  String? _printerName;
  bool _isPrinterConnected = false;
  bool _isTestingPrint = false;

  String _localVersion = '1.0.0';
  int _localBuildNumber = 0;
  AppVersionInfo? _remoteVersionInfo;

  late final TextEditingController _salesTargetController;
  late final TextEditingController _throughputTargetController;
  late final TextEditingController _expansionTargetController;

  @override
  void initState() {
    super.initState();
    _salesTargetController = TextEditingController(text: '1000000');
    _throughputTargetController = TextEditingController(text: '8000');
    _expansionTargetController = TextEditingController(text: '10');
    _loadConfiguration();
  }

  @override
  void dispose() {
    _salesTargetController.dispose();
    _throughputTargetController.dispose();
    _expansionTargetController.dispose();
    super.dispose();
  }

  /// Loads current configuration via controller
  Future<void> _loadConfiguration() async {
    try {
      final result = await _controller.loadConfiguration();
      final paperSize = await _printerService.getPaperSize();
      final pName = await _printerService.getSavedPrinterName();
      final isConnected = await _printerService.isConnected();

      if (mounted) {
        setState(() {
          _originalConfig = result.config;
          _configExistsInDb = result.existsInDb;
          _startDate = result.startDate;
          _endDate = result.endDate;
          _salesTargetController.text = result.config.salesTarget.toStringAsFixed(0);
          _throughputTargetController.text = result.config.throughputTarget.toStringAsFixed(0);
          _expansionTargetController.text = result.config.expansionTarget.toString();
          _thermalPaperSize = paperSize;
          _printerName = pName;
          _isPrinterConnected = isConnected;
          _isLoading = false;
        });
      }

      // Load app version info in background
      final pkg = await AppUpdateService.getCurrentPackageInfo();
      final latest = await AppUpdateService().getLatestVersionInfo();
      if (mounted) {
        setState(() {
          _localVersion = pkg.version;
          _localBuildNumber = int.tryParse(pkg.buildNumber) ?? 0;
          _remoteVersionInfo = latest;
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
    final pickedDate = await showDatePicker(context: context, initialDate: _startDate, firstDate: DateTime(2020), lastDate: DateTime(2050));

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
    final rawSales = _salesTargetController.text.replaceAll(',', '').trim();
    final salesTarget = double.tryParse(rawSales);
    if (salesTarget == null || salesTarget <= 0) {
      ShowMessage.error(context, 'Sales Target must be a valid positive number.');
      return;
    }

    final rawThroughput = _throughputTargetController.text.replaceAll(',', '').trim();
    final throughputTarget = double.tryParse(rawThroughput);
    if (throughputTarget == null || throughputTarget <= 0) {
      ShowMessage.error(context, 'Throughput Target must be a valid positive number.');
      return;
    }

    final rawExpansion = _expansionTargetController.text.replaceAll(',', '').trim();
    final expansionTarget = int.tryParse(rawExpansion);
    if (expansionTarget == null || expansionTarget < 0) {
      ShowMessage.error(context, 'Expansion Target must be a valid non-negative integer.');
      return;
    }

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
        salesTarget: salesTarget,
        buyingTargetPercentage: 80.0,
        throughputTarget: throughputTarget,
        placementTargetPercentage: 80.0,
        scanningTargetPercentage: 100.0,
        expansionTarget: expansionTarget,
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
  Widget _buildDateField({required String label, required DateTime date, required VoidCallback onTap, required IconData icon}) {
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
              decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 20, color: colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant),
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

  Widget _buildKpiTargetsCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
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
                  decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.track_changes_rounded, size: 22, color: Color(0xFF6366F1)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('KPI Monthly Targets', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Text('Set monthly operational goals and performance benchmarks', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),

            // Subsection: Self-Input Monthly Targets
            Text(
              'CUSTOM MONTHLY TARGETS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: colorScheme.primary),
            ),
            const SizedBox(height: 12),

            // Sales Target
            TextFormField(
              controller: _salesTargetController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Sales Target *',
                hintText: '1,000,000',
                prefixText: '₱ ',
                prefixIcon: const Icon(Icons.payments_outlined, size: 20),
                helperText: 'Monthly total invoiced sales target (Default: ₱1,000,000)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 16),

            // Throughput Target
            TextFormField(
              controller: _throughputTargetController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Throughput Target *',
                hintText: '8,000',
                prefixText: '₱ ',
                prefixIcon: const Icon(Icons.speed_outlined, size: 20),
                helperText: 'Target average sales per buying store (Default: ₱8,000)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 16),

            // Expansion Target
            TextFormField(
              controller: _expansionTargetController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Expansion Target *',
                hintText: '10',
                prefixIcon: const Icon(Icons.store_mall_directory_outlined, size: 20),
                suffixText: 'stores',
                helperText: 'Target number of newly opened stores this month (Default: 10)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),

            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Subsection: Fixed Targets
            Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'FIXED BENCHMARK TARGETS',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),

            _buildFixedTargetTile(
              title: 'Buying Target',
              value: '80%',
              scope: '80% of all stores',
              icon: Icons.shopping_cart_outlined,
              accentColor: const Color(0xFF10B981),
            ),
            const SizedBox(height: 10),

            _buildFixedTargetTile(
              title: 'Placement Target',
              value: '80%',
              scope: '80% of all stores',
              icon: Icons.grid_view_outlined,
              accentColor: const Color(0xFFF59E0B),
            ),
            const SizedBox(height: 10),

            _buildFixedTargetTile(
              title: 'Scanning Target',
              value: '100%',
              scope: '100% of all cabinets',
              icon: Icons.qr_code_scanner_outlined,
              accentColor: const Color(0xFF3B82F6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFixedTargetTile({
    required String title,
    required String value,
    required String scope,
    required IconData icon,
    required Color accentColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(scope, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, size: 11, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  value,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: accentColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setThermalPaperSize(ThermalPaperSize size) async {
    setState(() => _thermalPaperSize = size);
    await _printerService.setPaperSize(size);
    if (mounted) {
      ShowMessage.success(context, 'Thermal paper size set to ${size.code}.');
    }
  }

  Future<void> _openPrinterDevicePicker() async {
    // Proactively request Bluetooth permissions
    await _printerService.requestBluetoothPermissions();

    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => PrinterDevicePickerSheet(
        onConnected: (name) async {
          final isConn = await _printerService.isConnected();
          if (ctx.mounted) {
            Navigator.pop(ctx);
          }
          if (mounted) {
            setState(() {
              _printerName = name;
              _isPrinterConnected = isConn;
            });
            ShowMessage.success(context, 'Connected to printer: $name');
          }
        },
      ),
    );
  }

  Future<void> _disconnectPrinter() async {
    await _printerService.disconnect();
    if (mounted) {
      setState(() {
        _isPrinterConnected = false;
      });
      ShowMessage.success(context, 'Printer disconnected.');
    }
  }

  Future<void> _testPrintReceipt() async {
    if (_isTestingPrint) return;
    setState(() => _isTestingPrint = true);
    try {
      final isEnabled = await _printerService.isBluetoothEnabled();
      if (!isEnabled) {
        if (mounted) {
          ShowMessage.error(context, 'Bluetooth is turned off. Please turn on Bluetooth first.');
        }
        return;
      }

      final hasPerm = await _printerService.checkBluetoothPermissions();
      if (!hasPerm) {
        final granted = await _printerService.requestBluetoothPermissions();
        if (!granted) {
          if (mounted) {
            ShowMessage.error(context, 'Bluetooth permission is required to print.');
          }
          return;
        }
      }

      final isConn = await _printerService.isConnected();
      if (!isConn) {
        final savedMac = await _printerService.getSavedPrinterMac();
        if (savedMac != null && savedMac.isNotEmpty) {
          final connected = await _printerService.connect(savedMac);
          if (!connected && mounted) {
            _openPrinterDevicePicker();
            return;
          }
        } else {
          if (mounted) {
            _openPrinterDevicePicker();
          }
          return;
        }
      }

      final success = await _printerService.printTestReceipt(paperSize: _thermalPaperSize);
      if (mounted) {
        if (success) {
          ShowMessage.success(context, 'Test ticket printed successfully (${_thermalPaperSize.code})!');
        } else {
          ShowMessage.error(context, 'Failed to send test print job to printer.');
        }
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Test print error: $e');
      }
    } finally {
      if (mounted) {
        final isConn = await _printerService.isConnected();
        setState(() {
          _isTestingPrint = false;
          _isPrinterConnected = isConn;
        });
      }
    }
  }

  Widget _buildThermalPrinterCard(ColorScheme colorScheme) {
    return Card(
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
                    color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.print_outlined, size: 22, color: Color(0xFF6366F1)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Thermal Printer Setup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Text(
                        'Paper width (58mm / 80mm) & Bluetooth connection for delivery receipts',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),

            // Paper Size Selection
            const Text(
              'Paper Roll Width *',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose your thermal printer paper roll size. Text formatting and line wrapping automatically adjust.',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThermalPaperSize>(
                segments: const [
                  ButtonSegment<ThermalPaperSize>(
                    value: ThermalPaperSize.mm58,
                    label: Text('58mm (32 cols)'),
                    icon: Icon(Icons.receipt_outlined, size: 18),
                  ),
                  ButtonSegment<ThermalPaperSize>(
                    value: ThermalPaperSize.mm80,
                    label: Text('80mm (48 cols)'),
                    icon: Icon(Icons.receipt_long_outlined, size: 18),
                  ),
                ],
                selected: {_thermalPaperSize},
                onSelectionChanged: (val) => _setThermalPaperSize(val.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
                  selectedForegroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Bluetooth Connection Status
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _isPrinterConnected
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.grey.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isPrinterConnected ? Icons.bluetooth_connected_rounded : Icons.bluetooth_rounded,
                          size: 20,
                          color: _isPrinterConnected ? Colors.green.shade700 : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _printerName != null && _printerName!.isNotEmpty
                                  ? _printerName!
                                  : 'No Printer Selected',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isPrinterConnected ? 'Connected via Bluetooth' : 'Not Connected',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _isPrinterConnected ? Colors.green.shade700 : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isPrinterConnected)
                        IconButton(
                          icon: const Icon(Icons.link_off_rounded, color: Colors.red),
                          tooltip: 'Disconnect Printer',
                          onPressed: _disconnectPrinter,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openPrinterDevicePicker,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
                          label: Text(_isPrinterConnected ? 'Change Printer' : 'Select Printer'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _isTestingPrint ? null : _testPrintReceipt,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: _isTestingPrint
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.print_rounded, size: 18),
                          label: Text(_isTestingPrint ? 'Testing...' : 'Test Print'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
                          _buildDateField(label: 'Merch Blitz End Date *', date: _endDate, onTap: _pickEndDate, icon: Icons.event_available_rounded),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // KPI Monthly Targets Card
                  _buildKpiTargetsCard(),

                  const SizedBox(height: 16),

                  // Thermal Printer Configuration Card (58mm / 80mm & Bluetooth)
                  _buildThermalPrinterCard(colorScheme),

                  const SizedBox(height: 16),

                  // App Version & Self-Update Card
                  _buildAppVersionCard(colorScheme),

                  const SizedBox(height: 28),

                  // Save Configurations Button
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _saveConfiguration,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 20),
                    label: Text(_isSaving ? 'Saving...' : 'Save Configurations', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAppVersionCard(ColorScheme colorScheme) {
    final hasRemote = _remoteVersionInfo != null && _remoteVersionInfo!.latestVersionCode > 0;
    final isNewerAvailable = hasRemote && _remoteVersionInfo!.latestVersionCode > _localBuildNumber;

    return Card(
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
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.system_update_rounded, size: 22, color: Color(0xFF10B981)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('App Updates & Releases', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Text('Sideload and distribute seamless in-app APK updates', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Installed Version:', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'v$_localVersion (Build $_localBuildNumber)',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Latest Release in Cloud:', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          hasRemote
                              ? 'v${_remoteVersionInfo!.latestVersionName} (Build ${_remoteVersionInfo!.latestVersionCode})'
                              : 'Not Configured',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isNewerAvailable ? colorScheme.primary : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => AppUpdateService.checkAndPromptUpdate(context, silent: false),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Check for Updates'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _openPublishUpdateModal,
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: const Text('Publish Release'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openPublishUpdateModal() {
    final versionNameCtrl = TextEditingController(text: _remoteVersionInfo?.latestVersionName ?? '1.0.1');
    final versionCodeCtrl = TextEditingController(
      text: (_remoteVersionInfo != null && _remoteVersionInfo!.latestVersionCode > 0)
          ? (_remoteVersionInfo!.latestVersionCode + 1).toString()
          : (_localBuildNumber + 1).toString(),
    );
    final apkUrlCtrl = TextEditingController(text: _remoteVersionInfo?.apkUrl ?? '');
    final notesCtrl = TextEditingController(text: _remoteVersionInfo?.releaseNotes ?? '');
    bool isForce = _remoteVersionInfo?.forceUpdate ?? false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Row(
                children: [
                  Icon(Icons.cloud_upload_rounded, color: Colors.blue),
                  SizedBox(width: 10),
                  Text('Publish App Release', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: versionNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Version Name (e.g. 1.0.1)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: versionCodeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Build Number (e.g. 22)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: apkUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'APK Download URL',
                          hintText: 'https://.../app-release.apk',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Release Notes / What\'s New',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mandatory Update', style: TextStyle(fontSize: 14)),
                        subtitle: const Text('Users must update before using app', style: TextStyle(fontSize: 11)),
                        value: isForce,
                        onChanged: (val) => setDialogState(() => isForce = val),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final code = int.tryParse(versionCodeCtrl.text.trim()) ?? 0;
                    final name = versionNameCtrl.text.trim();
                    final url = apkUrlCtrl.text.trim();

                    if (code <= 0 || name.isEmpty || url.isEmpty) {
                      ShowMessage.error(context, 'Please enter a valid version name, build number, and APK URL.');
                      return;
                    }

                    Navigator.of(dialogCtx).pop();

                    final newInfo = AppVersionInfo(
                      latestVersionCode: code,
                      latestVersionName: name,
                      apkUrl: url,
                      releaseNotes: notesCtrl.text.trim(),
                      forceUpdate: isForce,
                      publishedAt: DateTime.now(),
                    );

                    await AppUpdateService().saveLatestVersionInfo(newInfo);
                    if (mounted) {
                      setState(() {
                        _remoteVersionInfo = newInfo;
                      });
                      ShowMessage.success(context, 'Release v$name+$code published to Cloud Firestore!');
                    }
                  },
                  child: const Text('Publish'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
