import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported thermal printer roll widths.
enum ThermalPaperSize {
  mm58(widthChars: 32, label: '58mm (Standard / 32 cols)'),
  mm80(widthChars: 48, label: '80mm (Wide / 48 cols)');

  final int widthChars;
  final String label;

  const ThermalPaperSize({required this.widthChars, required this.label});

  PaperSize get toPosPaperSize => this == ThermalPaperSize.mm80 ? PaperSize.mm80 : PaperSize.mm58;

  static ThermalPaperSize fromString(String? val) {
    if (val == '80mm' || val == 'mm80') return ThermalPaperSize.mm80;
    return ThermalPaperSize.mm58;
  }

  String get code => this == ThermalPaperSize.mm80 ? '80mm' : '58mm';
}

/// Service managing Bluetooth thermal printer settings, device connection,
/// text-only digital receipt generation, and ESC/POS thermal printing.
class ThermalPrinterService {
  static final ThermalPrinterService _instance = ThermalPrinterService._internal();
  factory ThermalPrinterService() => _instance;
  ThermalPrinterService._internal();

  static const String prefPaperSizeKey = 'thermal_printer_paper_size';
  static const String prefPrinterMacKey = 'thermal_printer_mac';
  static const String prefPrinterNameKey = 'thermal_printer_name';

  // ═══════════════════════════════════════════════════════════════════════════
  // PREFERENCES (Paper Size & Saved Printer)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<ThermalPaperSize> getPaperSize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(prefPaperSizeKey);
    return ThermalPaperSize.fromString(saved);
  }

  Future<void> setPaperSize(ThermalPaperSize size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefPaperSizeKey, size.code);
  }

  Future<String?> getSavedPrinterMac() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefPrinterMacKey);
  }

  Future<String?> getSavedPrinterName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefPrinterNameKey);
  }

  Future<void> saveSelectedPrinter(String mac, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefPrinterMacKey, mac);
    await prefs.setString(prefPrinterNameKey, name);
  }

  Future<void> clearSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefPrinterMacKey);
    await prefs.remove(prefPrinterNameKey);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BLUETOOTH STATUS, PERMISSIONS & CONNECTIVITY
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> isBluetoothEnabled() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  /// Checks if required Bluetooth permissions have been granted.
  Future<bool> checkBluetoothPermissions() async {
    try {
      if (Platform.isAndroid) {
        final connectStatus = await Permission.bluetoothConnect.status;
        final scanStatus = await Permission.bluetoothScan.status;

        if (connectStatus.isGranted && scanStatus.isGranted) {
          return true;
        }

        // Check plugin's internal check as fallback (supports pre-Android 12)
        return await PrintBluetoothThermal.isPermissionBluetoothGranted;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Checks if Bluetooth permissions were permanently denied.
  Future<bool> isPermissionPermanentlyDenied() async {
    try {
      if (Platform.isAndroid) {
        final connectStatus = await Permission.bluetoothConnect.status;
        final scanStatus = await Permission.bluetoothScan.status;
        return connectStatus.isPermanentlyDenied || scanStatus.isPermanentlyDenied;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Explicitly requests runtime Bluetooth permissions required to access
  /// paired and nearby Bluetooth thermal printers.
  Future<bool> requestBluetoothPermissions() async {
    try {
      if (Platform.isAndroid) {
        // 1. Request Android 12+ runtime permissions via permission_handler
        final statuses = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();

        final connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
        final scanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? false;

        if (connectGranted && scanGranted) {
          return true;
        }

        // 2. Also invoke plugin's native channel which handles ActivityCompat request
        final pluginGranted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
        return pluginGranted;
      }
      return true;
    } catch (e) {
      if (kDebugMode) print('Error requesting bluetooth permissions: $e');
      return false;
    }
  }

  Future<bool> isPermissionGranted() async {
    return checkBluetoothPermissions();
  }

  Future<List<BluetoothInfo>> getPairedDevices() async {
    try {
      // Ensure permissions before reading bonded devices to prevent SecurityException
      final hasPerm = await checkBluetoothPermissions();
      if (!hasPerm) {
        await requestBluetoothPermissions();
      }
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (e) {
      if (kDebugMode) print('Failed to get paired bluetooths: $e');
      return [];
    }
  }

  Future<bool> isConnected() async {
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      return false;
    }
  }

  Future<bool> connect(String macAddress) async {
    try {
      return await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
    } catch (e) {
      if (kDebugMode) print('Connection error: $e');
      return false;
    }
  }

  Future<bool> disconnect() async {
    try {
      return await PrintBluetoothThermal.disconnect;
    } catch (_) {
      return false;
    }
  }

  /// Ensures a printer is connected. If already connected, returns true.
  /// Otherwise attempts to connect to the saved MAC address.
  Future<bool> ensureConnected() async {
    if (await isConnected()) return true;
    final savedMac = await getSavedPrinterMac();
    if (savedMac == null || savedMac.isEmpty) return false;
    return await connect(savedMac);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RECEIPT SEGREGATION HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Separates items into the 3 requested receipt categories with quantity and price subtotals:
  /// 1st section: Selecta Products (By Case)
  /// 2nd section: Selecta Products (By Piece)
  /// 3rd section: Other Products
  static ({
    List<OrderItem> selectaCase,
    List<OrderItem> selectaPiece,
    List<OrderItem> otherProducts,
    int subtotalQtyCase,
    int subtotalQtyPiece,
    int subtotalQtyOther,
    double subtotalCase,
    double subtotalPiece,
    double subtotalOther,
  })
  categorizeItems(List<OrderItem> items) {
    final selectaCase = <OrderItem>[];
    final selectaPiece = <OrderItem>[];
    final otherProducts = <OrderItem>[];

    for (final item in items) {
      final isSelecta = item.productSource.toLowerCase() == 'selecta';
      if (isSelecta) {
        final cat = item.category.trim().toLowerCase();
        if (cat == 'by case' || cat.contains('case')) {
          selectaCase.add(item);
        } else {
          // Defaults to 'By Piece'
          selectaPiece.add(item);
        }
      } else {
        otherProducts.add(item);
      }
    }

    int compareOrderItems(OrderItem a, OrderItem b) {
      return Helperfunctions.compareBySrpAndName(
        nameA: a.productName,
        priceA: a.sellingPrice,
        nameB: b.productName,
        priceB: b.sellingPrice,
      );
    }

    selectaCase.sort(compareOrderItems);
    selectaPiece.sort(compareOrderItems);
    otherProducts.sort(compareOrderItems);

    int calcSubtotalQty(List<OrderItem> list) => list.fold<int>(0, (sum, i) => sum + i.pickedQuantity);

    double calcSubtotal(List<OrderItem> list) => list.fold<double>(0.0, (sum, i) => sum + (i.sellingPrice * i.pickedQuantity));

    return (
      selectaCase: selectaCase,
      selectaPiece: selectaPiece,
      otherProducts: otherProducts,
      subtotalQtyCase: calcSubtotalQty(selectaCase),
      subtotalQtyPiece: calcSubtotalQty(selectaPiece),
      subtotalQtyOther: calcSubtotalQty(otherProducts),
      subtotalCase: calcSubtotal(selectaCase),
      subtotalPiece: calcSubtotal(selectaPiece),
      subtotalOther: calcSubtotal(otherProducts),
    );
  }

  /// Utility to word-wrap a string into lines that do not exceed [maxWidth].
  static List<String> wrapText(String text, int maxWidth) {
    final clean = text.trim();
    if (clean.isEmpty) return [''];
    if (clean.length <= maxWidth) return [clean];

    final words = clean.split(RegExp(r'\s+'));
    final lines = <String>[];
    var currentLine = '';

    for (final word in words) {
      if (word.length > maxWidth) {
        if (currentLine.isNotEmpty) {
          lines.add(currentLine);
          currentLine = '';
        }
        var remaining = word;
        while (remaining.length > maxWidth) {
          lines.add(remaining.substring(0, maxWidth));
          remaining = remaining.substring(maxWidth);
        }
        currentLine = remaining;
      } else if (currentLine.isEmpty) {
        currentLine = word;
      } else if (currentLine.length + 1 + word.length <= maxWidth) {
        currentLine += ' $word';
      } else {
        lines.add(currentLine);
        currentLine = word;
      }
    }

    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }

    return lines;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DIGITAL RECEIPT (TEXT-ONLY GENERATION)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generates a structured, clean, monospace text-only digital receipt
  /// formatted for the specified paper width (58mm = 32 chars, 80mm = 48 chars).
  String generateTextReceipt({
    required Delivery delivery,
    required String dealerName,
    String? deliveryId,
    ThermalPaperSize paperSize = ThermalPaperSize.mm58,
  }) {
    final width = paperSize.widthChars;
    final divider = '-' * width;
    final doubleDivider = '=' * width;
    final buffer = StringBuffer();

    final currency = NumberFormat('#,##0.00');
    final dateStr = DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.now());
    final cat = categorizeItems(delivery.items);

    String center(String text) {
      if (text.length >= width) return text;
      final pad = (width - text.length) ~/ 2;
      return ' ' * pad + text;
    }

    // ── Column Widths Setup ──────────────────────────────────────────────────
    // 58mm (32 chars): Name (11), Qty (3), Price (7), Total (8) + 3 spaces = 32
    // 80mm (48 chars): Name (22), Qty (4), Price (9), Total (10) + 3 spaces = 48
    final is80 = paperSize == ThermalPaperSize.mm80;
    final nameWidth = is80 ? 22 : 11;
    final qtyWidth = is80 ? 4 : 3;
    final priceWidth = is80 ? 9 : 7;
    final totalWidth = is80 ? 10 : 8;

    String formatAmount(double value, int colWidth) {
      final formatted = currency.format(value);
      if (formatted.length <= colWidth) {
        return formatted.padLeft(colWidth);
      }
      final noComma = value.toStringAsFixed(2);
      if (noComma.length <= colWidth) {
        return noComma.padLeft(colWidth);
      }
      return formatted;
    }

    final tableHeader = '${'ITEM'.padRight(nameWidth)} ${'QTY'.padLeft(qtyWidth)} ${'PRICE'.padLeft(priceWidth)} ${'TOTAL'.padLeft(totalWidth)}';

    // ── Header Section (Dealer Name, Delivery Receipt, Store Name, Date) ─────
    final cleanDealer = dealerName.trim().isNotEmpty ? dealerName.trim().toUpperCase() : 'SELECTA DEALER';
    final cleanStore = delivery.storeName.trim().toUpperCase();

    buffer.writeln(center(cleanDealer));
    buffer.writeln(center('DELIVERY RECEIPT'));
    buffer.writeln('\n');
    buffer.writeln(divider);

    // ── Table Header (Appears only once at top) ─────────────────────────────
    buffer.writeln(tableHeader);
    buffer.writeln(divider);

    void writeProductRow(OrderItem item) {
      final nameLines = wrapText(item.productName.toUpperCase(), nameWidth);
      final qtyStr = item.pickedQuantity.toString().padLeft(qtyWidth);
      final priceStr = formatAmount(item.sellingPrice, priceWidth);
      final totalStr = formatAmount(item.sellingPrice * item.pickedQuantity, totalWidth);

      buffer.writeln('${nameLines[0].padRight(nameWidth)} $qtyStr $priceStr $totalStr');
      for (int i = 1; i < nameLines.length; i++) {
        buffer.writeln(nameLines[i]);
      }
    }

    void writeSubtotalRow(String categoryName, int subtotalQty, double subtotalAmount) {
      final subLabel = is80 ? 'SUBTOTAL ($categoryName)' : 'SUB ($categoryName)';
      final qtyStr = subtotalQty.toString().padLeft(qtyWidth);
      final emptyPrice = ' ' * priceWidth;
      final totalStr = formatAmount(subtotalAmount, totalWidth);

      buffer.writeln('${subLabel.padRight(nameWidth)} $qtyStr $emptyPrice $totalStr');
    }

    void writeCategoryItems(String sectionTitle, String categoryName, List<OrderItem> items, int subtotalQty, double subtotalAmount) {
      buffer.writeln('[$sectionTitle]');
      for (final item in items) {
        writeProductRow(item);
      }
      writeSubtotalRow(categoryName, subtotalQty, subtotalAmount);
      buffer.writeln(divider);
    }

    // ── Segregated Sections (By Case, By Piece, Other Products)
    if (cat.selectaCase.isNotEmpty) {
      writeCategoryItems('BY CASE', 'CASE', cat.selectaCase, cat.subtotalQtyCase, cat.subtotalCase);
    }

    if (cat.selectaPiece.isNotEmpty) {
      writeCategoryItems('BY PIECE', 'PIECE', cat.selectaPiece, cat.subtotalQtyPiece, cat.subtotalPiece);
    }

    if (cat.otherProducts.isNotEmpty) {
      writeCategoryItems('OTHER PRODUCTS', 'OTHER', cat.otherProducts, cat.subtotalQtyOther, cat.subtotalOther);
    }

    if (cat.selectaCase.isEmpty && cat.selectaPiece.isEmpty && cat.otherProducts.isEmpty) {
      buffer.writeln(center('(NO PRODUCTS IN ORDER)'));
      buffer.writeln(divider);
    }

    // ── Footer Section (Grand Total only) ───────────────────────────────────
    final grandTotalAmount = cat.subtotalCase + cat.subtotalPiece + cat.subtotalOther;
    final grandTotalQty = cat.subtotalQtyCase + cat.subtotalQtyPiece + cat.subtotalQtyOther;

    final grandLabel = 'GRAND TOTAL'.padRight(nameWidth);
    final grandQtyStr = grandTotalQty.toString().padLeft(qtyWidth);
    final emptyPrice = ' ' * priceWidth;
    final grandTotalStr = formatAmount(grandTotalAmount, totalWidth);

    buffer.writeln(doubleDivider);
    buffer.writeln('$grandLabel $grandQtyStr $emptyPrice $grandTotalStr');
    buffer.writeln(doubleDivider);

    buffer.writeln('\n');
    if (cleanStore.isNotEmpty) {
      final storeLines = wrapText('STORE: $cleanStore', width);
      for (final sLine in storeLines) {
        buffer.writeln(sLine);
      }
    }
    buffer.writeln('DATE: $dateStr');

    return buffer.toString();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ESC/POS THERMAL PRINTER BYTES GENERATION & PRINTING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generates ESC/POS command bytes for 58mm or 80mm thermal printer.
  Future<List<int>> generateEscPosBytes({
    required Delivery delivery,
    required String dealerName,
    String? deliveryId,
    ThermalPaperSize paperSize = ThermalPaperSize.mm58,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize.toPosPaperSize, profile);
    List<int> bytes = [];

    bytes += generator.reset();

    final text = generateTextReceipt(delivery: delivery, dealerName: dealerName, deliveryId: deliveryId, paperSize: paperSize);

    final lines = text.trim().split('\n');
    bool inHeader = true;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        // Output a newline to the thermal printer (avoid duplicate consecutive empty lines)
        if (i > 0 && lines[i - 1].trim().isEmpty) continue;
        bytes += generator.emptyLines(1);
        continue;
      }

      // Divider marks the end of header
      if (inHeader && (line.startsWith('---') || line.startsWith('==='))) {
        inHeader = false;
        bytes += generator.text(line);
        continue;
      }

      if (inHeader) {
        // Strip pre-padded spaces so thermal printer centers cleanly across 58mm/80mm
        final isDate = line.contains(DateFormat('yyyy').format(DateTime.now()));
        bytes += generator.text(
          line.trim(),
          styles: PosStyles(align: PosAlign.center, bold: !isDate),
        );
      } else if (line.startsWith('[') && line.endsWith(']')) {
        bytes += generator.text(line, styles: const PosStyles(bold: true));
      } else if (line.startsWith('ITEM') && line.contains('QTY') && line.contains('TOTAL')) {
        bytes += generator.text(line, styles: const PosStyles(bold: true));
      } else if (line.startsWith('SUBTOTAL')) {
        bytes += generator.text(line, styles: const PosStyles(bold: true));
      } else if (line.startsWith('GRAND TOTAL')) {
        bytes += generator.text(line, styles: const PosStyles(bold: true));
      } else {
        bytes += generator.text(line);
      }
    }

    // Feed only 1 line so paper clears tear bar without 5 hardcoded empty lines
    bytes += generator.feed(1);
    bytes += [0x1D, 0x56, 0x01]; // GS V 1: Partial cut (or manual tear)

    return bytes;
  }

  /// Sends the formatted receipt to the connected Bluetooth thermal printer.
  Future<bool> printReceipt({required Delivery delivery, required String dealerName, String? deliveryId, ThermalPaperSize? paperSize}) async {
    final effectiveSize = paperSize ?? await getPaperSize();
    final connected = await ensureConnected();
    if (!connected) {
      throw Exception('Bluetooth thermal printer is not connected.');
    }

    final bytes = await generateEscPosBytes(delivery: delivery, dealerName: dealerName, deliveryId: deliveryId, paperSize: effectiveSize);

    return await PrintBluetoothThermal.writeBytes(bytes);
  }

  /// Prints a short test ticket to verify alignment, paper width, and printer health.
  Future<bool> printTestReceipt({ThermalPaperSize? paperSize}) async {
    final effectiveSize = paperSize ?? await getPaperSize();
    final connected = await ensureConnected();
    if (!connected) {
      throw Exception('Thermal printer is not connected.');
    }

    final profile = await CapabilityProfile.load();
    final generator = Generator(effectiveSize.toPosPaperSize, profile);
    List<int> bytes = [];

    bytes += generator.reset();
    bytes += generator.text('THERMAL PRINTER TEST', styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text('Config: ${effectiveSize.label}', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text(DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.now()), styles: const PosStyles(align: PosAlign.center));
    bytes += generator.hr(ch: '-');
    bytes += generator.row([
      PosColumn(text: 'COL 1 (LEFT)', width: 6),
      PosColumn(
        text: 'COL 2 (RIGHT)',
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    bytes += generator.hr(ch: '=');
    bytes += generator.text('Selecta App Printer Config OK!', styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.feed(2);
    bytes += generator.cut();

    return await PrintBluetoothThermal.writeBytes(bytes);
  }
}
