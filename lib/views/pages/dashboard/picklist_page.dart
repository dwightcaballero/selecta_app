import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/delivery_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/services/inventory_service.dart';
import 'package:selecta_ops/views/pages/dashboard/book_order_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/digital_receipt_dialog.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/sound_feedback_service.dart';
import 'package:selecta_ops/views/pages/dashboard/picklist_continuous_scanner_page.dart';
import 'package:selecta_ops/views/widgets/picklist/multi_qty_reminder_dialog.dart';
import 'package:image_picker/image_picker.dart';

class PicklistPage extends StatefulWidget {
  final String deliveryID;
  final Delivery delivery;

  const PicklistPage({super.key, required this.deliveryID, required this.delivery});

  @override
  State<PicklistPage> createState() => _PicklistPageState();
}

class _PicklistPageState extends State<PicklistPage> {
  final DeliveryController _controller = DeliveryController();
  final ImagePicker _picker = ImagePicker();

  late Delivery _currentDelivery;
  late List<OrderItem> _items;
  File? _pickedImage;
  String _networkImagePath = '';
  bool _isDealer = true;
  bool _isAdmin = false;
  bool _isSaving = false;

  String _itemFilter = 'All'; // 'All', 'Pending', 'Picked'
  List<int> _selectaCaseIndices = [];
  List<int> _selectaPieceIndices = [];
  List<int> _otherIndices = [];

  final FocusNode _scannerFocusNode = FocusNode();
  final StringBuffer _scannerBuffer = StringBuffer();
  DateTime? _lastKeystrokeTime;

  bool _enableBarcodeScanner = true;
  final Map<String, String> _productIdToBarcode = {};
  final Map<String, Map<String, String>> _barcodeToProductInfo = {};
  StreamSubscription<List<InventoryItem>>? _inventorySub;
  final Map<String, int> _productIdToStock = {};
  final Map<String, int> _productNameToStock = {};

  @override
  void initState() {
    super.initState();
    _currentDelivery = widget.delivery;
    _items = widget.delivery.items.map((item) => item.copyWith()).toList();
    _networkImagePath = widget.delivery.imagePath;
    _groupAndSortItemIndices();
    _prefetchData();
    _subscribeInventory();
    SoundFeedbackService().init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scannerFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _inventorySub?.cancel();
    _scannerFocusNode.dispose();
    super.dispose();
  }

  void _subscribeInventory() {
    _inventorySub = InventoryService().getActiveInventoryStream().listen((items) {
      if (!mounted) return;
      final idMap = <String, int>{};
      final nameMap = <String, int>{};
      for (final it in items) {
        idMap[it.id] = it.stockQuantity;
        final nameKey = it.productName.trim().toLowerCase();
        if (it.stockQuantity > 0 || !nameMap.containsKey(nameKey)) {
          nameMap[nameKey] = it.stockQuantity;
        }
      }
      setState(() {
        _productIdToStock.clear();
        _productIdToStock.addAll(idMap);
        _productNameToStock.clear();
        _productNameToStock.addAll(nameMap);
      });
    });
  }

  int _getOnHandStock(OrderItem item) {
    int stock = 0;
    if (item.productId.isNotEmpty && _productIdToStock.containsKey(item.productId)) {
      stock = _productIdToStock[item.productId]!;
    }
    final nameKey = item.productName.trim().toLowerCase();
    if (_productNameToStock.containsKey(nameKey)) {
      final nameStock = _productNameToStock[nameKey]!;
      if (nameStock > stock) {
        stock = nameStock;
      }
    }
    return stock;
  }

  int _getRequiredQty(OrderItem item) {
    return item.pickedQuantity > 0 ? item.pickedQuantity : item.orderedQuantity;
  }

  Future<void> _showCannotPickStockDialog(OrderItem item, int onHand, int reqQty, {int? index}) async {
    SoundFeedbackService().playErrorBuzzer();
    HapticFeedback.heavyImpact();

    final isZero = onHand <= 0;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.block_rounded, color: Colors.red.shade700, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isZero ? 'CANNOT PICK - ZERO STOCK' : 'CANNOT PICK - INSUFFICIENT STOCK',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red.shade900),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isZero
                        ? 'The physical warehouse count for this product is 0 units.'
                        : 'Physical warehouse count is only $onHand unit(s), but the picklist requires $reqQty unit(s).',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isZero
                        ? 'You can mark this item as Out of Stock (0 Picked). The store will not be charged, and it will be recorded on their receipt as OOS without losing what they originally ordered.'
                        : 'You can pick the available $onHand unit(s) or mark as Out of Stock (0 Picked). The shortage will be printed on the receipt.',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CachedProductImage(imageUrl: item.imageUrl, size: 44, borderRadius: 8),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.productName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('Category: ${item.category}', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Warehouse Physical Count:', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                Text(
                  '$onHand ${item.category.toLowerCase().contains('case') ? 'Cases' : 'Units'}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isZero ? Colors.red.shade700 : Colors.amber.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Required Picklist Qty:', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                Text(
                  '$reqQty ${item.category.toLowerCase().contains('case') ? 'Cases' : 'Units'}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Select an option below to proceed without deleting or corrupting the order:',
              style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
            ),
          ],
        ),
        actions: [
          if (index != null) ...[
            if (!isZero && onHand > 0)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade800),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text('Pick Available ($onHand)'),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _items[index] = item.copyWith(pickedQuantity: onHand, isPicked: true);
                  });
                  SoundFeedbackService().playSuccessChime();
                  ShowMessage.info(
                    context,
                    'Adjusted ${item.productName} to available $onHand units. Shortage will be noted on receipt.',
                  );
                },
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              icon: const Icon(Icons.remove_shopping_cart_outlined, size: 18),
              label: const Text('Mark Out of Stock (0 Picked)'),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _items[index] = item.copyWith(pickedQuantity: 0, isPicked: true);
                });
                SoundFeedbackService().playSuccessChime();
                ShowMessage.warning(
                  context,
                  'Marked ${item.productName} as Out of Stock (0 picked). The store will not be charged and receipt will show OOS.',
                );
              },
            ),
          ],
          if (_isDealer)
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('Edit Order'),
              onPressed: () {
                Navigator.pop(ctx);
                _openEditOrderProducts();
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (mounted) _scannerFocusNode.requestFocus();
  }

  void _groupAndSortItemIndices() {
    final caseList = <int>[];
    final pieceList = <int>[];
    final otherList = <int>[];

    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      final isSelecta = item.productSource.trim().toLowerCase() == 'selecta' || item.productSource.trim().isEmpty;
      if (isSelecta) {
        final cat = item.category.trim().toLowerCase();
        if (cat == 'by case' || cat.contains('case')) {
          caseList.add(i);
        } else {
          pieceList.add(i);
        }
      } else {
        otherList.add(i);
      }
    }

    int compareDeliveryItemIndices(int a, int b) {
      final itemA = _items[a];
      final itemB = _items[b];
      return Helperfunctions.compareProducts(
        nameA: itemA.productName,
        priceA: itemA.sellingPrice,
        nameB: itemB.productName,
        priceB: itemB.sellingPrice,
        productIdA: itemA.productId,
        productIdB: itemB.productId,
        categoryA: itemA.category,
        categoryB: itemB.category,
      );
    }

    caseList.sort(compareDeliveryItemIndices);
    pieceList.sort(compareDeliveryItemIndices);
    otherList.sort(compareDeliveryItemIndices);

    _selectaCaseIndices = caseList;
    _selectaPieceIndices = pieceList;
    _otherIndices = otherList;
  }

  Future<void> _prefetchData() async {
    final dealer = await _controller.checkIsDealer();
    final admin = await _controller.checkIsAdmin();
    if (mounted) {
      setState(() {
        _isDealer = dealer;
        _isAdmin = admin;
      });
    }

    try {
      final config = await ConfigurationService().getConfiguration();
      if (mounted) {
        setState(() {
          _enableBarcodeScanner = config.enablePicklistBarcodeScanner;
        });
      }
    } catch (_) {}

    try {
      final selectaDocs = await FirebaseFirestore.instance.collection('selecta_products').get();
      for (final doc in selectaDocs.docs) {
        final data = doc.data();
        final barcode = (data['barcode'] as String? ?? '').trim();
        final name = (data['productName'] as String? ?? '').trim();
        final stock = (data['stockQuantity'] as num?)?.toInt() ?? 0;
        _productIdToStock[doc.id] = stock;
        if (name.isNotEmpty) {
          final nameKey = name.toLowerCase();
          if (stock > 0 || !_productNameToStock.containsKey(nameKey)) {
            _productNameToStock[nameKey] = stock;
          }
        }
        if (barcode.isNotEmpty) {
          _productIdToBarcode[doc.id] = barcode;
          _barcodeToProductInfo[barcode.toLowerCase()] = {'name': name, 'id': doc.id};
        }
      }

      final adminDocs = await FirebaseFirestore.instance.collection('admin_selecta_products').get();
      for (final doc in adminDocs.docs) {
        final data = doc.data();
        final barcode = (data['barcode'] as String? ?? '').trim();
        final name = (data['productName'] as String? ?? '').trim();
        // admin_selecta_products is the master catalog without dealer stockQuantity.
        // Link doc ID to existing stock by product name if available from selecta_products.
        final nameKey = name.toLowerCase();
        if (_productNameToStock.containsKey(nameKey)) {
          _productIdToStock[doc.id] = _productNameToStock[nameKey]!;
        }
        if (barcode.isNotEmpty) {
          _productIdToBarcode[doc.id] = barcode;
          _barcodeToProductInfo[barcode.toLowerCase()] = {'name': name, 'id': doc.id};
        }
      }

      final otherDocs = await FirebaseFirestore.instance.collection('other_products').get();
      for (final doc in otherDocs.docs) {
        final data = doc.data();
        final barcode = (data['barcode'] as String? ?? '').trim();
        final name = (data['productName'] as String? ?? '').trim();
        final stock = (data['stockQuantity'] as num?)?.toInt() ?? 0;
        _productIdToStock[doc.id] = stock;
        if (name.isNotEmpty) {
          final nameKey = name.toLowerCase();
          if (stock > 0 || !_productNameToStock.containsKey(nameKey)) {
            _productNameToStock[nameKey] = stock;
          }
        }
        if (barcode.isNotEmpty) {
          _productIdToBarcode[doc.id] = barcode;
          _barcodeToProductInfo[barcode.toLowerCase()] = {'name': name, 'id': doc.id};
        }
      }

      if (mounted) setState(() {});
    } catch (_) {}
  }

  String _getEffectiveBarcode(OrderItem item) {
    if (item.barcode.trim().isNotEmpty) return item.barcode.trim();
    if (item.productId.isNotEmpty && _productIdToBarcode.containsKey(item.productId)) {
      return _productIdToBarcode[item.productId]!;
    }
    return '';
  }

  int _findMatchingOrderItemIndex(String rawBarcode) {
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

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        final scanned = _scannerBuffer.toString().trim();
        _scannerBuffer.clear();
        if (scanned.isNotEmpty) {
          _handleScannedBarcode(scanned);
        }
      } else if (event.character != null && event.character!.isNotEmpty) {
        final now = DateTime.now();
        if (_lastKeystrokeTime != null && now.difference(_lastKeystrokeTime!).inMilliseconds > 1500) {
          _scannerBuffer.clear();
        }
        _lastKeystrokeTime = now;
        _scannerBuffer.write(event.character);
      }
    }
  }

  Future<void> _openCameraScanner() async {
    final updatedItems = await Navigator.push<List<OrderItem>>(
      context,
      MaterialPageRoute(
        builder: (_) => PicklistContinuousScannerPage(
          storeName: _currentDelivery.storeName,
          items: _items,
          productIdToBarcode: _productIdToBarcode,
          barcodeToProductInfo: _barcodeToProductInfo,
          productIdToStock: _productIdToStock,
          productNameToStock: _productNameToStock,
        ),
      ),
    );
    if (updatedItems != null && mounted) {
      setState(() {
        _items = updatedItems;
        _groupAndSortItemIndices();
      });
    }
    if (mounted) {
      _scannerFocusNode.requestFocus();
    }
  }

  Future<void> _handleScannedBarcode(String rawBarcode) async {
    final barcode = rawBarcode.trim();
    if (barcode.isEmpty) return;

    final matchIndex = _findMatchingOrderItemIndex(barcode);

    if (matchIndex == -1) {
      // WRONG SKU: Trigger loud error buzzer + long vibration & red warning dialog
      SoundFeedbackService().playErrorBuzzer();

      final catalogMatch = _barcodeToProductInfo[barcode.toLowerCase()];
      final scannedProductName = catalogMatch?['name'] ?? '';

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 26),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'WRONG ITEM SCANNED',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This product is NOT part of [${_currentDelivery.storeName}]\'s delivery order.',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'DO NOT PACK THIS ITEM!',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.red.shade700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Barcode: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(barcode, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                  ),
                ],
              ),
              if (scannedProductName.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Catalog Item: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(scannedProductName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      );

      if (mounted) _scannerFocusNode.requestFocus();
      return;
    }

    final item = _items[matchIndex];

    // If item is already picked:
    if (item.isPicked) {
      HapticFeedback.lightImpact();
      ShowMessage.info(context, '${item.productName} is already checked.');
      if (mounted) _scannerFocusNode.requestFocus();
      return;
    }

    final onHand = _getOnHandStock(item);
    final reqQty = _getRequiredQty(item);
    if (onHand < reqQty) {
      await _showCannotPickStockDialog(item, onHand, reqQty, index: matchIndex);
      return;
    }

    setState(() {
      _items[matchIndex] = item.copyWith(isPicked: true);
    });
    SoundFeedbackService().playSuccessChime();
    final unitLabel = reqQty == 1 ? '1 unit' : '$reqQty units';
    ShowMessage.success(context, 'Checked: ${item.productName} ($unitLabel)');

    if (shouldShowMultiQtyReminder(reqQty) && mounted) {
      await showMultiQtyReminderDialog(
        context,
        _items[matchIndex],
        requiredQty: reqQty,
      );
    }

    if (mounted) _scannerFocusNode.requestFocus();
  }

  bool get _hasProofOfDelivery => _pickedImage != null || _networkImagePath.trim().isNotEmpty;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      if (pickedFile != null) {
        setState(() {
          _pickedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to capture image: $e');
      }
    }
  }

  void _showImageSourceSelector() {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Attach Proof of Delivery', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                ),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                  child: Icon(Icons.camera_alt_outlined, color: colorScheme.primary),
                ),
                title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Capture with camera'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                  child: Icon(Icons.photo_library_outlined, color: colorScheme.primary),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Select existing photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasUnsavedChanges {
    if (_pickedImage != null) return true;
    if (_networkImagePath != widget.delivery.imagePath) return true;
    if (_items.length != widget.delivery.items.length) return true;
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].isPicked != widget.delivery.items[i].isPicked) return true;
    }
    return false;
  }

  Future<void> _removeImage() async {
    if (_networkImagePath.isNotEmpty) {
      final confirmed = await ShowMessage.confirm(
        context,
        title: 'Remove Image',
        message: 'Are you sure you want to remove the attached Proof of Delivery image?',
        icon: Icons.delete_outline,
        confirmText: 'Remove',
        isDestructive: true,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() {
      _pickedImage = null;
      _networkImagePath = '';
    });
  }

  int get _totalUnits {
    return _items.fold<int>(0, (total, item) => total + item.pickedQuantity);
  }

  int get _pickedLinesCount {
    return _items.where((item) => item.isPicked).length;
  }

  bool get _allItemsPicked {
    return _items.isNotEmpty && _items.every((item) => item.isPicked);
  }

  void _toggleAllPicked() {
    HapticFeedback.lightImpact();
    final target = !_allItemsPicked;
    if (!target) {
      setState(() {
        for (int i = 0; i < _items.length; i++) {
          _items[i] = _items[i].copyWith(isPicked: false);
        }
      });
      return;
    }

    int skippedCount = 0;
    setState(() {
      for (int i = 0; i < _items.length; i++) {
        final item = _items[i];
        final onHand = _getOnHandStock(item);
        final reqQty = _getRequiredQty(item);
        if (onHand >= reqQty) {
          _items[i] = item.copyWith(isPicked: true);
        } else {
          skippedCount++;
        }
      }
    });

    if (skippedCount > 0) {
      SoundFeedbackService().playErrorBuzzer();
      ShowMessage.error(
        context,
        'Skipped $skippedCount item(s) due to zero or insufficient physical warehouse stock.',
      );
    } else {
      SoundFeedbackService().playSuccessChime();
    }
  }

  void _toggleCategoryPicked(List<int> indices) {
    if (indices.isEmpty) return;
    HapticFeedback.lightImpact();
    final allCategoryPicked = indices.every((i) => _items[i].isPicked);
    final target = !allCategoryPicked;
    if (!target) {
      setState(() {
        for (final i in indices) {
          _items[i] = _items[i].copyWith(isPicked: false);
        }
      });
      return;
    }

    int skippedCount = 0;
    setState(() {
      for (final i in indices) {
        final item = _items[i];
        final onHand = _getOnHandStock(item);
        final reqQty = _getRequiredQty(item);
        if (onHand >= reqQty) {
          _items[i] = item.copyWith(isPicked: true);
        } else {
          skippedCount++;
        }
      }
    });

    if (skippedCount > 0) {
      SoundFeedbackService().playErrorBuzzer();
      ShowMessage.error(
        context,
        'Skipped $skippedCount item(s) in category due to zero or insufficient physical warehouse stock.',
      );
    } else {
      SoundFeedbackService().playSuccessChime();
    }
  }

  Future<void> _toggleItemPicked(int index) async {
    final item = _items[index];
    if (item.isPicked) {
      if (item.pickedQuantity < item.orderedQuantity) {
        final reset = await ShowMessage.confirm(
          context,
          title: 'Reset Adjusted Item',
          message:
              'Restore "${item.productName}" to original order quantity (${item.orderedQuantity}) and mark as unpicked?',
          confirmText: 'Restore (${item.orderedQuantity})',
          cancelText: 'Keep As Is',
        );
        if (reset) {
          setState(() {
            _items[index] = item.copyWith(
              pickedQuantity: item.orderedQuantity,
              isPicked: false,
            );
          });
          HapticFeedback.lightImpact();
        }
        return;
      }

      setState(() {
        final newStatus = !item.isPicked;
        _items[index] = item.copyWith(isPicked: newStatus);
        if (newStatus) {
          SoundFeedbackService().playSuccessChime();
        } else {
          HapticFeedback.lightImpact();
        }
      });
      return;
    }

    final onHand = _getOnHandStock(item);
    final reqQty = _getRequiredQty(item);
    if (onHand < reqQty) {
      await _showCannotPickStockDialog(item, onHand, reqQty, index: index);
      return;
    }

    setState(() {
      _items[index] = item.copyWith(isPicked: true);
      SoundFeedbackService().playSuccessChime();
    });

    if (shouldShowMultiQtyReminder(reqQty) && mounted) {
      await showMultiQtyReminderDialog(
        context,
        _items[index],
        requiredQty: reqQty,
      );
    }
  }

  Future<void> _openEditOrderProducts() async {
    final updatedDelivery = await Navigator.push<Delivery>(
      context,
      MaterialPageRoute(
        builder: (_) => BookOrderPage(
          deliveryID: widget.deliveryID,
          existingDelivery: _currentDelivery.copyWith(items: _items, imagePath: _networkImagePath),
          returnUpdatedDeliveryOnSave: true,
        ),
      ),
    );

    if (updatedDelivery != null && mounted) {
      setState(() {
        _currentDelivery = updatedDelivery;
        _items = updatedDelivery.items.map((e) => e.copyWith()).toList();
        if (updatedDelivery.imagePath.isNotEmpty) {
          _networkImagePath = updatedDelivery.imagePath;
        }
        _groupAndSortItemIndices();
      });
    }
  }

  Future<void> _onSaveProgress() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    await Helperfunctions.showLoading(context: context, showLoading: true, message: 'Saving picklist draft...');
    if (!mounted) return;
    try {
      final updated = await _controller.savePicklistProgress(
        context: context,
        deliveryId: widget.deliveryID,
        currentDelivery: _currentDelivery,
        storeName: _currentDelivery.storeName,
        items: _items,
        imageFile: _pickedImage,
        networkImagePath: _networkImagePath,
        placements: const [],
        placementId: '',
        remarks: _currentDelivery.remarks,
      );
      if (mounted) {
        setState(() {
          _currentDelivery = updated;
          _networkImagePath = updated.imagePath;
          _pickedImage = null;
        });
        await Helperfunctions.showLoading(showLoading: false);
        if (mounted) {
          ShowMessage.success(context, 'Picklist draft saved.');
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      await Helperfunctions.showLoading(showLoading: false);
      if (mounted) {
        ShowMessage.error(context, 'Failed to save progress: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onCompletePicklist() async {
    if (_isSaving) return;
    if (!_allItemsPicked) {
      ShowMessage.error(context, 'Please check all products before marking For Delivery.');
      return;
    }

    if (!_hasProofOfDelivery) {
      ShowMessage.error(context, 'Please attach a Proof of Delivery image before marking For Delivery.');
      return;
    }

    final deliveryDate = _currentDelivery.deliveryDate?.toDate() ?? DateTime.now();
    final status = await _controller.checkBreakdownAndVerificationStatus(deliveryDate);
    if (!mounted) return;
    if (status.isVerified) {
      ShowMessage.error(
        context,
        'Cannot mark For Delivery: The daily cash breakdown for ${DateFormat('MMM d, yyyy').format(deliveryDate)} has already been verified and closed by the dealer.\n\nPlease reschedule this delivery to an open date before dispatching.',
      );
      return;
    }

    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Complete Picklist',
      message: 'Mark [${_currentDelivery.storeName}] (${_items.length} items • $_totalUnits total units) as For Delivery?',
      icon: Icons.local_shipping_outlined,
      confirmText: 'Mark For Delivery',
    );
    if (!confirmed || !mounted) return;

    final statusNotifier = ValueNotifier<String>('Preparing picklist...');
    setState(() => _isSaving = true);
    await Helperfunctions.showLoading(
      context: context,
      showLoading: true,
      statusNotifier: statusNotifier,
      message: 'Processing picklist...',
      subtitle: 'Please wait, do not close or exit the app.',
    );
    if (!mounted) {
      statusNotifier.dispose();
      return;
    }

    try {
      final updatedDelivery = await _controller.completePicklist(
        context: context,
        deliveryId: widget.deliveryID,
        currentDelivery: _currentDelivery,
        storeName: _currentDelivery.storeName,
        pickedItems: _items,
        imageFile: _pickedImage,
        networkImagePath: _networkImagePath,
        placements: const [],
        placementId: '',
        sendText: false,
        smsMessage: '',
        remarks: _currentDelivery.remarks,
        onProgress: (step) {
          statusNotifier.value = step;
        },
      );

      if (!mounted) return;

      setState(() {
        _currentDelivery = updatedDelivery;
        _networkImagePath = updatedDelivery.imagePath;
        _pickedImage = null;
      });

      await Helperfunctions.showLoading(showLoading: false);
      if (!mounted) return;

      ShowMessage.success(context, 'Picklist completed! [${updatedDelivery.storeName}] is now For Delivery.');

      // Generate digital receipt (text only) that can also be printed on a thermal printer via Bluetooth
      await DigitalReceiptDialog.show(
        context,
        delivery: updatedDelivery,
        deliveryId: widget.deliveryID,
        proceedLabel: 'Close',
        remindIfNotPrinted: true,
        onProceed: () {
          if (!mounted) return;
          Navigator.pop(context, true);
        },
      );
    } catch (e) {
      await Helperfunctions.showLoading(showLoading: false);
      if (mounted) {
        ShowMessage.error(context, 'Error completing picklist: $e');
      }
    } finally {
      statusNotifier.dispose();
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onVoidOrder() async {
    if (_isSaving) return;

    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.block, color: Colors.red.shade700, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('Void Picklist Order', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voiding this order for [${_currentDelivery.storeName}] will cancel the picklist and release all reserved stock back to available inventory. The record will be permanently saved with your reason.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: reasonController,
                  autofocus: true,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Reason for Voiding *',
                    hintText: 'e.g. Duplicate order, store cancelled before packing...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'A reason is required to void this order.';
                    }
                    if (val.trim().length < 5) {
                      return 'Please provide a descriptive reason (at least 5 characters).';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  Navigator.pop(dialogCtx, true);
                }
              },
              child: const Text('Void Order'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final reason = reasonController.text.trim();
    setState(() => _isSaving = true);
    await Helperfunctions.showLoading(context: context, showLoading: true, message: 'Voiding order & releasing reserved stock...');
    if (!mounted) return;

    try {
      await _controller.voidDelivery(context: context, deliveryId: widget.deliveryID, delivery: _currentDelivery, reason: reason);
      if (mounted) {
        await Helperfunctions.showLoading(showLoading: false);
        if (mounted) {
          ShowMessage.success(context, 'Voided picklist order for [${_currentDelivery.storeName}]. Reserved stock has been released.');
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      await Helperfunctions.showLoading(showLoading: false);
      if (mounted) {
        ShowMessage.error(context, 'Failed to void order: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onAdminDeleteOrder() async {
    if (_isSaving) return;

    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Delete Order (Admin)',
      message: 'Permanently delete this order record for [${_currentDelivery.storeName}]?\n\n'
          '• Document will be deleted from the database.\n'
          '• Any deducted inventory will be automatically restored to warehouse stock.\n'
          '• Any floating reserved stock will be released.',
      confirmText: 'Delete Permanently',
      isDestructive: true,
      icon: Icons.delete_forever,
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    await Helperfunctions.showLoading(context: context, showLoading: true, message: 'Deleting order & reversing inventory...');
    if (!mounted) return;

    try {
      await _controller.deleteDelivery(
        context: context,
        deliveryId: widget.deliveryID,
        delivery: _currentDelivery,
        isAdmin: true,
      );
      if (mounted) {
        await Helperfunctions.showLoading(showLoading: false);
        if (mounted) {
          ShowMessage.success(context, 'Order record deleted and inventory reversed.');
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      await Helperfunctions.showLoading(showLoading: false);
      if (mounted) {
        ShowMessage.error(context, 'Failed to delete order: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildAppBarIconAction({required IconData icon, required String tooltip, required VoidCallback? onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: IconButton(
        icon: Icon(icon, size: 18, color: Colors.white),
        tooltip: tooltip,
        onPressed: onTap,
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildProgressHeader(ColorScheme colorScheme, {bool isCompact = false}) {
    final totalLines = _items.length;
    final pickedLines = _pickedLinesCount;
    final progress = totalLines == 0 ? 0.0 : pickedLines / totalLines;
    final isComplete = _allItemsPicked;

    return Container(
      margin: isCompact ? const EdgeInsets.only(bottom: 12) : const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                isComplete ? Icons.check_circle_rounded : Icons.checklist_rtl_rounded,
                size: 20,
                color: isComplete ? Colors.green.shade700 : colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$pickedLines of $totalLines checked • $_totalUnits units',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
              ),
              if (_enableBarcodeScanner) ...[
                TextButton.icon(
                  onPressed: _openCameraScanner,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    foregroundColor: const Color(0xFF0284C7),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 17),
                  label: const Text('Scan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 4),
              ],
              TextButton.icon(
                onPressed: _items.isEmpty ? null : _toggleAllPicked,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                icon: Icon(_allItemsPicked ? Icons.remove_done_rounded : Icons.done_all_rounded, size: 17),
                label: Text(_allItemsPicked ? 'Uncheck All' : 'Check All', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: isComplete ? Colors.green.shade700 : colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(ColorScheme colorScheme) {
    final pendingCount = _items.where((i) => !i.isPicked).length;
    final pickedCount = _pickedLinesCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        children: [
          _buildFilterChip('All', 'All (${_items.length})', colorScheme),
          const SizedBox(width: 8),
          _buildFilterChip('Pending', 'Pending ($pendingCount)', colorScheme, badgeColor: Colors.amber.shade800),
          const SizedBox(width: 8),
          _buildFilterChip('Picked', 'Picked ($pickedCount)', colorScheme, badgeColor: Colors.green.shade700),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, ColorScheme colorScheme, {Color? badgeColor}) {
    final isSelected = _itemFilter == value;
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _itemFilter = value);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? (badgeColor?.withValues(alpha: 0.12) ?? colorScheme.primaryContainer.withValues(alpha: 0.4)) : colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? (badgeColor ?? colorScheme.primary) : colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected ? (badgeColor ?? colorScheme.primary) : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupHeader({
    required String title,
    required IconData icon,
    required Color color,
    required int totalUnits,
    required List<int> categoryIndices,
  }) {
    final allPicked = categoryIndices.isNotEmpty && categoryIndices.every((i) => _items[i].isPicked);

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (categoryIndices.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: () => _toggleCategoryPicked(categoryIndices),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                  icon: Icon(allPicked ? Icons.remove_done_rounded : Icons.done_all_rounded, size: 15),
                  label: Text(allPicked ? 'Uncheck' : 'Check All', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 4),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(
                  '$totalUnits ${totalUnits == 1 ? "unit" : "units"}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, thickness: 1),
        ],
      ),
    );
  }

  Widget _buildPicklistItemTile(int index, ColorScheme colorScheme) {
    final item = _items[index];
    final isPicked = item.isPicked;
    final onHand = _getOnHandStock(item);
    final reqQty = _getRequiredQty(item);
    final isShortage = onHand < reqQty;
    final isZero = onHand <= 0;
    final isOutOfStock = isPicked && item.pickedQuantity == 0;
    final isPartialPicked = isPicked && item.pickedQuantity > 0 && item.pickedQuantity < item.orderedQuantity;

    final Color tileBgColor;
    final BorderSide tileBorder;
    if (isOutOfStock) {
      tileBgColor = Colors.red.withValues(alpha: 0.05);
      tileBorder = BorderSide(color: Colors.red.shade300, width: 1.2);
    } else if (isPartialPicked) {
      tileBgColor = Colors.amber.withValues(alpha: 0.05);
      tileBorder = BorderSide(color: Colors.amber.shade300, width: 1.2);
    } else if (isPicked) {
      tileBgColor = Colors.green.withValues(alpha: 0.06);
      tileBorder = BorderSide(color: Colors.green.withValues(alpha: 0.45), width: 1.3);
    } else if (isZero) {
      tileBgColor = Colors.red.withValues(alpha: 0.03);
      tileBorder = BorderSide(color: Colors.red.shade300, width: 1.2);
    } else if (isShortage) {
      tileBgColor = Colors.amber.withValues(alpha: 0.03);
      tileBorder = BorderSide(color: Colors.amber.shade300, width: 1.2);
    } else {
      tileBgColor = colorScheme.surface;
      tileBorder = BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1.0);
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: tileBgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: tileBorder,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toggleItemPicked(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Transform.scale(
                scale: 1.15,
                child: Checkbox(
                  value: isPicked,
                  activeColor: isOutOfStock
                      ? Colors.red.shade700
                      : (isPartialPicked ? Colors.amber.shade800 : Colors.green.shade700),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: (_) => _toggleItemPicked(index),
                ),
              ),
              const SizedBox(width: 6),
              CachedProductImage(imageUrl: item.imageUrl, size: 44, borderRadius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: isOutOfStock
                            ? Colors.red.shade800
                            : (isPartialPicked
                                ? Colors.amber.shade900
                                : (isPicked ? Colors.green.shade800 : colorScheme.onSurface)),
                        decoration: isPicked ? TextDecoration.lineThrough : null,
                        decorationColor: isOutOfStock
                            ? Colors.red.shade700
                            : (isPartialPicked ? Colors.amber.shade700 : Colors.green.shade700),
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final barcode = _getEffectiveBarcode(item);
                        if (barcode.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.qr_code_2_rounded,
                                size: 13,
                                color: isOutOfStock
                                    ? Colors.red.shade600
                                    : (isPicked ? Colors.green.shade600 : colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                barcode,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: isOutOfStock
                                      ? Colors.red.shade600
                                      : (isPicked ? Colors.green.shade600 : colorScheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (isOutOfStock)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.remove_shopping_cart_outlined, size: 12, color: Colors.red.shade700),
                              const SizedBox(width: 4),
                              Text(
                                'OUT OF STOCK (0 of ${item.orderedQuantity} requested)',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (isPartialPicked)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 12, color: Colors.amber.shade900),
                              const SizedBox(width: 4),
                              Text(
                                'PARTIAL PICK (${item.pickedQuantity} of ${item.orderedQuantity} requested)',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (!isPicked) ...[
                      if (isZero)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cancel_outlined, size: 12, color: Colors.red.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  '0 on hand • Out of stock',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (isShortage)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 12, color: Colors.amber.shade900),
                                const SizedBox(width: 4),
                                Text(
                                  'Only $onHand on hand (Need $reqQty)',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            'On hand: $onHand',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isOutOfStock
                      ? Colors.red.withValues(alpha: 0.12)
                      : (isPartialPicked
                          ? Colors.amber.withValues(alpha: 0.15)
                          : (isPicked
                              ? Colors.green.withValues(alpha: 0.15)
                              : (isZero
                                  ? Colors.red.withValues(alpha: 0.1)
                                  : (isShortage ? Colors.amber.withValues(alpha: 0.15) : colorScheme.primary.withValues(alpha: 0.08))))),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isOutOfStock
                        ? Colors.red.shade300
                        : (isPartialPicked
                            ? Colors.amber.shade300
                            : (isPicked
                                ? Colors.green.withValues(alpha: 0.3)
                                : (isZero
                                    ? Colors.red.shade300
                                    : (isShortage ? Colors.amber.shade300 : colorScheme.primary.withValues(alpha: 0.2))))),
                  ),
                ),
                child: Text(
                  isOutOfStock
                      ? 'OOS (0)'
                      : (isPartialPicked
                          ? '${item.pickedQuantity}/${item.orderedQuantity}'
                          : '×${item.pickedQuantity}'),
                  style: TextStyle(
                    fontSize: isOutOfStock || isPartialPicked ? 12 : 14.5,
                    fontWeight: FontWeight.w800,
                    color: isOutOfStock
                        ? Colors.red.shade700
                        : (isPartialPicked
                            ? Colors.amber.shade900
                            : (isPicked
                                ? Colors.green.shade700
                                : (isZero
                                    ? Colors.red.shade700
                                    : (isShortage ? Colors.amber.shade900 : colorScheme.primary)))),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProofOfDeliveryCard(ColorScheme colorScheme) {
    final hasImage = _hasProofOfDelivery;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(top: 6, bottom: 8),
      color: hasImage ? Colors.green.withValues(alpha: 0.04) : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: hasImage ? Colors.green.withValues(alpha: 0.5) : Colors.amber.shade600.withValues(alpha: 0.6), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: hasImage ? Colors.green.withValues(alpha: 0.12) : Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    hasImage ? Icons.verified_outlined : Icons.camera_alt_outlined,
                    size: 18,
                    color: hasImage ? Colors.green.shade700 : Colors.amber.shade900,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      const Text('Proof of Delivery', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: hasImage ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          hasImage ? 'Attached' : 'Required',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: hasImage ? Colors.green.shade800 : Colors.red.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasImage)
                  TextButton.icon(
                    onPressed: _showImageSourceSelector,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    icon: const Icon(Icons.replay, size: 15),
                    label: const Text('Retake', style: TextStyle(fontSize: 12.5)),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: _showImageSourceSelector,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                    label: const Text('Attach', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (hasImage) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () => Helperfunctions.navigateTo(context, ImageViewerPage(image: _pickedImage, networkImagePath: _networkImagePath)),
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Container(
                        height: 160,
                        width: double.infinity,
                        color: Colors.black12,
                        child: _pickedImage != null
                            ? Image.file(_pickedImage!, fit: BoxFit.cover)
                            : Image.network(
                                _networkImagePath,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(child: CircularProgressIndicator());
                                },
                                errorBuilder: (_, _, _) => Container(
                                  height: 160,
                                  color: colorScheme.surfaceContainerHighest,
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.broken_image_outlined, size: 32, color: colorScheme.onSurfaceVariant),
                                      const SizedBox(height: 4),
                                      Text('Unable to load image', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.zoom_in, color: Colors.white, size: 15),
                            SizedBox(width: 4),
                            Text(
                              'Tap to view full screen',
                              style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Helperfunctions.navigateTo(context, ImageViewerPage(image: _pickedImage, networkImagePath: _networkImagePath)),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.fullscreen, size: 16),
                      label: const Text('View Full Screen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: _removeImage,
                    tooltip: 'Remove Image',
                    style: IconButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade200),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
            ] else ...[
              InkWell(
                onTap: _showImageSourceSelector,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade300, style: BorderStyle.solid),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.amber.shade100, shape: BoxShape.circle),
                        child: Icon(Icons.add_a_photo_outlined, size: 22, color: Colors.amber.shade900),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Attach Proof of Delivery photo',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Take photo of signed receipt or items to enable "For Delivery"',
                              style: TextStyle(fontSize: 11.5, color: Colors.amber.shade800),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.amber.shade900),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStickyBottomBar(ColorScheme colorScheme, {bool isEmbedded = false}) {
    final hasProof = _hasProofOfDelivery;
    final canComplete = !_isSaving && _allItemsPicked && hasProof;

    final content = Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6))),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_allItemsPicked && !hasProof)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: _showImageSourceSelector,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade400),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.camera_alt_outlined, size: 18, color: Colors.amber.shade900),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Proof of Delivery photo is required before clicking For Delivery.',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Attach',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                if (_isDealer) ...[
                  IconButton.outlined(
                    onPressed: _isSaving ? null : _onVoidOrder,
                    tooltip: 'Void Order',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.block, size: 22),
                  ),
                  const SizedBox(width: 8),
                  if (_isAdmin) ...[
                    IconButton.outlined(
                      onPressed: _isSaving ? null : _onAdminDeleteOrder,
                      tooltip: 'Delete Record (Admin)',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        foregroundColor: Colors.red.shade900,
                        backgroundColor: Colors.red.shade50,
                        side: BorderSide(color: Colors.red.shade400),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.delete_forever, size: 22),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
                Expanded(
                  flex: 2,
                  child: AsyncOutlinedButton(
                    onPressed: _onSaveProgress,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      'Save Draft',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: AsyncFilledButton.icon(
                    onPressed: canComplete ? _onCompletePicklist : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.local_shipping_outlined, size: 20),
                    label: const Text(
                      'For Delivery',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    if (isEmbedded) return content;
    return SafeArea(child: content);
  }

  Widget _buildOrderStoreSummaryCard(ColorScheme colorScheme, DateTime deliveryDate) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.storefront_rounded, size: 22, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentDelivery.storeName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Delivery: ${Helperfunctions.formatDateForDisplay(deliveryDate)}',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _currentDelivery.transactionStatus == DeliveryStatus.delivered
                        ? Colors.green.shade50
                        : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _currentDelivery.transactionStatus == DeliveryStatus.delivered
                          ? Colors.green.shade300
                          : Colors.blue.shade300,
                    ),
                  ),
                  child: Text(
                    _currentDelivery.transactionStatus,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _currentDelivery.transactionStatus == DeliveryStatus.delivered
                          ? Colors.green.shade800
                          : Colors.blue.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order Amount:', style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
                Text(
                  Helperfunctions.formatDoubleAmountForDisplay(_currentDelivery.orderAmount),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (_currentDelivery.remarks.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Remarks: ', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  Expanded(
                    child: Text(
                      _currentDelivery.remarks,
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdownCard(
    ColorScheme colorScheme, {
    required int caseCount,
    required int caseUnits,
    required int pieceCount,
    required int pieceUnits,
    required int otherCount,
    required int otherUnits,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Fulfillment Breakdown', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildBreakdownBadge(
                    label: 'By Case',
                    count: caseCount,
                    units: caseUnits,
                    color: Colors.deepOrange.shade700,
                    bgColor: Colors.deepOrange.shade50,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildBreakdownBadge(
                    label: 'By Piece',
                    count: pieceCount,
                    units: pieceUnits,
                    color: colorScheme.primary,
                    bgColor: colorScheme.primary.withValues(alpha: 0.08),
                  ),
                ),
                if (otherCount > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildBreakdownBadge(
                      label: 'Other',
                      count: otherCount,
                      units: otherUnits,
                      color: Colors.purple.shade700,
                      bgColor: Colors.purple.shade50,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownBadge({
    required String label,
    required int count,
    required int units,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 2),
          Text(
            '$count SKUs • $units units',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLandscapeView(
    ColorScheme colorScheme,
    DateTime deliveryDate,
    List<int> visibleSelectaCase,
    List<int> visibleSelectaPiece,
    List<int> visibleOther,
    int Function(List<int>) calcUnits,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left Pane: Store Info, Picklist Progress, Breakdown & Actions (flex: 4)
        Expanded(
          flex: 4,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildOrderStoreSummaryCard(colorScheme, deliveryDate),
                      _buildProgressHeader(colorScheme, isCompact: true),
                      _buildCategoryBreakdownCard(
                        colorScheme,
                        caseCount: _selectaCaseIndices.length,
                        caseUnits: calcUnits(_selectaCaseIndices),
                        pieceCount: _selectaPieceIndices.length,
                        pieceUnits: calcUnits(_selectaPieceIndices),
                        otherCount: _otherIndices.length,
                        otherUnits: calcUnits(_otherIndices),
                      ),
                      _buildProofOfDeliveryCard(colorScheme),
                    ],
                  ),
                ),
              ),
              _buildStickyBottomBar(colorScheme, isEmbedded: true),
            ],
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        // Right Pane: Filter Chips & Item Verification List (flex: 6)
        Expanded(
          flex: 6,
          child: Column(
            children: [
              if (_items.isNotEmpty) _buildFilterChips(colorScheme),
              Expanded(
                child: _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shopping_basket_outlined, size: 44, color: colorScheme.onSurfaceVariant),
                              const SizedBox(height: 10),
                              Text(
                                'No products in this order yet.',
                                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13.5, fontWeight: FontWeight.w700),
                              ),
                              if (_isDealer) ...[
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: _openEditOrderProducts,
                                  icon: const Icon(Icons.edit_note_rounded, size: 20),
                                  label: const Text('Edit Order', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : (visibleSelectaCase.isEmpty && visibleSelectaPiece.isEmpty && visibleOther.isEmpty)
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _itemFilter == 'Pending' ? Icons.task_alt_rounded : Icons.checklist_rtl_rounded,
                                    size: 44,
                                    color: _itemFilter == 'Pending' ? Colors.green.shade600 : colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _itemFilter == 'Pending' ? 'All items in this order have been checked!' : 'No products match this filter.',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton(onPressed: () => setState(() => _itemFilter = 'All'), child: const Text('Show All Items')),
                                ],
                              ),
                            ),
                          )
                        : ListView(
                            primary: false,
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(12, 4, 16, 24),
                            children: [
                              if (visibleSelectaCase.isNotEmpty) ...[
                                _buildGroupHeader(
                                  title: 'By Case',
                                  icon: Icons.all_inbox_rounded,
                                  color: Colors.deepOrange.shade700,
                                  totalUnits: calcUnits(visibleSelectaCase),
                                  categoryIndices: visibleSelectaCase,
                                ),
                                ...visibleSelectaCase.map((idx) => _buildPicklistItemTile(idx, colorScheme)),
                              ],
                              if (visibleSelectaPiece.isNotEmpty) ...[
                                _buildGroupHeader(
                                  title: 'By Piece',
                                  icon: Icons.icecream_outlined,
                                  color: colorScheme.primary,
                                  totalUnits: calcUnits(visibleSelectaPiece),
                                  categoryIndices: visibleSelectaPiece,
                                ),
                                ...visibleSelectaPiece.map((idx) => _buildPicklistItemTile(idx, colorScheme)),
                              ],
                              if (visibleOther.isNotEmpty) ...[
                                _buildGroupHeader(
                                  title: 'Other Products',
                                  icon: Icons.inventory_2_outlined,
                                  color: colorScheme.onSurfaceVariant,
                                  totalUnits: calcUnits(visibleOther),
                                  categoryIndices: visibleOther,
                                ),
                                ...visibleOther.map((idx) => _buildPicklistItemTile(idx, colorScheme)),
                              ],
                            ],
                          ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitLayout(
    ColorScheme colorScheme,
    List<int> visibleSelectaCase,
    List<int> visibleSelectaPiece,
    List<int> visibleOther,
    int Function(List<int>) calcUnits,
  ) {
    return Column(
      children: [
        _buildProgressHeader(colorScheme),
        if (_items.isNotEmpty) _buildFilterChips(colorScheme),
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_basket_outlined, size: 44, color: colorScheme.onSurfaceVariant),
                        const SizedBox(height: 10),
                        Text(
                          'No products in this order yet.',
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        if (_isDealer) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _openEditOrderProducts,
                            icon: const Icon(Icons.edit_note_rounded, size: 20),
                            label: const Text('Edit Order', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : (visibleSelectaCase.isEmpty && visibleSelectaPiece.isEmpty && visibleOther.isEmpty)
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _itemFilter == 'Pending' ? Icons.task_alt_rounded : Icons.checklist_rtl_rounded,
                              size: 44,
                              color: _itemFilter == 'Pending' ? Colors.green.shade600 : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _itemFilter == 'Pending' ? 'All items in this order have been checked!' : 'No products match this filter.',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(onPressed: () => setState(() => _itemFilter = 'All'), child: const Text('Show All Items')),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      primary: false,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        if (visibleSelectaCase.isNotEmpty) ...[
                          _buildGroupHeader(
                            title: 'By Case',
                            icon: Icons.all_inbox_rounded,
                            color: Colors.deepOrange.shade700,
                            totalUnits: calcUnits(visibleSelectaCase),
                            categoryIndices: visibleSelectaCase,
                          ),
                          ...visibleSelectaCase.map((idx) => _buildPicklistItemTile(idx, colorScheme)),
                        ],
                        if (visibleSelectaPiece.isNotEmpty) ...[
                          _buildGroupHeader(
                            title: 'By Piece',
                            icon: Icons.icecream_outlined,
                            color: colorScheme.primary,
                            totalUnits: calcUnits(visibleSelectaPiece),
                            categoryIndices: visibleSelectaPiece,
                          ),
                          ...visibleSelectaPiece.map((idx) => _buildPicklistItemTile(idx, colorScheme)),
                        ],
                        if (visibleOther.isNotEmpty) ...[
                          _buildGroupHeader(
                            title: 'Other Products',
                            icon: Icons.inventory_2_outlined,
                            color: colorScheme.onSurfaceVariant,
                            totalUnits: calcUnits(visibleOther),
                            categoryIndices: visibleOther,
                          ),
                          ...visibleOther.map((idx) => _buildPicklistItemTile(idx, colorScheme)),
                        ],
                        _buildProofOfDeliveryCard(colorScheme),
                      ],
                    ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final deliveryDate = _currentDelivery.deliveryDate?.toDate() ?? DateTime.now();
    final isTabletLandscape = ScreenSize.isTabletLandscape(context);

    List<int> filterIndices(List<int> indices) {
      if (_itemFilter == 'All') return indices;
      if (_itemFilter == 'Pending') {
        return indices.where((i) => !_items[i].isPicked).toList();
      }
      return indices.where((i) => _items[i].isPicked).toList();
    }

    final visibleSelectaCase = filterIndices(_selectaCaseIndices);
    final visibleSelectaPiece = filterIndices(_selectaPieceIndices);
    final visibleOther = filterIndices(_otherIndices);

    int calcUnits(List<int> idxs) => idxs.fold<int>(0, (total, i) => total + _items[i].pickedQuantity);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isSaving) return;
        if (_hasUnsavedChanges) {
          final shouldDiscard = await ShowMessage.confirm(
            context,
            title: 'Discard Changes?',
            message: 'You have unsaved picklist progress. Are you sure you want to leave without saving?',
            confirmText: 'Discard',
            isDestructive: true,
          );
          if (shouldDiscard && context.mounted) {
            Navigator.pop(context);
          }
        } else {
          Navigator.pop(context);
        }
      },
      child: KeyboardListener(
        focusNode: _scannerFocusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          appBar: CustomAppbar(
            title: _currentDelivery.storeName,
            subtitle: 'Picklist • ${Helperfunctions.formatDateForDisplay(deliveryDate)}',
            centerTitle: false,
            onBackPressed: _isSaving ? () {} : null,
            actions: [
              if (_enableBarcodeScanner)
                _buildAppBarIconAction(icon: Icons.qr_code_scanner_rounded, tooltip: 'Scan Barcode', onTap: _isSaving ? null : _openCameraScanner),
              if (_isDealer) ...[
                if (_enableBarcodeScanner) const SizedBox(width: 6),
                _buildAppBarIconAction(
                  icon: Icons.edit_note_rounded,
                  tooltip: 'Edit Order in Book Order Page',
                  onTap: _isSaving ? null : _openEditOrderProducts,
                ),
              ],
            ],
          ),
          bottomNavigationBar: isTabletLandscape ? null : _buildStickyBottomBar(colorScheme),
          body: isTabletLandscape
              ? _buildTabletLandscapeView(
                  colorScheme,
                  deliveryDate,
                  visibleSelectaCase,
                  visibleSelectaPiece,
                  visibleOther,
                  calcUnits,
                )
              : _buildPortraitLayout(
                  colorScheme,
                  visibleSelectaCase,
                  visibleSelectaPiece,
                  visibleOther,
                  calcUnits,
                ),
        ),
      ),
    );
  }
}
