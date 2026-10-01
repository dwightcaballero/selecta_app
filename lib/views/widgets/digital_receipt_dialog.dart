import 'package:flutter/material.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/thermal_printer_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// Modal dialog displaying a text-only digital receipt with actions to print
/// via Bluetooth thermal printer, copy text to clipboard, or configure printer settings.
class DigitalReceiptDialog extends StatefulWidget {
  final Delivery delivery;
  final String deliveryId;
  final String? dealerName;
  final VoidCallback? onProceed;
  final String proceedLabel;

  const DigitalReceiptDialog({
    super.key,
    required this.delivery,
    required this.deliveryId,
    this.dealerName,
    this.onProceed,
    this.proceedLabel = 'Close',
  });

  /// Static helper to display the receipt dialog easily from any page.
  static Future<void> show(
    BuildContext context, {
    required Delivery delivery,
    required String deliveryId,
    String? dealerName,
    VoidCallback? onProceed,
    String proceedLabel = 'Close',
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          DigitalReceiptDialog(delivery: delivery, deliveryId: deliveryId, dealerName: dealerName, onProceed: onProceed, proceedLabel: proceedLabel),
    );
  }

  @override
  State<DigitalReceiptDialog> createState() => _DigitalReceiptDialogState();
}

class _DigitalReceiptDialogState extends State<DigitalReceiptDialog> {
  final ThermalPrinterService _printerService = ThermalPrinterService();

  ThermalPaperSize _paperSize = ThermalPaperSize.mm58;
  String _effectiveDealerName = '';
  String _receiptText = '';
  bool _isLoading = true;
  bool _isPrinting = false;
  bool _isConnected = false;
  String? _printerName;
  final TransformationController _transController = TransformationController();
  double _fontScale = 1.0;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _transController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      _paperSize = await _printerService.getPaperSize();
      _printerName = await _printerService.getSavedPrinterName();
      _isConnected = await _printerService.isConnected();

      if (widget.dealerName != null && widget.dealerName!.trim().isNotEmpty) {
        _effectiveDealerName = widget.dealerName!.trim();
      } else {
        final user = await KVariables.getUser();
        _effectiveDealerName = user?.dealerName.trim() ?? '';
      }

      _generateReceipt();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _generateReceipt() {
    _receiptText = _printerService.generateTextReceipt(
      delivery: widget.delivery,
      dealerName: _effectiveDealerName,
      deliveryId: widget.deliveryId,
      paperSize: _paperSize,
    );
  }

  Future<void> _changePaperSize(ThermalPaperSize newSize) async {
    setState(() {
      _paperSize = newSize;
      _generateReceipt();
      _transController.value = Matrix4.identity();
    });
    await _printerService.setPaperSize(newSize);
  }

  Future<void> _handlePrint() async {
    if (_isPrinting) return;
    setState(() => _isPrinting = true);

    try {
      final isEnabled = await _printerService.isBluetoothEnabled();
      if (!isEnabled) {
        if (mounted) {
          ShowMessage.error(context, 'Bluetooth is turned off. Please turn on Bluetooth to connect to your thermal printer.');
        }
        return;
      }

      final isConn = await _printerService.isConnected();
      if (!isConn) {
        final savedMac = await _printerService.getSavedPrinterMac();
        if (savedMac != null && savedMac.isNotEmpty) {
          final connected = await _printerService.connect(savedMac);
          if (!connected && mounted) {
            _showDeviceSelectorModal();
            return;
          }
        } else {
          if (mounted) {
            _showDeviceSelectorModal();
          }
          return;
        }
      }

      final success = await _printerService.printReceipt(
        delivery: widget.delivery,
        dealerName: _effectiveDealerName,
        deliveryId: widget.deliveryId,
        paperSize: _paperSize,
      );

      if (mounted) {
        if (success) {
          ShowMessage.success(context, 'Receipt printed successfully on $_paperSize printer!');
        } else {
          ShowMessage.error(context, 'Failed to send print job to thermal printer.');
        }
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Printing failed: $e');
      }
    } finally {
      if (mounted) {
        final status = await _printerService.isConnected();
        setState(() {
          _isPrinting = false;
          _isConnected = status;
        });
      }
    }
  }

  void _showDeviceSelectorModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => PrinterDevicePickerSheet(
        onConnected: (name) {
          setState(() {
            _printerName = name;
            _isConnected = true;
          });
          Navigator.pop(ctx);
          _handlePrint();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top Header ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFF0284C7).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF0284C7), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Digital Receipt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        SizedBox(height: 2),
                        Text('Text-only receipt for thermal printing', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.bluetooth_searching_rounded),
                    tooltip: 'Select Thermal Printer',
                    onPressed: _showDeviceSelectorModal,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onProceed?.call();
                    },
                  ),
                ],
              ),
            ),

            // ── Paper Width & Font Zoom Bar ─────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    // Paper size toggle
                    SegmentedButton<ThermalPaperSize>(
                      segments: const [
                        ButtonSegment<ThermalPaperSize>(
                          value: ThermalPaperSize.mm58,
                          label: Text('58mm', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        ButtonSegment<ThermalPaperSize>(
                          value: ThermalPaperSize.mm80,
                          label: Text('80mm', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                      selected: {_paperSize},
                      onSelectionChanged: (val) => _changePaperSize(val.first),
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Font Zoom Controls (A- / A+)
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Decrease font size',
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 32),
                            icon: const Icon(Icons.remove_rounded, size: 16),
                            onPressed: _fontScale > 0.85 ? () => setState(() => _fontScale = (_fontScale - 0.15).clamp(0.85, 2.2)) : null,
                          ),
                          InkWell(
                            onTap: () => setState(() => _fontScale = 1.0),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                              child: Text('${(_fontScale * 100).round()}%', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Increase font size',
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 32),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            onPressed: _fontScale < 2.1 ? () => setState(() => _fontScale = (_fontScale + 0.15).clamp(0.85, 2.2)) : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Scrollable Monospace Thermal Paper Preview with Pinch-to-Zoom ──
            Flexible(
              child: _isLoading
                  ? const Center(
                      child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
                    )
                  : Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF9F6), // Warm paper white
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: GestureDetector(
                          onDoubleTap: () {
                            setState(() {
                              if (_transController.value != Matrix4.identity()) {
                                _transController.value = Matrix4.identity();
                              } else {
                                _transController.value = Matrix4.diagonal3Values(2.0, 2.0, 1.0);
                              }
                            });
                          },
                          child: InteractiveViewer(
                            transformationController: _transController,
                            minScale: 1.0,
                            maxScale: 3.5,
                            boundaryMargin: const EdgeInsets.all(40),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(14),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SelectableText(
                                  _receiptText,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: (_paperSize == ThermalPaperSize.mm80 ? 11.0 : 12.5) * _fontScale,
                                    height: 1.35,
                                    color: const Color(0xFF1E293B),
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),

            // ── Action Buttons ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isPrinting ? null : _handlePrint,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: _isPrinting
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.print_rounded, size: 20),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _isPrinting ? 'Printing Receipt...' : 'Print Thermal Receipt',
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _showDeviceSelectorModal,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 48,
                          constraints: const BoxConstraints(maxWidth: 135),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: _isConnected ? Colors.green.withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _isConnected ? Colors.green.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.print_rounded, size: 16, color: _isConnected ? Colors.green.shade700 : Colors.grey.shade700),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _isConnected ? (_printerName ?? 'Connected') : 'No Printer',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _isConnected ? Colors.green.shade800 : Colors.grey.shade700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onProceed?.call();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF15803D),
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(widget.proceedLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet allowing user to scan, select, and connect to a Bluetooth thermal printer.
class PrinterDevicePickerSheet extends StatefulWidget {
  final void Function(String name) onConnected;

  const PrinterDevicePickerSheet({super.key, required this.onConnected});

  @override
  State<PrinterDevicePickerSheet> createState() => _PrinterDevicePickerSheetState();
}

class _PrinterDevicePickerSheetState extends State<PrinterDevicePickerSheet> {
  final ThermalPrinterService _service = ThermalPrinterService();
  List<BluetoothInfo> _devices = [];
  bool _isLoading = true;
  bool _isBluetoothOn = true;
  bool _hasPermission = true;
  bool _isPermanentlyDenied = false;
  String? _connectingMac;

  @override
  void initState() {
    super.initState();
    _scanDevices();
  }

  Future<void> _scanDevices() async {
    setState(() => _isLoading = true);

    // 1. Check & request Bluetooth permissions
    final hasPerm = await _service.checkBluetoothPermissions();
    if (!hasPerm) {
      final granted = await _service.requestBluetoothPermissions();
      if (!granted) {
        final permDenied = await _service.isPermissionPermanentlyDenied();
        if (mounted) {
          setState(() {
            _hasPermission = false;
            _isPermanentlyDenied = permDenied;
            _isLoading = false;
            _devices = [];
          });
        }
        return;
      }
    }

    // 2. Check if Bluetooth is turned on
    final isEnabled = await _service.isBluetoothEnabled();
    if (!isEnabled) {
      if (mounted) {
        setState(() {
          _isBluetoothOn = false;
          _hasPermission = true;
          _isLoading = false;
          _devices = [];
        });
      }
      return;
    }

    // 3. Retrieve paired devices
    final devices = await _service.getPairedDevices();
    if (mounted) {
      setState(() {
        _devices = devices;
        _hasPermission = true;
        _isBluetoothOn = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _handlePermissionAction() async {
    if (_isPermanentlyDenied) {
      await openAppSettings();
    } else {
      final granted = await _service.requestBluetoothPermissions();
      if (granted) {
        _scanDevices();
      } else {
        final permDenied = await _service.isPermissionPermanentlyDenied();
        if (mounted) {
          setState(() => _isPermanentlyDenied = permDenied);
        }
        if (permDenied) {
          await openAppSettings();
        }
      }
    }
  }

  Future<void> _connectToDevice(BluetoothInfo dev) async {
    setState(() => _connectingMac = dev.macAdress);
    try {
      final success = await _service.connect(dev.macAdress);
      if (success) {
        await _service.saveSelectedPrinter(dev.macAdress, dev.name);
        widget.onConnected(dev.name);
      } else {
        if (mounted) {
          ShowMessage.error(context, 'Could not connect to ${dev.name}. Make sure printer is ON and paired in phone Bluetooth settings.');
        }
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Connection error: $e');
    } finally {
      if (mounted) setState(() => _connectingMac = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.bluetooth_rounded, color: Color(0xFF0284C7)),
                const SizedBox(width: 10),
                const Text('Select Thermal Printer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.refresh_rounded, size: 20), tooltip: 'Rescan', onPressed: _scanDevices),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Printers must be paired in your device\'s Bluetooth settings first.',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            const Divider(height: 24),
            if (_isLoading)
              const Center(
                child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
              )
            else if (!_hasPermission)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), shape: BoxShape.circle),
                      child: const Icon(Icons.security_rounded, size: 36, color: Colors.amber),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Nearby Devices Permission Needed',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Android requires Bluetooth / Nearby Devices permission so Selecta App can detect paired thermal printers.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _handlePermissionAction,
                      icon: Icon(_isPermanentlyDenied ? Icons.settings_rounded : Icons.check_circle_outline_rounded, size: 18),
                      label: Text(_isPermanentlyDenied ? 'Open App Settings' : 'Grant Permission'),
                    ),
                  ],
                ),
              )
            else if (!_isBluetoothOn)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.15), shape: BoxShape.circle),
                      child: const Icon(Icons.bluetooth_disabled_rounded, size: 36, color: Colors.blue),
                    ),
                    const SizedBox(height: 12),
                    const Text('Bluetooth is Turned Off', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 6),
                    const Text(
                      'Please turn ON Bluetooth on your phone, then tap the button below to detect paired printers.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(onPressed: _scanDevices, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Check Again')),
                  ],
                ),
              )
            else if (_devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                child: Column(
                  children: [
                    Icon(Icons.print_disabled_outlined, size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 10),
                    const Text('No paired Bluetooth printers found', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('To connect your printer:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          SizedBox(height: 4),
                          Text('1. Turn ON the thermal printer.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text('2. Open your phone\'s Bluetooth Settings.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text('3. Pair with your printer (PIN: usually 0000 or 1234).', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(
                            '4. Once paired under "Paired devices", return here and tap Refresh.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => openAppSettings(),
                          icon: const Icon(Icons.settings_outlined, size: 16),
                          label: const Text('App Settings'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _scanDevices,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Refresh List'),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _devices.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final dev = _devices[i];
                    final isConnectingThis = _connectingMac == dev.macAdress;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                        child: Icon(Icons.print_outlined, color: colorScheme.primary),
                      ),
                      title: Text(dev.name.isNotEmpty ? dev.name : 'Unknown Device', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(dev.macAdress, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                      trailing: isConnectingThis
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: isConnectingThis ? null : () => _connectToDevice(dev),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
