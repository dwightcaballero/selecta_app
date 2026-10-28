import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/services/sound_feedback_service.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/picklist/multi_qty_reminder_dialog.dart';

enum ScanFeedbackType { none, success, alreadyPicked, wrongItem }

class ScanFeedback {
  final ScanFeedbackType type;
  final String title;
  final String subtitle;
  final String barcode;
  final String? productName;
  final int? quantity;
  final DateTime timestamp;

  ScanFeedback({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.barcode,
    this.productName,
    this.quantity,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  static ScanFeedback empty() => ScanFeedback(
        type: ScanFeedbackType.none,
        title: '',
        subtitle: '',
        barcode: '',
      );
}

/// Dedicated full-screen continuous barcode scanner for warehouse order picking.
/// Keeps the camera open and allows scanning multiple items in rapid succession
/// with instant Heads-Up Display (HUD) feedback, audio/haptic responses, and
/// an expandable live checklist drawer.
class PicklistContinuousScannerPage extends StatefulWidget {
  final String storeName;
  final List<OrderItem> items;
  final Map<String, String> productIdToBarcode;
  final Map<String, Map<String, String>> barcodeToProductInfo;
  final Map<String, int> productIdToStock;
  final Map<String, int> productNameToStock;

  const PicklistContinuousScannerPage({
    super.key,
    required this.storeName,
    required this.items,
    required this.productIdToBarcode,
    required this.barcodeToProductInfo,
    this.productIdToStock = const {},
    this.productNameToStock = const {},
  });

  @override
  State<PicklistContinuousScannerPage> createState() => _PicklistContinuousScannerPageState();
}

class _PicklistContinuousScannerPageState extends State<PicklistContinuousScannerPage> {
  final MobileScannerController _cameraController = MobileScannerController();
  final FocusNode _keyboardFocusNode = FocusNode();
  final StringBuffer _scannerBuffer = StringBuffer();
  DateTime? _lastKeystrokeTime;

  late List<OrderItem> _items;
  bool _isTorchOn = false;
  bool _isProcessingModal = false;
  bool _isDrawerExpanded = false;

  String? _lastScannedBarcode;
  DateTime? _lastScannedTimestamp;

  ScanFeedback _feedback = ScanFeedback.empty();

  @override
  void initState() {
    super.initState();
    _items = widget.items.map((item) => item.copyWith()).toList();
    SoundFeedbackService().init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  int get _pickedCount => _items.where((it) => it.isPicked).length;
  int get _totalCount => _items.length;
  int get _totalUnits => _items.fold<int>(0, (total, it) => total + it.pickedQuantity);
  List<OrderItem> get _pendingItems => _items.where((it) => !it.isPicked).toList();

  int _getOnHandStock(OrderItem item) {
    if (item.productId.isNotEmpty && widget.productIdToStock.containsKey(item.productId)) {
      return widget.productIdToStock[item.productId]!;
    }
    final nameKey = item.productName.trim().toLowerCase();
    if (widget.productNameToStock.containsKey(nameKey)) {
      return widget.productNameToStock[nameKey]!;
    }
    return 0;
  }

  int _getRequiredQty(OrderItem item) {
    return item.pickedQuantity > 0 ? item.pickedQuantity : item.orderedQuantity;
  }

  String _getEffectiveBarcode(OrderItem item) {
    if (item.barcode.trim().isNotEmpty) return item.barcode.trim();
    if (item.productId.isNotEmpty && widget.productIdToBarcode.containsKey(item.productId)) {
      return widget.productIdToBarcode[item.productId]!;
    }
    return '';
  }

  int _findMatchingIndex(String rawBarcode) {
    final clean = rawBarcode.trim().toLowerCase();
    if (clean.isEmpty) return -1;

    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      final itemBarcode = _getEffectiveBarcode(item).toLowerCase();
      if (itemBarcode.isNotEmpty && itemBarcode == clean) {
        return i;
      }
      if (item.productId.toLowerCase() == clean) {
        return i;
      }
    }
    return -1;
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessingModal) return;

    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || barcode.trim().isEmpty) return;

    final cleanBarcode = barcode.trim();
    final now = DateTime.now();

    // 1.8-second debounce for duplicate scans of the exact same barcode in camera view
    if (_lastScannedBarcode == cleanBarcode &&
        _lastScannedTimestamp != null &&
        now.difference(_lastScannedTimestamp!).inMilliseconds < 1800) {
      return;
    }

    _lastScannedBarcode = cleanBarcode;
    _lastScannedTimestamp = now;

    _processBarcode(cleanBarcode);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        final scanned = _scannerBuffer.toString().trim();
        _scannerBuffer.clear();
        if (scanned.isNotEmpty) {
          _processBarcode(scanned);
        }
      } else if (event.character != null && event.character!.isNotEmpty) {
        final now = DateTime.now();
        if (_lastKeystrokeTime != null &&
            now.difference(_lastKeystrokeTime!).inMilliseconds > 1500) {
          _scannerBuffer.clear();
        }
        _lastKeystrokeTime = now;
        _scannerBuffer.write(event.character);
      }
    }
  }

  Future<void> _processBarcode(String barcode) async {
    final matchIndex = _findMatchingIndex(barcode);

    if (matchIndex == -1) {
      // ── Wrong SKU scanned ───────────────────────────────────────────
      SoundFeedbackService().playErrorBuzzer();

      final catalogProduct = widget.barcodeToProductInfo[barcode.toLowerCase()];
      final catalogName = catalogProduct?['name'] ?? '';

      setState(() {
        _feedback = ScanFeedback(
          type: ScanFeedbackType.wrongItem,
          title: 'WRONG ITEM! DO NOT PACK',
          subtitle: catalogName.isNotEmpty
              ? 'Scanned: $catalogName (Not in this order)'
              : 'Barcode $barcode is NOT in this order',
          barcode: barcode,
          productName: catalogName,
        );
      });
      return;
    }

    final item = _items[matchIndex];

    if (item.isPicked) {
      // ── Item already picked ─────────────────────────────────────────
      HapticFeedback.lightImpact();
      setState(() {
        _feedback = ScanFeedback(
          type: ScanFeedbackType.alreadyPicked,
          title: 'Already Checked',
          subtitle: '${item.productName} is already marked as picked',
          barcode: barcode,
          productName: item.productName,
        );
      });
      return;
    }

    final onHand = _getOnHandStock(item);
    final reqQty = _getRequiredQty(item);
    if (onHand < reqQty) {
      SoundFeedbackService().playErrorBuzzer();
      HapticFeedback.heavyImpact();
      setState(() {
        _feedback = ScanFeedback(
          type: ScanFeedbackType.wrongItem,
          title: onHand <= 0 ? '⚠️ Zero Warehouse Stock' : '⚠️ Insufficient Stock',
          subtitle: onHand <= 0
              ? '${item.productName}: 0 on hand in warehouse (Cannot pick)'
              : '${item.productName}: only $onHand on hand (need $reqQty)',
          barcode: barcode,
          productName: item.productName,
        );
      });
      return;
    }

    final isCase = item.category.trim().toLowerCase().contains('case');
    final unitLabel = isCase ? 'Cases' : 'Units';

    SoundFeedbackService().playSuccessChime();

    setState(() {
      _items[matchIndex] = item.copyWith(isPicked: true);
      _feedback = ScanFeedback(
        type: ScanFeedbackType.success,
        title: reqQty <= 1 ? '✓ Item Picked' : '✓ Items Picked',
        subtitle: reqQty <= 1
            ? '${item.productName} (1 unit)'
            : '${item.productName} ($reqQty $unitLabel)',
        barcode: barcode,
        productName: item.productName,
        quantity: reqQty,
      );
    });

    if (shouldShowMultiQtyReminder(reqQty) && mounted) {
      setState(() => _isProcessingModal = true);
      await showMultiQtyReminderDialog(
        context,
        _items[matchIndex],
        requiredQty: reqQty,
      );
      if (mounted) {
        setState(() => _isProcessingModal = false);
        _keyboardFocusNode.requestFocus();
      }
    }
  }

  Future<void> _toggleManualItem(int index) async {
    if (_isProcessingModal) return;
    final item = _items[index];
    if (!item.isPicked) {
      final onHand = _getOnHandStock(item);
      final reqQty = _getRequiredQty(item);
      if (onHand < reqQty) {
        SoundFeedbackService().playErrorBuzzer();
        HapticFeedback.heavyImpact();
        setState(() {
          _feedback = ScanFeedback(
            type: ScanFeedbackType.wrongItem,
            title: onHand <= 0 ? '⚠️ Zero Warehouse Stock' : '⚠️ Insufficient Stock',
            subtitle: onHand <= 0
                ? '${item.productName}: 0 on hand in warehouse (Cannot pick)'
                : '${item.productName}: only $onHand on hand (need $reqQty)',
            barcode: _getEffectiveBarcode(item),
            productName: item.productName,
          );
        });
        return;
      }
    }

    final newStatus = !_items[index].isPicked;
    setState(() {
      _items[index] = _items[index].copyWith(isPicked: newStatus);
      if (newStatus) {
        SoundFeedbackService().playSuccessChime();
      } else {
        HapticFeedback.lightImpact();
      }
    });

    if (newStatus) {
      final reqQty = _getRequiredQty(_items[index]);
      if (shouldShowMultiQtyReminder(reqQty) && mounted) {
        setState(() => _isProcessingModal = true);
        await showMultiQtyReminderDialog(
          context,
          _items[index],
          requiredQty: reqQty,
        );
        if (mounted) {
          setState(() => _isProcessingModal = false);
          _keyboardFocusNode.requestFocus();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allComplete = _totalCount > 0 && _pickedCount == _totalCount;
    final progress = _totalCount == 0 ? 0.0 : _pickedCount / _totalCount;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _items);
      },
      child: KeyboardListener(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // ── 1. Live Camera Feed ──────────────────────────────────
              MobileScanner(
                controller: _cameraController,
                onDetect: _onDetect,
              ),

              // ── 2. Viewfinder Reticle Overlay ────────────────────────
              _buildViewfinderOverlay(),

              // ── 3. Top Header Bar (Glassmorphic) ──────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopHeader(progress, allComplete),
              ),

              // ── 4. Heads-Up Display (HUD) Scan Feedback Banner ────────
              Positioned(
                bottom: _isDrawerExpanded ? 340 : 130,
                left: 16,
                right: 16,
                child: _buildHudFeedbackBanner(),
              ),

              // ── 5. Bottom Live Pending Items Drawer ───────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomDrawer(allComplete),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(double progress, bool allComplete) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                tooltip: 'Done & Return to Picklist',
                onPressed: () => Navigator.pop(context, _items),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Continuous Scanner • $_pickedCount of $_totalCount Picked ($_totalUnits units)',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                style: IconButton.styleFrom(
                  backgroundColor: _isTorchOn
                      ? Colors.amber.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.2),
                  foregroundColor: _isTorchOn ? Colors.black : Colors.white,
                ),
                icon: Icon(_isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded, size: 20),
                tooltip: 'Flashlight',
                onPressed: () async {
                  await _cameraController.toggleTorch();
                  setState(() => _isTorchOn = !_isTorchOn);
                },
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: allComplete ? Colors.green.shade600 : const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(context, _items),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              color: allComplete ? Colors.green.shade500 : const Color(0xFF38BDF8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewfinderOverlay() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 270,
            height: 190,
            decoration: BoxDecoration(
              border: Border.all(
                color: _feedback.type == ScanFeedbackType.wrongItem
                    ? Colors.redAccent.withValues(alpha: 0.9)
                    : (_feedback.type == ScanFeedbackType.success
                        ? Colors.greenAccent.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.7)),
                width: 2.2,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              children: [
                // Top-left bracket
                Positioned(top: 0, left: 0, child: _cornerBracket(0)),
                // Top-right bracket
                Positioned(top: 0, right: 0, child: _cornerBracket(1)),
                // Bottom-left bracket
                Positioned(bottom: 0, left: 0, child: _cornerBracket(2)),
                // Bottom-right bracket
                Positioned(bottom: 0, right: 0, child: _cornerBracket(3)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Align carton / tub barcode inside frame',
              style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cornerBracket(int index) {
    const double size = 20;
    const double thickness = 3.5;
    const color = Colors.white;

    Border border;
    switch (index) {
      case 0:
        border = const Border(top: BorderSide(color: color, width: thickness), left: BorderSide(color: color, width: thickness));
        break;
      case 1:
        border = const Border(top: BorderSide(color: color, width: thickness), right: BorderSide(color: color, width: thickness));
        break;
      case 2:
        border = const Border(bottom: BorderSide(color: color, width: thickness), left: BorderSide(color: color, width: thickness));
        break;
      case 3:
      default:
        border = const Border(bottom: BorderSide(color: color, width: thickness), right: BorderSide(color: color, width: thickness));
        break;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(border: border),
    );
  }

  Widget _buildHudFeedbackBanner() {
    if (_feedback.type == ScanFeedbackType.none) {
      return const SizedBox.shrink();
    }

    Color bgColor;
    Color borderColor;
    IconData icon;

    switch (_feedback.type) {
      case ScanFeedbackType.success:
        bgColor = const Color(0xFF15803D).withValues(alpha: 0.95);
        borderColor = const Color(0xFF4ADE80);
        icon = Icons.check_circle_rounded;
        break;
      case ScanFeedbackType.alreadyPicked:
        bgColor = const Color(0xFFB45309).withValues(alpha: 0.95);
        borderColor = const Color(0xFFFCD34D);
        icon = Icons.info_outline_rounded;
        break;
      case ScanFeedbackType.wrongItem:
        bgColor = const Color(0xFFB91C1C).withValues(alpha: 0.95);
        borderColor = const Color(0xFFF87171);
        icon = Icons.warning_amber_rounded;
        break;
      case ScanFeedbackType.none:
        return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _feedback.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _feedback.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
            onPressed: () => setState(() => _feedback = ScanFeedback.empty()),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomDrawer(bool allComplete) {
    final pending = _pendingItems;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      height: _isDrawerExpanded ? 320 : 100,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drawer Header / Handle
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isDrawerExpanded = !_isDrawerExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        allComplete ? Icons.task_alt_rounded : Icons.pending_actions_rounded,
                        size: 18,
                        color: allComplete ? const Color(0xFF4ADE80) : const Color(0xFF38BDF8),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          allComplete
                              ? 'All items picked! Tap Done to finish.'
                              : '${pending.length} pending items remaining',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        _isDrawerExpanded ? 'Hide List' : 'View Checklist',
                        style: TextStyle(
                          color: const Color(0xFF38BDF8),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        _isDrawerExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                        color: const Color(0xFF38BDF8),
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Drawer Scrollable List (visible when expanded)
          if (_isDrawerExpanded)
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                itemCount: _items.length,
                separatorBuilder: (context, index) => const Divider(height: 8, color: Colors.white12),
                itemBuilder: (ctx, idx) {
                  final item = _items[idx];
                  final isPicked = item.isPicked;
                  final barcode = _getEffectiveBarcode(item);

                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _toggleManualItem(idx),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: Row(
                        children: [
                          Icon(
                            isPicked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                            color: isPicked ? const Color(0xFF4ADE80) : Colors.white38,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          CachedProductImage(imageUrl: item.imageUrl, size: 36, borderRadius: 6),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.productName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isPicked ? Colors.white60 : Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    decoration: isPicked ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                if (barcode.isNotEmpty)
                                  Text(
                                    barcode,
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10.5,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                Builder(builder: (context) {
                                  final onHand = _getOnHandStock(item);
                                  final reqQty = _getRequiredQty(item);
                                  if (onHand < reqQty && !isPicked) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        onHand <= 0 ? '0 on hand (Out of stock)' : 'Only $onHand on hand (Need $reqQty)',
                                        style: TextStyle(
                                          color: onHand <= 0 ? Colors.redAccent.shade100 : Colors.amberAccent.shade100,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isPicked ? Colors.green.withValues(alpha: 0.2) : Colors.white10,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '×${item.pickedQuantity}',
                              style: TextStyle(
                                color: isPicked ? const Color(0xFF4ADE80) : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
