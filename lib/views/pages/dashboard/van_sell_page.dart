import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/van_sell_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/van_load.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/views/widgets/digital_receipt_dialog.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:selecta_ops/views/widgets/book_order/product_order_card.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';
import 'package:selecta_ops/views/widgets/snackbar_widget.dart';
import 'package:selecta_ops/data/responsive.dart';

class VanSellPage extends StatefulWidget {
  final String? preselectedStoreName;

  const VanSellPage({super.key, this.preselectedStoreName});

  @override
  State<VanSellPage> createState() => _VanSellPageState();
}

class _VanSellPageState extends State<VanSellPage> {
  final VanSellController _controller = VanSellController();
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _storeSearchController = TextEditingController();
  final TextEditingController _productSearchController = TextEditingController();

  VanLoad? _activeVanLoad;
  StreamSubscription? _vanLoadSub;

  List<Hapistore> _allStores = [];
  Set<String> _buyingStoreNames = {};
  bool _isLoadingStores = true;
  bool _filterOnlyNonBuying = false;

  Hapistore? _selectedStore;
  final Map<String, int> _sellQuantities = {}; // productId -> quantity
  File? _proofImage;
  final ImagePicker _picker = ImagePicker();

  bool _isSaving = false;
  String _productSearchQuery = '';

  bool get _hasUnsavedChanges =>
      _selectedStore != null ||
      _sellQuantities.values.any((q) => q > 0) ||
      _remarksController.text.trim().isNotEmpty ||
      _proofImage != null;

  @override
  void initState() {
    super.initState();
    _subscribeActiveVanLoad();
    _loadStoresAndBuyingStatus();
  }

  @override
  void dispose() {
    _vanLoadSub?.cancel();
    _remarksController.dispose();
    _storeSearchController.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  void _subscribeActiveVanLoad() {
    _vanLoadSub = _controller.streamActiveVanLoad().listen((load) {
      if (!mounted) return;
      setState(() {
        _activeVanLoad = load;
        // Clamp existing sell quantities against new available quantities if load changed
        if (load != null) {
          final Map<String, int> available = {
            for (final vi in load.items) vi.productId: vi.availableQuantity
          };
          _sellQuantities.removeWhere((id, qty) {
            final max = available[id] ?? 0;
            return max <= 0;
          });
          _sellQuantities.forEach((id, qty) {
            final max = available[id] ?? 0;
            if (qty > max) {
              _sellQuantities[id] = max;
            }
          });
        }
      });
    });
  }

  Future<void> _loadStoresAndBuyingStatus() async {
    setState(() => _isLoadingStores = true);
    try {
      final buyingSet = await _controller.getBuyingStoreNamesCurrentMonth();
      final storeSnap = await FirebaseFirestore.instance
          .collection(HAPISTORE_COLLECTION_REF)
          .orderBy('storeName')
          .get();

      final stores = storeSnap.docs
          .map((d) => Hapistore.fromJson(d.data()))
          .where((s) => s.storeName.trim().isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _allStores = stores;
        _buyingStoreNames = buyingSet;
        _isLoadingStores = false;

        if (widget.preselectedStoreName != null && widget.preselectedStoreName!.isNotEmpty) {
          _selectedStore = stores
              .where((s) => s.storeName.trim().toLowerCase() == widget.preselectedStoreName!.trim().toLowerCase())
              .firstOrNull;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingStores = false);
    }
  }

  bool _isNonBuying(Hapistore store) {
    return !_buyingStoreNames.contains(store.storeName.trim().toLowerCase());
  }

  void _updateQuantity(String productId, int newQty, int availableMax) {
    final clamped = newQty.clamp(0, availableMax);
    setState(() {
      if (clamped <= 0) {
        _sellQuantities.remove(productId);
      } else {
        _sellQuantities[productId] = clamped;
      }
    });
  }

  Future<void> _showQuantityDialog(VanLoadItem item, int currentQty, int maxAllowed) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final defaultQty = currentQty > 0 ? currentQty : (maxAllowed >= 1 ? 1 : 0);
    final initialText = defaultQty > 0 ? '$defaultQty' : '';
    final controller = TextEditingController(text: initialText)
      ..selection = TextSelection(baseOffset: 0, extentOffset: initialText.length);

    final entered = await showDialog<int>(
      context: context,
      builder: (dCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            void setVal(int v) {
              final clamped = v.clamp(0, maxAllowed);
              final text = clamped > 0 ? '$clamped' : '';
              controller.value = TextEditingValue(
                text: text,
                selection: TextSelection(baseOffset: 0, extentOffset: text.length),
              );
              setDialogState(() {});
            }

            return AlertDialog(
              title: Text(item.productName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available on Van: $maxAllowed',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: '0',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(label: const Text('+1'), onPressed: () => setVal((int.tryParse(controller.text) ?? 0) + 1)),
                      ActionChip(label: const Text('+5'), onPressed: () => setVal((int.tryParse(controller.text) ?? 0) + 5)),
                      ActionChip(label: const Text('+10'), onPressed: () => setVal((int.tryParse(controller.text) ?? 0) + 10)),
                      ActionChip(label: const Text('Max'), onPressed: () => setVal(maxAllowed)),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () {
                    final qty = int.tryParse(controller.text.trim()) ?? 0;
                    Navigator.pop(dCtx, qty);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (entered != null) {
      _updateQuantity(item.productId, entered, maxAllowed);
    }
  }

  int get _totalSellUnits {
    return _sellQuantities.values.fold<int>(0, (acc, q) => acc + q);
  }

  double get _totalSellAmount {
    if (_activeVanLoad == null) return 0.0;
    double total = 0.0;
    final Map<String, double> priceMap = {
      for (final vi in _activeVanLoad!.items) vi.productId: vi.sellingPrice
    };
    for (final entry in _sellQuantities.entries) {
      final price = priceMap[entry.key] ?? 0.0;
      total += price * entry.value;
    }
    return total;
  }

  List<OrderItem> _buildOrderItems() {
    if (_activeVanLoad == null) return [];
    final List<OrderItem> items = [];
    for (final entry in _sellQuantities.entries) {
      if (entry.value <= 0) continue;
      final vanItem = _activeVanLoad!.items.where((i) => i.productId == entry.key).firstOrNull;
      if (vanItem != null) {
        items.add(OrderItem(
          productId: vanItem.productId,
          productName: vanItem.productName,
          imageUrl: vanItem.imageUrl,
          barcode: vanItem.barcode,
          productSource: vanItem.productSource,
          category: vanItem.category,
          tag: vanItem.tag,
          buyingPrice: vanItem.buyingPrice,
          sellingPrice: vanItem.sellingPrice,
          orderedQuantity: entry.value,
          pickedQuantity: entry.value,
          returnedQuantity: 0,
          isPicked: true,
        ));
      }
    }
    return items;
  }

  Future<void> _onCompleteAndPrint() async {
    if (_activeVanLoad == null) {
      SnackBarWidget.error(context, 'No active Van Load found. Please ask Dealer to load van first.');
      return;
    }

    if (_selectedStore == null) {
      SnackBarWidget.error(context, 'Please select a registered Hapi Store.');
      return;
    }

    final items = _buildOrderItems();
    if (items.isEmpty) {
      SnackBarWidget.error(context, 'Please add at least 1 product from van stock.');
      return;
    }

    await _showSaleConfirmationDialog(items);
  }

  Future<void> _showSaleConfirmationDialog(List<OrderItem> items) async {
    final targetTotal = _totalSellAmount;
    final totalUnits = _totalSellUnits;
    final store = _selectedStore!;

    // Initial payment controllers - default to Full Cash for convenience
    final txtCash = TextEditingController(text: targetTotal > 0 ? targetTotal.toStringAsFixed(2) : '0.00');
    final txtOnline = TextEditingController();
    final txtCredit = TextEditingController();
    final txtDialogRemarks = TextEditingController(text: _remarksController.text.trim());

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final cashVal = double.tryParse(txtCash.text.trim()) ?? 0.0;
            final onlineVal = double.tryParse(txtOnline.text.trim()) ?? 0.0;
            final creditVal = double.tryParse(txtCredit.text.trim()) ?? 0.0;
            final totalAccounted = cashVal + onlineVal + creditVal;
            final diff = totalAccounted - targetTotal;
            final isBalanced = diff.abs() < 0.01;
            final isOver = diff >= 0.01;

            final Color badgeColor = isBalanced
                ? Colors.green.shade700
                : (isOver ? Colors.orange.shade800 : Colors.red.shade700);
            final Color badgeBgColor = isBalanced
                ? Colors.green.shade50
                : (isOver ? Colors.orange.shade50 : Colors.red.shade50);
            final Color badgeBorderColor = isBalanced
                ? Colors.green.shade300
                : (isOver ? Colors.orange.shade300 : Colors.red.shade300);

            void quickFill(String target) {
              final formatted = targetTotal.toStringAsFixed(2);
              setDialogState(() {
                if (target == 'cash') {
                  txtCash.text = formatted;
                  txtOnline.clear();
                  txtCredit.clear();
                } else if (target == 'online') {
                  txtOnline.text = formatted;
                  txtCash.clear();
                  txtCredit.clear();
                } else if (target == 'credit') {
                  txtCredit.text = formatted;
                  txtCash.clear();
                  txtOnline.clear();
                } else {
                  txtCash.clear();
                  txtOnline.clear();
                  txtCredit.clear();
                }
              });
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.check_circle_outline, color: Colors.teal, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Confirm Van Sale', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('Review order & payment details', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(ctx).size.width * 0.9,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // Customer Store info card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.storefront_outlined, color: Colors.teal.shade700, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    store.storeName,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                  if (store.storeAddress.isNotEmpty)
                                    Text(
                                      store.storeAddress,
                                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Sale Summary: Units and Total
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.teal.shade100),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total Items', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                                Text('$totalUnits units (${items.length} SKUs)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('Total Amount', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                                Text(
                                  Helperfunctions.formatDoubleAmountForDisplay(targetTotal),
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Quick-Fill Chips
                      Row(
                        children: [
                          Icon(Icons.bolt, size: 16, color: Colors.amber.shade800),
                          const SizedBox(width: 4),
                          const Text(
                            'Quick-Fill Payment:',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ActionChip(
                              avatar: const Icon(Icons.payments_outlined, size: 16, color: Colors.teal),
                              label: const Text('Full Cash', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              onPressed: () => quickFill('cash'),
                            ),
                            const SizedBox(width: 6),
                            ActionChip(
                              avatar: const Icon(Icons.account_balance_outlined, size: 16, color: Colors.teal),
                              label: const Text('Full Online', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              onPressed: () => quickFill('online'),
                            ),
                            const SizedBox(width: 6),
                            ActionChip(
                              avatar: const Icon(Icons.credit_card_outlined, size: 16, color: Colors.teal),
                              label: const Text('Full Credit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              onPressed: () => quickFill('credit'),
                            ),
                            const SizedBox(width: 6),
                            ActionChip(
                              avatar: Icon(Icons.restart_alt, size: 16, color: Colors.red.shade700),
                              label: Text('Clear', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
                              onPressed: () => quickFill('clear'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Cash, Online, Credit Input Fields
                      _buildPaymentAmountField(
                        label: 'Cash Amount',
                        controller: txtCash,
                        icon: Icons.payments_outlined,
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 10),
                      _buildPaymentAmountField(
                        label: 'Online Amount',
                        controller: txtOnline,
                        icon: Icons.account_balance_outlined,
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 10),
                      _buildPaymentAmountField(
                        label: 'Credit Amount',
                        controller: txtCredit,
                        icon: Icons.credit_card_outlined,
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),

                      // Balance status badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: badgeBgColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: badgeBorderColor, width: 1.2),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isBalanced ? Icons.check_circle : (isOver ? Icons.error_outline : Icons.warning_amber_rounded),
                              size: 20,
                              color: badgeColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isBalanced
                                        ? 'Payment Balanced'
                                        : (isOver
                                            ? 'Overpaid by ${Helperfunctions.formatDoubleAmountForDisplay(diff.abs())}'
                                            : 'Short by ${Helperfunctions.formatDoubleAmountForDisplay(diff.abs())}'),
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: badgeColor),
                                  ),
                                  Text(
                                    'Accounted: ${Helperfunctions.formatDoubleAmountForDisplay(totalAccounted)} / Target: ${Helperfunctions.formatDoubleAmountForDisplay(targetTotal)}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Remarks field
                      TextField(
                        controller: txtDialogRemarks,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Remarks (Optional)',
                          hintText: 'e.g., GCash ref#, notes, etc.',
                          prefixIcon: const Icon(Icons.note_alt_outlined, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Proof of Van Selling section (Required)
                      _buildDialogProofSection(dialogCtx, setDialogState),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('Cancel / Keep Editing'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: (isBalanced && _proofImage != null) ? Colors.teal : Colors.grey,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Confirm & Complete'),
                  onPressed: () {
                    if (!isBalanced) {
                      SnackBarWidget.error(context, 'Payment must balance with total amount before completing.');
                      return;
                    }
                    if (_proofImage == null) {
                      SnackBarWidget.error(context, 'Please upload proof of van selling before completing.');
                      return;
                    }
                    Navigator.pop(dialogCtx, true);
                  },
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true && mounted) {
      final cash = double.tryParse(txtCash.text.trim()) ?? 0.0;
      final online = double.tryParse(txtOnline.text.trim()) ?? 0.0;
      final credit = double.tryParse(txtCredit.text.trim()) ?? 0.0;
      final remarks = txtDialogRemarks.text.trim();

      String method;
      if (cash > 0 && online == 0 && credit == 0) {
        method = 'Cash';
      } else if (online > 0 && cash == 0 && credit == 0) {
        method = 'Online';
      } else if (credit > 0 && cash == 0 && online == 0) {
        method = 'Credit';
      } else {
        method = 'Split';
      }

      await _executeSaleWithPayment(
        items: items,
        paymentMethod: method,
        cashAmount: cash,
        onlineAmount: online,
        creditAmount: credit,
        remarks: remarks,
      );
    }

    txtCash.dispose();
    txtOnline.dispose();
    txtCredit.dispose();
    txtDialogRemarks.dispose();
  }

  Widget _buildPaymentAmountField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
      textAlign: TextAlign.end,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        prefixIcon: Icon(icon, size: 20, color: Colors.teal),
        prefixText: '₱ ',
        prefixStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        hintText: '0.00',
      ),
    );
  }

  Future<void> _pickProofImage(ImageSource source, [StateSetter? setDialogState]) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          _proofImage = File(pickedFile.path);
        });
        setDialogState?.call(() {});
      }
    } catch (e) {
      if (mounted) {
        SnackBarWidget.error(context, 'Failed to capture image: $e');
      }
    }
  }

  void _showImageSourceSelector([StateSetter? setDialogState]) {
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
                  child: Text('Attach Proof of Van Selling', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                ),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.withValues(alpha: 0.1),
                  child: const Icon(Icons.camera_alt_outlined, color: Colors.teal),
                ),
                title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Capture with camera'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickProofImage(ImageSource.camera, setDialogState);
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.withValues(alpha: 0.1),
                  child: const Icon(Icons.photo_library_outlined, color: Colors.teal),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Select existing photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickProofImage(ImageSource.gallery, setDialogState);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removeProofImage([StateSetter? setDialogState]) async {
    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Remove Image',
      message: 'Are you sure you want to remove the attached Proof of Van Selling image?',
      icon: Icons.delete_outline,
      confirmText: 'Remove',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _proofImage = null;
    });
    setDialogState?.call(() {});
  }

  Widget _buildDialogProofSection(BuildContext ctx, StateSetter setDialogState) {
    final hasProof = _proofImage != null;

    return Container(
      decoration: BoxDecoration(
        color: hasProof ? Colors.green.withValues(alpha: 0.04) : Colors.amber.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasProof ? Colors.green.withValues(alpha: 0.4) : Colors.amber.shade700,
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: hasProof ? Colors.green.withValues(alpha: 0.12) : Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  hasProof ? Icons.verified_outlined : Icons.camera_alt_outlined,
                  size: 16,
                  color: hasProof ? Colors.green.shade800 : Colors.amber.shade900,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      'Proof of Van Selling',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: hasProof ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        hasProof ? 'Attached' : 'Required',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: hasProof ? Colors.green.shade800 : Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasProof)
                TextButton.icon(
                  onPressed: () => _showImageSourceSelector(setDialogState),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  ),
                  icon: const Icon(Icons.replay, size: 14),
                  label: const Text('Retake', style: TextStyle(fontSize: 11.5)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasProof) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => Helperfunctions.navigateTo(context, ImageViewerPage(image: _proofImage, networkImagePath: '')),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Image.file(
                      _proofImage!,
                      height: 130,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
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
                          Icon(Icons.zoom_in, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Tap to view full screen',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Helperfunctions.navigateTo(context, ImageViewerPage(image: _proofImage, networkImagePath: '')),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.fullscreen, size: 15),
                    label: const Text('View Full Screen', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.outlined(
                  onPressed: () => _removeProofImage(setDialogState),
                  tooltip: 'Remove Image',
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade200),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 16),
                ),
              ],
            ),
          ] else ...[
            InkWell(
              onTap: () => _showImageSourceSelector(setDialogState),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300, style: BorderStyle.solid),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_a_photo_outlined, size: 28, color: Colors.teal.shade700),
                    const SizedBox(height: 6),
                    Text(
                      'Attach Proof of Van Selling',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Take a photo with camera or choose from gallery',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMainScreenProofBanner() {
    final hasProof = _proofImage != null;

    return Container(
      decoration: BoxDecoration(
        color: hasProof ? Colors.green.withValues(alpha: 0.05) : Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasProof ? Colors.green.withValues(alpha: 0.4) : Colors.amber.shade600.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: hasProof
              ? () => Helperfunctions.navigateTo(context, ImageViewerPage(image: _proofImage, networkImagePath: ''))
              : () => _showImageSourceSelector(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                if (hasProof)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(_proofImage!, width: 40, height: 40, fit: BoxFit.cover),
                  )
                else
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.add_a_photo_outlined, color: Colors.amber.shade900, size: 20),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Proof of Van Selling',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: hasProof ? Colors.green.shade900 : Colors.amber.shade900,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: hasProof ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              hasProof ? 'ATTACHED' : 'REQUIRED',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: hasProof ? Colors.green.shade800 : Colors.red.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasProof
                            ? 'Tap to inspect or change photo'
                            : 'Upload photo of store handover / transaction',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (hasProof) ...[
                  IconButton(
                    icon: const Icon(Icons.replay, size: 18),
                    color: Colors.grey.shade700,
                    tooltip: 'Retake Photo',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showImageSourceSelector(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: Colors.red.shade700,
                    tooltip: 'Remove Photo',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _removeProofImage(),
                  ),
                ] else
                  FilledButton.tonal(
                    onPressed: () => _showImageSourceSelector(),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    child: const Text('Attach', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _executeSaleWithPayment({
    required List<OrderItem> items,
    required String paymentMethod,
    required double cashAmount,
    required double onlineAmount,
    required double creditAmount,
    required String remarks,
  }) async {
    if (_proofImage == null) {
      SnackBarWidget.error(context, 'Proof of van selling photo is required.');
      return;
    }

    final statusNotifier = ValueNotifier<String>('Uploading proof photo...');
    setState(() => _isSaving = true);

    await Helperfunctions.showLoading(
      context: context,
      showLoading: true,
      statusNotifier: statusNotifier,
      message: 'Processing van sale...',
      subtitle: 'Please wait, do not close or exit the app.',
    );
    if (!mounted) {
      statusNotifier.dispose();
      return;
    }

    try {
      // 1. Upload proof photo to Firebase Storage
      final uploadedImageUrl = await Helperfunctions.saveImage(context, _proofImage!);

      if (mounted) {
        statusNotifier.value = 'Recording sale...';
      }

      // 2. Complete van sale record in Firestore
      final result = await _controller.completeVanSale(
        vanLoad: _activeVanLoad!,
        store: _selectedStore!,
        items: items,
        paymentMethod: paymentMethod,
        cashAmount: cashAmount,
        onlineAmount: onlineAmount,
        creditAmount: creditAmount,
        remarks: remarks,
        imagePath: uploadedImageUrl,
      );

      await Helperfunctions.showLoading(showLoading: false);

      if (!mounted) return;

      SnackBarWidget.success(context, 'Van Sale recorded for ${_selectedStore!.storeName}!');

      // Prompt for thermal print
      await _promptThermalPrint(result.delivery, result.deliveryId);

      // If opened for a specific store from PJP visit, pop back with true
      if (widget.preselectedStoreName != null && mounted) {
        Navigator.pop(context, true);
        return;
      }

      // Reset form for next customer
      if (mounted) {
        setState(() {
          _selectedStore = null;
          _sellQuantities.clear();
          _remarksController.clear();
          _proofImage = null;
        });
      }
    } catch (e) {
      await Helperfunctions.showLoading(showLoading: false);
      if (mounted) SnackBarWidget.error(context, 'Failed to complete sale: $e');
    } finally {
      statusNotifier.dispose();
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _promptThermalPrint(Delivery delivery, String deliveryId) async {
    await DigitalReceiptDialog.show(
      context,
      delivery: delivery,
      deliveryId: deliveryId,
      proceedLabel: 'Done',
      remindIfNotPrinted: true,
    );
  }

  void _showStoreSelectionModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          final query = _storeSearchController.text.trim().toLowerCase();
          final filtered = _allStores.where((s) {
            final matchesQuery = query.isEmpty ||
                s.storeName.toLowerCase().contains(query) ||
                s.storeAddress.toLowerCase().contains(query);
            final isNonBuying = _isNonBuying(s);
            final matchesFilter = !_filterOnlyNonBuying || isNonBuying;
            return matchesQuery && matchesFilter;
          }).toList();

          return Container(
            height: MediaQuery.of(ctx).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Select Registered Hapi Store', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                // Search bar
                TextField(
                  controller: _storeSearchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search store name or address...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                  onChanged: (val) => setModalState(() {}),
                ),
                const SizedBox(height: 8),
                // Filter chip for Non-Buying stores
                Row(
                  children: [
                    FilterChip(
                      label: const Text('⚠️ Non-Buying Stores (0 orders this month)'),
                      selected: _filterOnlyNonBuying,
                      selectedColor: Colors.amber.shade100,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _filterOnlyNonBuying ? Colors.amber.shade900 : Colors.black87,
                      ),
                      onSelected: (val) {
                        setModalState(() => _filterOnlyNonBuying = val);
                        setState(() => _filterOnlyNonBuying = val);
                      },
                    ),
                  ],
                ),
                const Divider(height: 16),
                Expanded(
                  child: _isLoadingStores
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? Center(child: Text('No stores found', style: TextStyle(color: Colors.grey.shade600)))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final store = filtered[i];
                            final isNonBuying = _isNonBuying(store);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isNonBuying ? Colors.amber.shade50 : Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.storefront_outlined,
                                  color: isNonBuying ? Colors.amber.shade800 : Colors.teal,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(store.storeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                                  ),
                                  if (isNonBuying)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'NON-BUYING',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.amber.shade900),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                store.storeAddress.isNotEmpty ? store.storeAddress : 'No address specified',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.pop(modalCtx);
                                setState(() {
                                  _selectedStore = store;
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLandscapeTablet = ScreenSize.isTabletLandscape(context);

    return PopScope(
      canPop: !_hasUnsavedChanges && !_isSaving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isSaving) return;
        if (_hasUnsavedChanges) {
          final shouldDiscard = await ShowMessage.confirm(
            context,
            title: 'Discard Van Sale?',
            message: 'You have unsaved items or store selection. Are you sure you want to go back and discard this sale?',
            confirmText: 'Discard',
            cancelText: 'Keep Editing',
            isDestructive: true,
            icon: Icons.warning_amber_rounded,
          );
          if (shouldDiscard && context.mounted) {
            setState(() {
              _selectedStore = null;
              _sellQuantities.clear();
              _remarksController.clear();
              _proofImage = null;
            });
            if (Navigator.of(context).canPop()) {
              Navigator.pop(context);
            }
          }
        }
      },
      child: Scaffold(
        appBar: CustomAppbar(
          title: 'Van Sell',
          subtitle: _activeVanLoad != null
              ? '${_activeVanLoad!.totalAvailableUnits} units available on van'
              : 'Sell From Van Stock',
          showBackButton: true,
        ),
        body: _activeVanLoad == null
            ? _buildNoActiveLoadState(theme)
            : (isLandscapeTablet
                ? _buildTabletLandscapeView(theme)
                : _buildVanSellForm(theme)),
        bottomNavigationBar: _activeVanLoad != null && !isLandscapeTablet
            ? _buildBottomBar(theme)
            : null,
      ),
    );
  }

  Widget _buildTabletLandscapeView(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: Product Catalog on Van (flex: 6)
        Expanded(
          flex: 6,
          child: _buildTabletCatalogPane(theme),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        // Right: Cart Summary & Checkout (flex: 4)
        Expanded(
          flex: 4,
          child: _buildTabletCartPane(theme),
        ),
      ],
    );
  }

  Widget _buildTabletCatalogPane(ThemeData theme) {
    final vanItems = _activeVanLoad!.items.where((i) {
      final matchesSearch = _productSearchQuery.isEmpty ||
          i.productName.toLowerCase().contains(_productSearchQuery.toLowerCase());
      return matchesSearch && i.availableQuantity > 0;
    }).toList();

    return Column(
      children: [
        // Search & Available Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _productSearchController,
                    onChanged: (val) => setState(() => _productSearchQuery = val.trim()),
                    style: const TextStyle(fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'Search products on van...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _productSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _productSearchController.clear();
                                setState(() => _productSearchQuery = '');
                              },
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 16, color: Colors.teal.shade800),
                    const SizedBox(width: 6),
                    Text(
                      '${vanItems.length} SKUs available',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Product Catalog List
        Expanded(
          child: vanItems.isEmpty
              ? Center(
                  child: Text(
                    _activeVanLoad!.items.isEmpty
                        ? 'No products loaded on van.'
                        : 'No available products match search.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: vanItems.length,
                  itemBuilder: (context, i) {
                    final item = vanItems[i];
                    final currentQty = _sellQuantities[item.productId] ?? 0;
                    final invItem = InventoryItem(
                      id: item.productId,
                      productName: item.productName,
                      imageUrl: item.imageUrl,
                      barcode: item.barcode,
                      buyingPrice: item.buyingPrice,
                      sellingPrice: item.sellingPrice,
                      isActive: true,
                      stockQuantity: item.availableQuantity,
                      lowStockThreshold: 5,
                      source: InventoryProductSource.fromKey(item.productSource),
                      category: item.category,
                      tag: item.tag,
                    );

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ProductOrderCard(
                        item: invItem,
                        selectedQty: currentQty,
                        maxOrderable: item.availableQuantity,
                        isPlaced: false,
                        currencyFormat: _currencyFormat,
                        onTap: () => _showQuantityDialog(item, currentQty, item.availableQuantity),
                        onIncrement: () {
                          HapticFeedback.lightImpact();
                          _updateQuantity(item.productId, currentQty + 1, item.availableQuantity);
                        },
                        onDecrement: () {
                          HapticFeedback.lightImpact();
                          _updateQuantity(item.productId, currentQty - 1, item.availableQuantity);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTabletCartPane(ThemeData theme) {
    final orderItems = _buildOrderItems();

    return Container(
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cart Pane Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            color: Colors.white,
            child: Row(
              children: [
                Icon(Icons.shopping_bag_outlined, color: Colors.teal.shade700, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cart (${orderItems.length} SKU${orderItems.length == 1 ? '' : 's'} • $_totalSellUnits units)',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (orderItems.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: const Text('Clear', style: TextStyle(fontSize: 12.5)),
                    onPressed: () async {
                      final confirmed = await ShowMessage.confirm(
                        context,
                        title: 'Clear Cart',
                        message: 'Are you sure you want to remove all selected items from the cart?',
                        confirmText: 'Clear All',
                        cancelText: 'Cancel',
                        isDestructive: true,
                        icon: Icons.delete_outline,
                      );
                      if (confirmed && mounted) {
                        setState(() {
                          _sellQuantities.clear();
                        });
                      }
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Store Selection & Proof Section
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Customer Store:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    if (_selectedStore != null && _isNonBuying(_selectedStore!))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(4)),
                        child: Text('NON-BUYING STORE', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _showStoreSelectionModal,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _selectedStore == null ? Colors.teal : Colors.grey.shade300,
                        width: _selectedStore == null ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.storefront_outlined, color: _selectedStore != null ? Colors.teal : Colors.grey, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedStore != null ? _selectedStore!.storeName : 'Select Registered Hapi Store...',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedStore != null ? Colors.black87 : Colors.grey.shade600,
                                ),
                              ),
                              if (_selectedStore != null && _selectedStore!.storeAddress.isNotEmpty)
                                Text(
                                  _selectedStore!.storeAddress,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
                if (_selectedStore != null) ...[
                  const SizedBox(height: 8),
                  _buildMainScreenProofBanner(),
                ],
              ],
            ),
          ),
          const Divider(height: 1),

          // Cart Items List
          Expanded(
            child: orderItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        Text(
                          'No items in cart',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Select products on the left to add to sale.',
                          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: orderItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = orderItems[index];
                      final vanItem = _activeVanLoad!.items.where((i) => i.productId == item.productId).firstOrNull;
                      final maxAllowed = vanItem?.availableQuantity ?? item.orderedQuantity;
                      final itemTotal = item.sellingPrice * item.orderedQuantity;

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (item.imageUrl.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  item.imageUrl,
                                  width: 38,
                                  height: 38,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 38,
                                    height: 38,
                                    color: Colors.grey.shade100,
                                    child: Icon(Icons.icecream, color: Colors.grey.shade400, size: 20),
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(Icons.icecream, color: Colors.grey.shade400, size: 20),
                              ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_currencyFormat.format(item.sellingPrice)} each',
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Stepper
                            Container(
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove, size: 14),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 30),
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      _updateQuantity(item.productId, item.orderedQuantity - 1, maxAllowed);
                                    },
                                  ),
                                  InkWell(
                                    onTap: vanItem != null
                                        ? () => _showQuantityDialog(vanItem, item.orderedQuantity, maxAllowed)
                                        : null,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Text(
                                        '${item.orderedQuantity}',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add, size: 14),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 30),
                                    onPressed: item.orderedQuantity < maxAllowed
                                        ? () {
                                            HapticFeedback.lightImpact();
                                            _updateQuantity(item.productId, item.orderedQuantity + 1, maxAllowed);
                                          }
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 65,
                              child: Text(
                                _currencyFormat.format(itemTotal),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.teal),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Sticky Cart Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Units:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    Text('$_totalSellUnits', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Amount:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(
                      Helperfunctions.formatDoubleAmountForDisplay(_totalSellAmount),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.teal),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: AsyncFilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: const Text(
                      'Complete & Print Receipt',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    loadingLabel: 'Processing...',
                    onPressed: _onCompleteAndPrint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoActiveLoadState(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_transfer_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('No Active Van Load Found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Stocks must be loaded onto the van before you can start selling.\nPlease ask the Dealer to create and confirm a Van Load.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Check Again'),
              onPressed: () => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVanSellForm(ThemeData theme) {
    final vanItems = _activeVanLoad!.items.where((i) {
      final matchesSearch = _productSearchQuery.isEmpty ||
          i.productName.toLowerCase().contains(_productSearchQuery.toLowerCase());
      return matchesSearch && i.availableQuantity > 0;
    }).toList();

    return Column(
      children: [
        // Store Selection Section
        Container(
          padding: const EdgeInsets.all(14),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Customer Store:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
                  if (_selectedStore != null && _isNonBuying(_selectedStore!))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Text('NON-BUYING STORE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _showStoreSelectionModal,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _selectedStore == null ? Colors.teal : Colors.grey.shade300, width: _selectedStore == null ? 1.5 : 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.storefront_outlined, color: _selectedStore != null ? Colors.teal : Colors.grey),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedStore != null ? _selectedStore!.storeName : 'Select Registered Hapi Store...',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _selectedStore != null ? Colors.black87 : Colors.grey.shade600,
                              ),
                            ),
                            if (_selectedStore != null && _selectedStore!.storeAddress.isNotEmpty)
                              Text(
                                _selectedStore!.storeAddress,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              if (_selectedStore != null) ...[
                const SizedBox(height: 8),
                _buildMainScreenProofBanner(),
              ],
              const SizedBox(height: 10),
              // Search in van inventory
              SizedBox(
                height: 40,
                child: TextField(
                  controller: _productSearchController,
                  onChanged: (val) => setState(() => _productSearchQuery = val.trim()),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search products on van...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Products on Van
        Expanded(
          child: vanItems.isEmpty
              ? Center(
                  child: Text(
                    _activeVanLoad!.items.isEmpty
                        ? 'No products loaded on van.'
                        : 'No available products match search.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: vanItems.length,
                  itemBuilder: (context, i) {
                    final item = vanItems[i];
                    final currentQty = _sellQuantities[item.productId] ?? 0;
                    final invItem = InventoryItem(
                      id: item.productId,
                      productName: item.productName,
                      imageUrl: item.imageUrl,
                      barcode: item.barcode,
                      buyingPrice: item.buyingPrice,
                      sellingPrice: item.sellingPrice,
                      isActive: true,
                      stockQuantity: item.availableQuantity,
                      lowStockThreshold: 5,
                      source: InventoryProductSource.fromKey(item.productSource),
                      category: item.category,
                      tag: item.tag,
                    );

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ProductOrderCard(
                        item: invItem,
                        selectedQty: currentQty,
                        maxOrderable: item.availableQuantity,
                        isPlaced: false,
                        currencyFormat: _currencyFormat,
                        onTap: () => _showQuantityDialog(item, currentQty, item.availableQuantity),
                        onIncrement: () {
                          HapticFeedback.lightImpact();
                          _updateQuantity(item.productId, currentQty + 1, item.availableQuantity);
                        },
                        onDecrement: () {
                          HapticFeedback.lightImpact();
                          _updateQuantity(item.productId, currentQty - 1, item.availableQuantity);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_totalSellUnits items', style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(_totalSellAmount),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.teal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AsyncFilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: const Text(
                'Complete & Print',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              loadingLabel: 'Processing...',
              onPressed: _onCompleteAndPrint,
            ),
          ],
        ),
      ),
    );
  }
}
