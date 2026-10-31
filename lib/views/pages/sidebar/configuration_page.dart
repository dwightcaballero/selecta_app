import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/configuration_controller.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/models/sub_category.dart';
import 'package:selecta_ops/services/sms_gateway_service.dart';
import 'package:selecta_ops/services/thermal_printer_service.dart';
import 'package:selecta_ops/views/pages/sidebar/admin_promos_page.dart';
import 'package:selecta_ops/views/pages/sidebar/product_sorting_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:selecta_ops/views/widgets/digital_receipt_dialog.dart';
import 'package:selecta_ops/views/widgets/full_screen_location_picker_dialog.dart';

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

  bool _enablePicklistBarcodeScanner = true;

  // State for Product Sorting & Sub-Categories
  String _productSortMode = 'srp';
  List<SubCategory> _subCategories = [];
  int _selectedSubCategoryCategoryIndex = 0; // 0 = By Piece, 1 = By Case

  ThermalPaperSize _thermalPaperSize = ThermalPaperSize.mm58;
  String? _printerName;
  bool _isPrinterConnected = false;
  bool _isTestingPrint = false;

  late final TextEditingController _salesTargetController;
  late final TextEditingController _throughputTargetController;
  late final TextEditingController _expansionTargetController;
  late final TextEditingController _creditSmsTemplateController;
  late final TextEditingController _smsGatewayUrlController;
  late final TextEditingController _smsGatewayTokenController;
  late final TextEditingController _depotAddressController;
  late final TextEditingController _depotRadiusController;
  late final TextEditingController _depotLatitudeController;
  late final TextEditingController _depotLongitudeController;

  // State for collapsible cards
  bool _isMerchBlitzExpanded = false;
  bool _isKpiTargetsExpanded = false;
  bool _isCreditSmsExpanded = false;
  bool _isSmsGatewayExpanded = false;
  bool _isWarehouseExpanded = false;
  bool _isPrinterExpanded = false;
  bool _isProductSortExpanded = false;
  bool _isPromosExpanded = false;
  bool _isAttendanceExpanded = false;

  // Attendance & Depot Geofence settings
  bool _attendanceEnabled = true;
  bool _isCapturingDepotGps = false;

  // SMS Gateway settings
  bool _smsGatewayEnabled = true;
  int _smsGatewaySimSlot = 1;
  bool _isTestingGateway = false;
  String? _gatewayHealthMessage;
  bool? _isGatewayOnline;

  bool get _allExpanded =>
      _isMerchBlitzExpanded &&
      _isKpiTargetsExpanded &&
      _isCreditSmsExpanded &&
      _isSmsGatewayExpanded &&
      _isWarehouseExpanded &&
      _isPrinterExpanded &&
      _isProductSortExpanded &&
      _isPromosExpanded &&
      _isAttendanceExpanded;

  void _toggleAllSections() {
    final shouldExpand = !_allExpanded;
    setState(() {
      _isMerchBlitzExpanded = shouldExpand;
      _isKpiTargetsExpanded = shouldExpand;
      _isCreditSmsExpanded = shouldExpand;
      _isSmsGatewayExpanded = shouldExpand;
      _isWarehouseExpanded = shouldExpand;
      _isPrinterExpanded = shouldExpand;
      _isProductSortExpanded = shouldExpand;
      _isPromosExpanded = shouldExpand;
      _isAttendanceExpanded = shouldExpand;
    });
  }

  @override
  void initState() {
    super.initState();
    _salesTargetController = TextEditingController(text: '1000000');
    _salesTargetController.addListener(() {
      if (mounted) setState(() {});
    });
    _throughputTargetController = TextEditingController(text: '8000');
    _expansionTargetController = TextEditingController(text: '10');
    _creditSmsTemplateController = TextEditingController(text: Configuration.defaultCreditReminderSmsTemplate);
    _creditSmsTemplateController.addListener(() {
      if (mounted) setState(() {});
    });
    _smsGatewayUrlController = TextEditingController();
    _smsGatewayUrlController.addListener(() {
      if (mounted) setState(() {});
    });
    _smsGatewayTokenController = TextEditingController();
    _depotAddressController = TextEditingController();
    _depotRadiusController = TextEditingController(text: '300');
    _depotLatitudeController = TextEditingController();
    _depotLongitudeController = TextEditingController();
    _loadConfiguration();
  }

  @override
  void dispose() {
    _salesTargetController.dispose();
    _throughputTargetController.dispose();
    _expansionTargetController.dispose();
    _creditSmsTemplateController.dispose();
    _smsGatewayUrlController.dispose();
    _smsGatewayTokenController.dispose();
    _depotAddressController.dispose();
    _depotRadiusController.dispose();
    _depotLatitudeController.dispose();
    _depotLongitudeController.dispose();
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
          _creditSmsTemplateController.text = result.config.creditReminderSmsTemplate;
          _enablePicklistBarcodeScanner = result.config.enablePicklistBarcodeScanner;
          _productSortMode = result.config.productSortMode;
          _subCategories = List<SubCategory>.from(result.config.subCategories);
          _thermalPaperSize = paperSize;
          _printerName = pName;
          _isPrinterConnected = isConnected;
          _smsGatewayEnabled = result.config.smsGatewayEnabled;
          _smsGatewayUrlController.text = result.config.smsGatewayUrl;
          _smsGatewayTokenController.text = result.config.smsGatewayToken;
          _smsGatewaySimSlot = result.config.smsGatewaySimSlot;
          _attendanceEnabled = result.config.attendanceEnabled;
          _depotAddressController.text = result.config.depotAddress;
          _depotRadiusController.text = result.config.depotRadiusMeters.toStringAsFixed(0);
          _depotLatitudeController.text = result.config.depotLatitude != null ? result.config.depotLatitude.toString() : '';
          _depotLongitudeController.text = result.config.depotLongitude != null ? result.config.depotLongitude.toString() : '';
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
    if (_isSaving) return;
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

    final smsTemplate = _creditSmsTemplateController.text.trim();
    if (smsTemplate.isEmpty) {
      ShowMessage.error(context, 'Credit SMS reminder template cannot be empty.');
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
        enablePicklistBarcodeScanner: _enablePicklistBarcodeScanner,
        creditReminderSmsTemplate: smsTemplate,
        productSortMode: _productSortMode,
        subCategories: _subCategories,
        smsGatewayEnabled: _smsGatewayEnabled,
        smsGatewayUrl: _smsGatewayUrlController.text.trim(),
        smsGatewayToken: _smsGatewayTokenController.text.trim(),
        smsGatewaySimSlot: _smsGatewaySimSlot,
        attendanceEnabled: _attendanceEnabled,
        depotLatitude: double.tryParse(_depotLatitudeController.text.trim()),
        depotLongitude: double.tryParse(_depotLongitudeController.text.trim()),
        depotRadiusMeters: double.tryParse(_depotRadiusController.text.trim()) ?? 300.0,
        depotAddress: _depotAddressController.text.trim(),
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

  /// Generic reusable container for collapsible configuration sections
  Widget _buildCollapsibleSectionCard({
    required bool isExpanded,
    required VoidCallback onToggle,
    required Color iconColor,
    required IconData icon,
    required String title,
    required String subtitle,
    String? badgeText,
    Color? badgeColor,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 22, color: iconColor),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (badgeText != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: badgeColor?.withValues(alpha: 0.12) ?? colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: badgeColor?.withValues(alpha: 0.3) ?? colorScheme.outlineVariant.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Text(
                                  badgeText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: badgeColor ?? colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  ...children,
                ],
              ),
            ),
            crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildMerchBlitzCard() {
    final dateRangeStr =
        '${DateFormat('MMM d').format(_startDate)} – ${DateFormat('MMM d').format(_endDate)}';

    return _buildCollapsibleSectionCard(
      isExpanded: _isMerchBlitzExpanded,
      onToggle: () => setState(() => _isMerchBlitzExpanded = !_isMerchBlitzExpanded),
      icon: Icons.campaign_outlined,
      iconColor: const Color(0xFF0284C7),
      title: 'Merch Blitz Schedule',
      subtitle: 'Configure campaign duration for store merchandising',
      badgeText: dateRangeStr,
      badgeColor: const Color(0xFF0284C7),
      children: [
        _buildDateField(
          label: 'Merch Blitz Start Date *',
          date: _startDate,
          onTap: _pickStartDate,
          icon: Icons.calendar_today_rounded,
        ),
        const SizedBox(height: 14),
        _buildDateField(
          label: 'Merch Blitz End Date *',
          date: _endDate,
          onTap: _pickEndDate,
          icon: Icons.event_available_rounded,
        ),
      ],
    );
  }

  Widget _buildKpiTargetsCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final salesTargetStr = _salesTargetController.text.isNotEmpty ? '₱${_salesTargetController.text}' : 'Target';

    return _buildCollapsibleSectionCard(
      isExpanded: _isKpiTargetsExpanded,
      onToggle: () => setState(() => _isKpiTargetsExpanded = !_isKpiTargetsExpanded),
      icon: Icons.track_changes_rounded,
      iconColor: const Color(0xFF6366F1),
      title: 'KPI Monthly Targets',
      subtitle: 'Set monthly operational goals and performance benchmarks',
      badgeText: salesTargetStr,
      badgeColor: const Color(0xFF6366F1),
      children: [
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

  void _insertSmsPlaceholder(String token) {
    final text = _creditSmsTemplateController.text;
    final selection = _creditSmsTemplateController.selection;
    if (selection.start >= 0 && selection.end >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, token);
      _creditSmsTemplateController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + token.length),
      );
    } else {
      _creditSmsTemplateController.text = '$text $token';
    }
  }

  Widget _buildPlaceholderChip(String token, String label, ColorScheme colorScheme) {
    return ActionChip(
      avatar: const Icon(Icons.add_rounded, size: 14),
      label: Text('$token ($label)'),
      labelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
      onPressed: () => _insertSmsPlaceholder(token),
    );
  }

  Widget _buildCreditReminderSmsCard(ColorScheme colorScheme) {
    final currentText = _creditSmsTemplateController.text;
    final charCount = currentText.length;
    final segmentCount = (charCount == 0) ? 1 : ((charCount - 1) ~/ 153) + 1;

    final sampleDateStr = DateFormat('MMM d, yyyy').format(DateTime.now().subtract(const Duration(days: 7)));
    final previewText = currentText
        .replaceAll('{storeName}', 'ALENG TINDERA STORE')
        .replaceAll('{creditAmount}', '₱4,850.00')
        .replaceAll('{creditDate}', sampleDateStr)
        .replaceAll('{daysOverdue}', '7');

    return _buildCollapsibleSectionCard(
      isExpanded: _isCreditSmsExpanded,
      onToggle: () => setState(() => _isCreditSmsExpanded = !_isCreditSmsExpanded),
      icon: Icons.sms_rounded,
      iconColor: const Color(0xFFF97316),
      title: 'Credit Reminder SMS',
      subtitle: 'Preconfigured text message for following up on overdue credit balances',
      badgeText: '$charCount chars',
      badgeColor: const Color(0xFFF97316),
      children: [
        Text(
          'Dynamic Placeholders (Tap to insert):',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _buildPlaceholderChip('{storeName}', 'Store Name', colorScheme),
            _buildPlaceholderChip('{creditAmount}', 'Credit Amount', colorScheme),
            _buildPlaceholderChip('{creditDate}', 'Credit Date', colorScheme),
            _buildPlaceholderChip('{daysOverdue}', 'Days Overdue', colorScheme),
          ],
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _creditSmsTemplateController,
          maxLines: 4,
          minLines: 3,
          style: const TextStyle(fontSize: 13.5, height: 1.4),
          decoration: InputDecoration(
            alignLabelWithHint: true,
            labelText: 'Message Template *',
            hintText: 'Enter credit reminder SMS message template...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$charCount chars • ~$segmentCount SMS segment${segmentCount > 1 ? 's' : ''}',
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _creditSmsTemplateController.text = Configuration.defaultCreditReminderSmsTemplate;
                });
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: const Text('Reset to Default', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Live Preview Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.visibility_outlined, size: 14, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Live Customer SMS Preview',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                    bottomLeft: Radius.circular(2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  previewText,
                  style: const TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _testSmsGatewayConnection() async {
    setState(() {
      _isTestingGateway = true;
      _gatewayHealthMessage = null;
      _isGatewayOnline = null;
    });

    try {
      final result = await SmsGatewayService().checkHealth();
      if (!mounted) return;
      setState(() {
        _isTestingGateway = false;
        _isGatewayOnline = result.isOnline;
        _gatewayHealthMessage = result.isOnline
            ? 'Online (${result.latencyMs ?? 0}ms) • ${result.status}'
            : result.status;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTestingGateway = false;
        _isGatewayOnline = false;
        _gatewayHealthMessage = 'Check failed: $e';
      });
    }
  }

  Widget _buildSmsGatewayCard(ColorScheme colorScheme) {
    final isConfigured = _smsGatewayUrlController.text.trim().isNotEmpty;
    final badgeText = !_smsGatewayEnabled
        ? 'Disabled'
        : (isConfigured ? 'Configured' : 'Unconfigured');
    final badgeColor = !_smsGatewayEnabled
        ? Colors.grey
        : (isConfigured ? const Color(0xFF10B981) : Colors.orange);

    return _buildCollapsibleSectionCard(
      isExpanded: _isSmsGatewayExpanded,
      onToggle: () => setState(() => _isSmsGatewayExpanded = !_isSmsGatewayExpanded),
      icon: Icons.cell_tower_rounded,
      iconColor: const Color(0xFF0D9488),
      title: 'Office SMS Gateway',
      subtitle: 'Dispatch SMS via spare Android phone with unlimited SIM promo',
      badgeText: badgeText,
      badgeColor: badgeColor,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable Office SMS Gateway', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: const Text('When disabled, the app falls back to the device\'s native SMS messenger.', style: TextStyle(fontSize: 12)),
          value: _smsGatewayEnabled,
          onChanged: (val) => setState(() => _smsGatewayEnabled = val),
        ),
        const SizedBox(height: 8),

        // Info Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D9488).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.2)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_outlined, size: 18, color: Color(0xFF0D9488)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '100% Google Play Compliant. Selecta Ops makes a secure Cloud Function call instead of requesting restricted SMS permissions on salesmen devices.',
                  style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF0F766E)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Gateway URL
        TextField(
          controller: _smsGatewayUrlController,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Gateway Phone URL *',
            hintText: 'https://sms-gateway.yourcompany.org/message or http://192.168.1.120:8080',
            prefixIcon: const Icon(Icons.link_rounded, size: 20),
            helperText: 'Endpoint of android-sms-gateway app (via Cloudflare Tunnel, Cloud Relay, or LAN)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
        const SizedBox(height: 14),

        // Auth Token / Credentials
        TextField(
          controller: _smsGatewayTokenController,
          decoration: InputDecoration(
            labelText: 'API Token / Basic Auth (Optional)',
            hintText: 'selecta_gateway:YourPassword or BearerToken',
            prefixIcon: const Icon(Icons.key_rounded, size: 20),
            helperText: 'Basic Auth credentials (username:password) or API token configured in gateway app',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
        const SizedBox(height: 14),

        // SIM Slot Selector
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _smsGatewaySimSlot,
                decoration: InputDecoration(
                  labelText: 'Default SIM Slot',
                  prefixIcon: const Icon(Icons.sim_card_outlined, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('SIM Slot 1 (Primary)')),
                  DropdownMenuItem(value: 2, child: Text('SIM Slot 2 (Secondary)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _smsGatewaySimSlot = val);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Test Connection Button & Status Feedback
        Row(
          children: [
            AsyncOutlinedButton.icon(
              onPressed: _testSmsGatewayConnection,
              loadingLabel: 'Pinging...',
              icon: const Icon(Icons.network_ping_rounded, size: 16),
              label: const Text('Test Connection', style: TextStyle(fontSize: 12.5)),
            ),
            const SizedBox(width: 12),
            if (_isTestingGateway)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (_isGatewayOnline != null)
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      _isGatewayOnline == true ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 16,
                      color: _isGatewayOnline == true ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _gatewayHealthMessage ?? '',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _isGatewayOnline == true ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildWarehouseBarcodeCard(ColorScheme colorScheme) {
    return _buildCollapsibleSectionCard(
      isExpanded: _isWarehouseExpanded,
      onToggle: () => setState(() => _isWarehouseExpanded = !_isWarehouseExpanded),
      icon: Icons.qr_code_scanner_rounded,
      iconColor: const Color(0xFF0284C7),
      title: 'Warehouse & Picking',
      subtitle: 'Barcode verification settings for delivery picklist preparation',
      badgeText: _enablePicklistBarcodeScanner ? 'Active' : 'Disabled',
      badgeColor: _enablePicklistBarcodeScanner ? const Color(0xFF10B981) : Colors.grey,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Picklist Barcode Verification', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: const Text(
            'Require scanning outer carton / tub barcodes or checking items to prevent picking incorrect products.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          value: _enablePicklistBarcodeScanner,
          activeTrackColor: const Color(0xFF0284C7),
          onChanged: (val) {
            setState(() {
              _enablePicklistBarcodeScanner = val;
            });
          },
        ),
      ],
    );
  }

  Future<void> _captureCurrentGpsForDepot() async {
    setState(() => _isCapturingDepotGps = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) ShowMessage.error(context, 'Location services are disabled.');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) ShowMessage.error(context, 'Location permissions are denied.');
          return;
        }
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _depotLatitudeController.text = pos.latitude.toStringAsFixed(6);
          _depotLongitudeController.text = pos.longitude.toStringAsFixed(6);
        });
        ShowMessage.success(context, 'Depot coordinates set to current location.');
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Could not retrieve GPS: $e');
    } finally {
      if (mounted) setState(() => _isCapturingDepotGps = false);
    }
  }

  Future<void> _pickDepotLocationOnMap() async {
    final currentLat = double.tryParse(_depotLatitudeController.text.trim()) ?? 14.5995;
    final currentLng = double.tryParse(_depotLongitudeController.text.trim()) ?? 120.9842;

    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (ctx) => FullScreenLocationPickerDialog(
          initialLocation: LatLng(currentLat, currentLng),
        ),
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        _depotLatitudeController.text = picked.latitude.toStringAsFixed(6);
        _depotLongitudeController.text = picked.longitude.toStringAsFixed(6);
      });
    }
  }

  Widget _buildAttendanceDepotCard(ColorScheme colorScheme) {
    final hasCoords = _depotLatitudeController.text.isNotEmpty && _depotLongitudeController.text.isNotEmpty;
    final badgeText = !_attendanceEnabled
        ? 'Disabled'
        : hasCoords
            ? '${_depotRadiusController.text}m Geofence'
            : 'No GPS Set';
    final badgeColor = !_attendanceEnabled
        ? Colors.grey
        : hasCoords
            ? const Color(0xFF10B981)
            : const Color(0xFFF59E0B);

    return _buildCollapsibleSectionCard(
      isExpanded: _isAttendanceExpanded,
      onToggle: () => setState(() => _isAttendanceExpanded = !_isAttendanceExpanded),
      icon: Icons.access_time_filled_rounded,
      iconColor: const Color(0xFF3B82F6),
      title: 'Time & Attendance (Depot Geofence)',
      subtitle: 'Depot location, GPS radius check, and mandatory salesman clock-in',
      badgeText: badgeText,
      badgeColor: badgeColor,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Require Salesman Attendance', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: const Text(
            'Force salesmen to clock in upon morning app open and clock out before End of Day cash breakdown.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          value: _attendanceEnabled,
          activeTrackColor: const Color(0xFF3B82F6),
          onChanged: (val) => setState(() => _attendanceEnabled = val),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _depotAddressController,
          decoration: InputDecoration(
            labelText: 'Depot Name / Address',
            hintText: 'e.g. Main Warehouse, Barangay San Jose',
            prefixIcon: const Icon(Icons.warehouse_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _depotLatitudeController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: 'Depot Latitude',
                  prefixIcon: const Icon(Icons.my_location, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _depotLongitudeController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: 'Depot Longitude',
                  prefixIcon: const Icon(Icons.location_searching, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _depotRadiusController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Geofence Radius (meters)',
            helperText: 'Clock-ins outside this radius will be flagged as "Off-Site"',
            prefixIcon: const Icon(Icons.radar, size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isCapturingDepotGps ? null : _captureCurrentGpsForDepot,
                icon: _isCapturingDepotGps
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.gps_fixed, size: 16),
                label: const Text('Use Current GPS'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDepotLocationOnMap,
                icon: const Icon(Icons.map, size: 16),
                label: const Text('Pick on Map'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildThermalPrinterCard(ColorScheme colorScheme) {
    final statusText = _isPrinterConnected ? 'Connected' : 'Offline';
    final badgeText = '${_thermalPaperSize.code} • $statusText';

    return _buildCollapsibleSectionCard(
      isExpanded: _isPrinterExpanded,
      onToggle: () => setState(() => _isPrinterExpanded = !_isPrinterExpanded),
      icon: Icons.print_outlined,
      iconColor: const Color(0xFF6366F1),
      title: 'Thermal Printer Setup',
      subtitle: 'Paper width (58mm / 80mm) & Bluetooth connection for delivery receipts',
      badgeText: badgeText,
      badgeColor: _isPrinterConnected ? const Color(0xFF10B981) : const Color(0xFF6366F1),
      children: [
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
    );
  }

  void _showAddSubCategoryDialog(String category) {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add $category Sub-Category'),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Sub-Category Name',
            hintText: 'e.g., Cones, Tubs, Sticks...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = textCtrl.text.trim();
              if (name.isNotEmpty) {
                final isCase = category.toLowerCase().contains('case');
                final catName = isCase ? 'By Case' : 'By Piece';
                final existing = _subCategories
                    .where((s) => s.category.toLowerCase().contains(isCase ? 'case' : 'piece'))
                    .toList();
                final maxOrder = existing.isEmpty
                    ? -1
                    : existing.map((s) => s.order).reduce((a, b) => a > b ? a : b);
                setState(() {
                  _subCategories.add(SubCategory(
                    id: 'sub_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    category: catName,
                    order: maxOrder + 1,
                    isActive: true,
                  ));
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showRenameSubCategoryDialog(SubCategory sub) {
    final textCtrl = TextEditingController(text: sub.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Sub-Category'),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = textCtrl.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  final idx = _subCategories.indexWhere((s) => s.id == sub.id);
                  if (idx != -1) {
                    _subCategories[idx] = _subCategories[idx].copyWith(name: name);
                  }
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSubCategory(SubCategory sub) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Sub-Category?'),
        content: Text(
          'Are you sure you want to delete "${sub.name}"?\n\n'
          'Products assigned to this sub-category will become Unassigned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                _subCategories.removeWhere((s) => s.id == sub.id);
              });
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildProductSortingCard(ColorScheme colorScheme) {
    final isCustom = _productSortMode == 'custom';
    final currentCat = _selectedSubCategoryCategoryIndex == 0 ? 'By Piece' : 'By Case';
    final forCat = _subCategories
        .where((s) => s.category.toLowerCase().contains(
              _selectedSubCategoryCategoryIndex == 0 ? 'piece' : 'case',
            ))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    return _buildCollapsibleSectionCard(
      isExpanded: _isProductSortExpanded,
      onToggle: () => setState(() => _isProductSortExpanded = !_isProductSortExpanded),
      iconColor: Colors.deepPurple,
      icon: Icons.sort_rounded,
      title: 'Product Sorting & Sub-Categories',
      subtitle: 'Sequence products across book orders, loads, receipts & reports',
      badgeText: isCustom ? 'Custom Sort' : 'Default (SRP)',
      badgeColor: isCustom ? Colors.deepPurple : colorScheme.onSurfaceVariant,
      children: [
        // Mode Selector: SRP vs Custom
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SORTING MODE',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _productSortMode,
                onChanged: (val) {
                  if (val != null) setState(() => _productSortMode = val);
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      value: 'srp',
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: Colors.deepPurple,
                      title: const Text('Default (by SRP then Name)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: const Text('Products sorted by descending Suggested Retail Price, then alphabetically.', style: TextStyle(fontSize: 11)),
                    ),
                    const Divider(height: 1),
                    RadioListTile<String>(
                      value: 'custom',
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: Colors.deepPurple,
                      title: const Text('Custom Dealer Sort', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: const Text('Grouped by sub-categories with custom dealer drag-and-drop sequencing.', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Quick Link to Full Drag-and-Drop Page
        FilledButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductSortingPage(
                  initialTabIndex: _selectedSubCategoryCategoryIndex,
                ),
              ),
            ).then((_) => _loadConfiguration());
          },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.sort_rounded, size: 20),
          label: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Open Product Sorting Page', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(width: 6),
              Icon(Icons.arrow_forward_rounded, size: 16),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Sub-Categories Manager
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SUB-CATEGORIES',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
            ),
            OutlinedButton.icon(
              onPressed: () => _showAddSubCategoryDialog(currentCat),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: Text('Add $currentCat Sub-Category', style: const TextStyle(fontSize: 11)),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // Segmented Control for By Piece vs By Case
        SegmentedButton<int>(
          segments: const [
            ButtonSegment<int>(value: 0, label: Text('By Piece'), icon: Icon(Icons.icecream_outlined, size: 16)),
            ButtonSegment<int>(value: 1, label: Text('By Case'), icon: Icon(Icons.inventory_2_outlined, size: 16)),
          ],
          selected: {_selectedSubCategoryCategoryIndex},
          onSelectionChanged: (val) {
            setState(() => _selectedSubCategoryCategoryIndex = val.first);
          },
        ),

        const SizedBox(height: 12),

        if (forCat.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'No sub-categories defined for $currentCat yet.',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: forCat.length,
            separatorBuilder: (context, index) => Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            itemBuilder: (context, idx) {
              final sub = forCat[idx];

              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                leading: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${idx + 1}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                ),
                title: Text(
                  sub.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: sub.isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                  ),
                ),
                subtitle: Text(
                  sub.isActive ? 'Active' : 'Inactive',
                  style: TextStyle(fontSize: 11, color: sub.isActive ? Colors.green.shade700 : Colors.grey),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: sub.isActive,
                      onChanged: (val) {
                        setState(() {
                          final mIdx = _subCategories.indexWhere((s) => s.id == sub.id);
                          if (mIdx != -1) {
                            _subCategories[mIdx] = _subCategories[mIdx].copyWith(isActive: val);
                          }
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'Rename',
                      onPressed: () => _showRenameSubCategoryDialog(sub),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      tooltip: 'Delete',
                      onPressed: () => _confirmDeleteSubCategory(sub),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildPromotionsCard(ColorScheme colorScheme) {
    return _buildCollapsibleSectionCard(
      isExpanded: _isPromosExpanded,
      onToggle: () => setState(() => _isPromosExpanded = !_isPromosExpanded),
      icon: Icons.local_offer_outlined,
      iconColor: const Color(0xFFE11D48),
      title: 'Promotions & Bundles',
      subtitle: 'Manage promo mechanics, bundle discounts, and freebies',
      badgeText: 'Pricing & Promos',
      badgeColor: const Color(0xFFE11D48),
      children: [
        Text(
          'Configure store promos, product discounts, bundle sets, and free items offered to retail stores during booking and sales.',
          style: TextStyle(
            fontSize: 12.5,
            color: colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminPromosPage()),
            );
          },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            backgroundColor: const Color(0xFFE11D48),
          ),
          icon: const Icon(Icons.local_offer_rounded, size: 18),
          label: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Manage Promotions & Bundles', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(width: 6),
              Icon(Icons.arrow_forward_rounded, size: 16),
            ],
          ),
        ),
      ],
    );
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
        appBar: CustomAppbar(
          title: 'Configurations',
          subtitle: 'App & Campaign Settings',
          actions: [
            IconButton(
              onPressed: _toggleAllSections,
              icon: Icon(_allExpanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded),
              tooltip: _allExpanded ? 'Collapse All' : 'Expand All',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'CONFIGURATION SECTIONS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _toggleAllSections,
                            icon: Icon(_allExpanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded, size: 16),
                            label: Text(_allExpanded ? 'Collapse All' : 'Expand All', style: const TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Merch Blitz Settings Card
                    _buildMerchBlitzCard(),

                    const SizedBox(height: 12),

                    // KPI Monthly Targets Card
                    _buildKpiTargetsCard(),

                    const SizedBox(height: 12),

                    // Credit Overdue SMS Reminder Card
                    _buildCreditReminderSmsCard(colorScheme),

                    const SizedBox(height: 12),

                    // Office SMS Gateway Relay Card
                    _buildSmsGatewayCard(colorScheme),

                    const SizedBox(height: 12),

                    // Warehouse Picklist Verification Card
                    _buildWarehouseBarcodeCard(colorScheme),

                    const SizedBox(height: 12),

                    // Time & Attendance Depot Geofence Card
                    _buildAttendanceDepotCard(colorScheme),

                    const SizedBox(height: 12),

                    // Thermal Printer Configuration Card (58mm / 80mm & Bluetooth)
                    _buildThermalPrinterCard(colorScheme),

                    const SizedBox(height: 12),

                    // Product Sorting & Sub-Categories Card
                    _buildProductSortingCard(colorScheme),

                    const SizedBox(height: 12),

                    // Promotions & Bundles Card
                    _buildPromotionsCard(colorScheme),

                    const SizedBox(height: 24),

                    // Save Configurations Button
                    AsyncFilledButton.icon(
                      onPressed: _saveConfiguration,
                      loadingLabel: 'Saving...',
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.save_rounded, size: 20),
                      label: const Text('Save Configurations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
