import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/badorder_controller.dart';
import 'package:selecta_ops/controllers/selecta_product_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/badorder.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/hapistore_dropdown.dart';

/// Full-page form for recording (Salesman & Dealer) or editing (Dealer only)
/// Bad Order records. Features a collapsible Incident & Store Information card
/// to maximize vertical space for product selection, with consistent tap-to-add
/// and modal quantity editing matching Book Order, Purchase Order, and Van Sell.
class BadOrderFormPage extends StatefulWidget {
  final BadOrder? existingRecord;
  final String? recID;
  final String? initialStoreName;
  final DateTime? initialDate;

  const BadOrderFormPage({
    super.key,
    this.existingRecord,
    this.recID,
    this.initialStoreName,
    this.initialDate,
  });

  @override
  State<BadOrderFormPage> createState() => _BadOrderFormPageState();
}

class _BadOrderFormPageState extends State<BadOrderFormPage> {
  final SelectaProductController _productController = SelectaProductController();
  final BadOrderController _boController = BadOrderController();
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _storeController;
  late final TextEditingController _notesController;
  final TextEditingController _searchController = TextEditingController();

  late DateTime _selectedDate;
  final Map<String, int> _quantities = {};
  File? _imageFile;
  String _existingImageUrl = '';
  String _searchQuery = '';
  String _categoryFilter = 'All'; // 'All', 'By Piece', 'By Case'
  bool _isSubmitting = false;
  bool _isCardExpanded = true;
  bool _isSalesman = false;

  bool get _isEditMode => widget.existingRecord != null && widget.recID != null;

  @override
  void initState() {
    super.initState();
    KVariables.getIsSalesman().then((val) {
      if (mounted) setState(() => _isSalesman = val);
    });
    final existing = widget.existingRecord;
    _storeController = TextEditingController(
      text: existing?.hapistore ?? widget.initialStoreName ?? '',
    );
    _notesController = TextEditingController(
      text: existing?.notes ?? '',
    );
    _selectedDate = existing != null
        ? existing.badorderDate.toDate()
        : (widget.initialDate ?? DateTime.now());
    _existingImageUrl = existing?.imagePath ?? '';

    // If editing and store/photo is already provided, keep card collapsed initially
    // to give immediate full view of products
    if (existing != null) {
      _isCardExpanded = false;
      for (final item in existing.items) {
        if (item.quantity > 0) {
          _quantities[item.productId] = item.quantity;
        }
      }
    }
  }

  @override
  void dispose() {
    _storeController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked != null) {
        setState(() => _imageFile = File(picked.path));
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to pick image: $e');
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  int get _totalUnits {
    return _quantities.values.fold<int>(0, (acc, q) => acc + q);
  }

  int get _totalSkus {
    return _quantities.values.where((q) => q > 0).length;
  }

  double _computeTotalAmount(List<SelectaProduct> products) {
    double total = 0.0;
    for (final p in products) {
      final q = _quantities[p.id] ?? 0;
      if (q > 0) {
        total += roundToTwoDecimals(q * p.storeRefundPerPiece);
      }
    }
    return total;
  }

  double _computeSupplierTotalAmount(List<SelectaProduct> products) {
    double total = 0.0;
    for (final p in products) {
      final q = _quantities[p.id] ?? 0;
      if (q > 0) {
        total += roundToTwoDecimals(q * p.supplierRefundPerPiece);
      }
    }
    return total;
  }

  void _updateQuantity(String productId, int newQty) {
    setState(() {
      if (newQty <= 0) {
        _quantities.remove(productId);
      } else {
        _quantities[productId] = newQty;
      }
    });
  }

  /// Consistent modal quantity dialog matching Book Order, Purchase Order, and Van Sell.
  Future<void> _showQuantityDialog(SelectaProduct product) async {
    if (!product.isBoPricingReady) {
      ShowMessage.error(
        context,
        'Cannot set quantity: "${product.productName}" is By Case and has no pieces per case configured by admin.',
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final currentQty = _quantities[product.id] ?? 0;
    final initialText = currentQty > 0 ? '$currentQty' : '';
    final controller = TextEditingController(text: initialText)
      ..selection = TextSelection(baseOffset: 0, extentOffset: initialText.length);

    final entered = await showDialog<int>(
      context: context,
      builder: (dCtx) {
        final colorScheme = Theme.of(dCtx).colorScheme;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            void setVal(int v) {
              final clamped = v < 0 ? 0 : v;
              final text = clamped > 0 ? '$clamped' : '';
              controller.value = TextEditingValue(
                text: text,
                selection: TextSelection(baseOffset: 0, extentOffset: text.length),
              );
              setDialogState(() {});
            }

            final typedVal = int.tryParse(controller.text.trim()) ?? 0;
            final liveSubtotal = roundToTwoDecimals(typedVal * product.storeRefundPerPiece);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: product.imageUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              product.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(Icons.icecream, color: Colors.purple, size: 20),
                            ),
                          )
                        : const Icon(Icons.icecream, color: Colors.purple, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.productName,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          product.isCaseProduct
                              ? '${product.category} • ${Helperfunctions.formatDoubleAmountForDisplay(product.storeRefundPerPiece)} / pc (${Helperfunctions.formatDoubleAmountForDisplay(product.sellingPrice)} / ${product.boPiecesPerCase})'
                              : '${product.category} • ${Helperfunctions.formatDoubleAmountForDisplay(product.storeRefundPerPiece)} / pc',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pullout Quantity (pcs)',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: '0',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text('+1'),
                        onPressed: () => setVal((int.tryParse(controller.text) ?? 0) + 1),
                      ),
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text('+5'),
                        onPressed: () => setVal((int.tryParse(controller.text) ?? 0) + 5),
                      ),
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text('+10'),
                        onPressed: () => setVal((int.tryParse(controller.text) ?? 0) + 10),
                      ),
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text('+25'),
                        onPressed: () => setVal((int.tryParse(controller.text) ?? 0) + 25),
                      ),
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text('Clear', style: TextStyle(color: Colors.red)),
                        onPressed: () => setVal(0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(
                          Helperfunctions.formatDoubleAmountForDisplay(liveSubtotal),
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: colorScheme.primary),
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

    if (entered != null && mounted) {
      _updateQuantity(product.id, entered);
    }
  }

  Future<void> _submit(List<SelectaProduct> allProducts) async {
    if (_isSubmitting) return;
    final storeName = _storeController.text.trim();
    if (storeName.isEmpty) {
      ShowMessage.error(context, 'Please select or enter the store name.');
      setState(() => _isCardExpanded = true);
      return;
    }

    final selectedItems = <BadOrderItem>[];
    for (final p in allProducts) {
      final q = _quantities[p.id] ?? 0;
      if (q > 0) {
        if (!p.isBoPricingReady) {
          ShowMessage.error(
            context,
            'Cannot submit: "${p.productName}" is By Case and has no pieces per case configured by admin.',
          );
          return;
        }
        selectedItems.add(BadOrderItem.fromProduct(
          product: p,
          quantity: q,
          imageUrl: p.imageUrl,
        ));
      }
    }

    if (selectedItems.isEmpty) {
      ShowMessage.error(context, 'Please specify quantities for at least one bad order product.');
      return;
    }

    final hasPhoto = _imageFile != null || _existingImageUrl.isNotEmpty;
    if (!hasPhoto) {
      ShowMessage.error(context, 'An incident photo of the bad order is required.');
      setState(() => _isCardExpanded = true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      String finalImageUrl = _existingImageUrl;
      if (_imageFile != null) {
        finalImageUrl = await Helperfunctions.saveImage(context, _imageFile!);
      }

      if (_isEditMode) {
        final existing = widget.existingRecord!;
        final isAdmin = await _boController.checkIsAdmin();
        if (!isAdmin && existing.status != BadOrderStatus.storePullout) {
          if (mounted) {
            ShowMessage.error(
              context,
              'Cannot edit bad order once status is "${existing.status}" in order to maintain data accuracy.',
            );
          }
          return;
        }
        final updated = existing.copyWith(
          hapistore: storeName,
          badorderDate: Timestamp.fromDate(_selectedDate),
          imagePath: finalImageUrl,
          items: selectedItems,
          notes: _notesController.text.trim(),
        );

        await _boController.updateBadOrder(
          recID: widget.recID!,
          updatedRecord: updated,
          existingRecord: existing,
          page: AppPages.badOrder,
        );

        if (mounted) {
          ShowMessage.success(context, 'Bad order record successfully updated!');
          Navigator.pop(context, true);
        }
      } else {
        await _boController.createBadOrder(
          hapistore: storeName,
          selectedDate: _selectedDate,
          imagePath: finalImageUrl,
          items: selectedItems,
          notes: _notesController.text.trim(),
          page: AppPages.badOrder,
        );

        if (mounted) {
          ShowMessage.success(context, 'Bad order record successfully submitted and recorded!');
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to save bad order record: $e');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Collapsible card holding Store name, Incident date, Incident photo, and Remarks.
  Widget _buildCollapsibleIncidentCard(ColorScheme colorScheme) {
    final storeName = _storeController.text.trim();
    final hasPhoto = _imageFile != null || _existingImageUrl.isNotEmpty;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header / Toggle Tile
          InkWell(
            onTap: () => setState(() => _isCardExpanded = !_isCardExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.storefront_outlined, size: 18, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Incident & Store Details',
                              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            if (!hasPhoto)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Photo Req.',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                                ),
                              )
                            else
                              Icon(Icons.check_circle, size: 15, color: Colors.green.shade700),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          storeName.isNotEmpty
                              ? '$storeName • ${DateFormat('MMM dd, yyyy').format(_selectedDate)}'
                              : 'Tap to configure store, date & photo',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isCardExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // Collapsible Details
          if (_isCardExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Store Selector
                  HapistorePickerField(
                    controller: _storeController,
                    label: 'Store Name (Required)',
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 12),

                  // 2. Incident Date Picker
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month_outlined, size: 20, color: colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Incident Date', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat('MMMM dd, yyyy').format(_selectedDate),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'Change',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 3. Incident Photo Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: !hasPhoto
                          ? Colors.red.shade50.withValues(alpha: 0.5)
                          : Colors.green.shade50.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: !hasPhoto ? Colors.red.shade300 : Colors.green.shade400,
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.photo_camera_outlined,
                              size: 18,
                              color: !hasPhoto ? Colors.red.shade800 : Colors.green.shade800,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Incident Photo (Required)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: !hasPhoto ? Colors.red.shade800 : Colors.green.shade800,
                              ),
                            ),
                            const Spacer(),
                            if (hasPhoto)
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _imageFile = null;
                                    _existingImageUrl = '';
                                  });
                                },
                                icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                label: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 12)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_imageFile != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              _imageFile!,
                              height: 130,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          )
                        else if (_existingImageUrl.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _existingImageUrl,
                              height: 130,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                height: 100,
                                alignment: Alignment.center,
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.broken_image, size: 30),
                              ),
                            ),
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _pickImage(ImageSource.camera),
                                  icon: const Icon(Icons.camera_alt, size: 18),
                                  label: const Text('Camera'),
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _pickImage(ImageSource.gallery),
                                  icon: const Icon(Icons.photo_library, size: 18),
                                  label: const Text('Gallery'),
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 4. Remarks / Notes TextField
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Remarks / Notes (Optional)',
                      hintText: 'Reason: expired, melted, damaged packaging...',
                      prefixIcon: const Icon(Icons.edit_note, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Product Item Card with Add button, quantity stepper, and tap-to-open quantity modal.
  Widget _buildProductCard(SelectaProduct product, ColorScheme colorScheme) {
    final qty = _quantities[product.id] ?? 0;
    final isCase = product.isCaseProduct;
    final hasValidPrice = product.isBoPricingReady;
    final unitPrice = product.storeRefundPerPiece;
    final subtotal = roundToTwoDecimals(qty * unitPrice);
    final isSelected = qty > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isSelected ? colorScheme.primary.withValues(alpha: 0.04) : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: !hasValidPrice
            ? null
            : () {
                HapticFeedback.lightImpact();
                if (qty == 0) {
                  // Tapping the card when qty is 0 sets to 1
                  _updateQuantity(product.id, 1);
                } else {
                  // Tapping the card when qty > 0 opens the modal quantity dialog
                  _showQuantityDialog(product);
                }
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CachedProductImage(
                imageUrl: product.imageUrl,
                isActive: hasValidPrice,
                size: 44,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top: Product Title & Subtotal
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            product.productName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          Text(
                            Helperfunctions.formatDoubleAmountForDisplay(subtotal),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),

                    // In the row of the category by case and by piece:
                    // Left: Category badge & unit price
                    // Right: Add button or Stepper
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left: Category chip & unit price
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 2,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: isCase ? Colors.purple.shade50 : Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  product.category,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: isCase ? Colors.purple.shade700 : Colors.blue.shade700,
                                  ),
                                ),
                              ),
                              if (!hasValidPrice)
                                const Text(
                                  '⚠️ No pieces/case set',
                                  style: TextStyle(fontSize: 10.5, color: Colors.red, fontWeight: FontWeight.bold),
                                )
                              else
                                Text(
                                  isCase
                                      ? '@ ${Helperfunctions.formatDoubleAmountForDisplay(unitPrice)} / pc (${Helperfunctions.formatDoubleAmountForDisplay(product.sellingPrice)} / ${product.boPiecesPerCase})'
                                      : '@ ${Helperfunctions.formatDoubleAmountForDisplay(unitPrice)} / pc',
                                  style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Right: Add button or Stepper
                        if (!hasValidPrice)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('Blocked', style: TextStyle(color: Colors.red, fontSize: 10.5, fontWeight: FontWeight.bold)),
                          )
                        else if (!isSelected)
                          FilledButton.icon(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              _updateQuantity(product.id, 1);
                            },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              minimumSize: const Size(74, 35),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.standard,
                            ),
                            icon: const Icon(Icons.add_rounded, size: 17),
                            label: const Text('Add', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          )
                        else
                          Container(
                            height: 35,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      _updateQuantity(product.id, qty - 1);
                                    },
                                    child: SizedBox(
                                      width: 32,
                                      height: 35,
                                      child: Icon(
                                        qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                                        size: 16,
                                        color: qty == 1 ? colorScheme.error : colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _showQuantityDialog(product),
                                  child: Container(
                                    constraints: const BoxConstraints(minWidth: 30),
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '$qty',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(18)),
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      _updateQuantity(product.id, qty + 1);
                                    },
                                    child: SizedBox(
                                      width: 32,
                                      height: 35,
                                      child: Icon(Icons.add_rounded, size: 16, color: colorScheme.primary),
                                    ),
                                  ),
                                ),
                              ],
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: CustomAppbar(
          title: _isEditMode ? 'Edit Bad Order' : 'Record Bad Order',
          subtitle: _isEditMode ? widget.existingRecord!.hapistore : 'Selecta Pullout',
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _productController.getProductsStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? [];
            final allProducts = docs
                .map((d) => SelectaProduct.fromSnapshot(d))
                .where((p) => p.isActive)
                .toList();

            final filteredProducts = allProducts.where((p) {
              final matchesCat = _categoryFilter == 'All' || p.category == _categoryFilter;
              final matchesQuery = _searchQuery.isEmpty ||
                  p.productName.toLowerCase().contains(_searchQuery) ||
                  p.itemCode.toLowerCase().contains(_searchQuery);
              return matchesCat && matchesQuery;
            }).toList();

            // Sort products honoring dealer product sorting hierarchy
            filteredProducts.sort((a, b) {
              if (_categoryFilter == 'All') {
                final catComp = Helperfunctions.compareCategoryHierarchy(a.category, b.category);
                if (catComp != 0) return catComp;
              }
              return Helperfunctions.compareProducts(
                nameA: a.productName,
                priceA: a.sellingPrice,
                nameB: b.productName,
                priceB: b.sellingPrice,
                productIdA: a.id,
                productIdB: b.id,
                categoryA: a.category,
                categoryB: b.category,
              );
            });

            final totalUnits = _totalUnits;
            final totalSkus = _totalSkus;
            final totalAmount = _computeTotalAmount(allProducts);
            final totalSupplierAmount = _computeSupplierTotalAmount(allProducts);

            if (ScreenSize.isTabletLandscape(context)) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        border: Border(
                          right: BorderSide(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      child: _buildTabletIncidentSummaryPanel(
                        colorScheme,
                        allProducts,
                        totalSkus,
                        totalUnits,
                        totalAmount,
                        totalSupplierAmount,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: _buildTabletCatalogPanel(
                      colorScheme,
                      filteredProducts,
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      // 1. Collapsible Incident & Store Details Card
                      SliverToBoxAdapter(
                        child: _buildCollapsibleIncidentCard(colorScheme),
                      ),

                      // 2. Search Products Bar (dedicated row only)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                          child: SizedBox(
                            height: 40,
                            child: TextField(
                              controller: _searchController,
                              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                              decoration: InputDecoration(
                                hintText: 'Search products...',
                                prefixIcon: const Icon(Icons.search, size: 18),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 16),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                      )
                                    : null,
                                filled: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 3. Category Filter Chips (Row below search)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                          child: Row(
                            children: [
                              ChoiceChip(
                                label: const Text('All', style: TextStyle(fontSize: 12)),
                                selected: _categoryFilter == 'All',
                                onSelected: (_) => setState(() => _categoryFilter = 'All'),
                                visualDensity: VisualDensity.compact,
                                showCheckmark: false,
                              ),
                              const SizedBox(width: 6),
                              ChoiceChip(
                                label: const Text('By Piece', style: TextStyle(fontSize: 12)),
                                selected: _categoryFilter == 'By Piece',
                                onSelected: (_) => setState(() => _categoryFilter = 'By Piece'),
                                visualDensity: VisualDensity.compact,
                                showCheckmark: false,
                              ),
                              const SizedBox(width: 6),
                              ChoiceChip(
                                label: const Text('By Case', style: TextStyle(fontSize: 12)),
                                selected: _categoryFilter == 'By Case',
                                onSelected: (_) => setState(() => _categoryFilter = 'By Case'),
                                visualDensity: VisualDensity.compact,
                                showCheckmark: false,
                              ),
                              const Spacer(),
                              Text(
                                '${filteredProducts.length} items',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 4. Products List
                      if (filteredProducts.isEmpty)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(32.0),
                            child: Center(child: Text('No active Selecta products match filter.')),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final product = filteredProducts[index];
                                return _buildProductCard(product, colorScheme);
                              },
                              childCount: filteredProducts.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Sticky Bottom Bar
                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$totalSkus SKU${totalSkus == 1 ? '' : 's'} • $totalUnits pcs',
                                style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                              ),
                              Row(
                                children: [
                                  Text(
                                    Helperfunctions.formatDoubleAmountForDisplay(totalAmount),
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    '(Store refund)',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFE11D48)),
                                  ),
                                ],
                              ),
                              if (!_isSalesman && totalSupplierAmount > 0)
                                Text(
                                  'Expected supplier: ${Helperfunctions.formatDoubleAmountForDisplay(totalSupplierAmount)}',
                                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                        AsyncFilledButton.icon(
                          onPressed: () => _submit(allProducts),
                          loadingLabel: 'Saving...',
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange.shade800,
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(
                            _isEditMode ? 'Update Bad Order' : 'Save Bad Order',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabletIncidentSummaryPanel(
    ColorScheme colorScheme,
    List<SelectaProduct> allProducts,
    int totalSkus,
    int totalUnits,
    double totalAmount,
    double totalSupplierAmount,
  ) {
    final selectedProducts = allProducts.where((p) => (_quantities[p.id] ?? 0) > 0).toList();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCollapsibleIncidentCard(colorScheme),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
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
                              Text(
                                'Claim Items ($totalSkus SKU${totalSkus == 1 ? '' : 's'})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const Spacer(),
                              if (selectedProducts.isNotEmpty)
                                TextButton(
                                  onPressed: () {
                                    setState(() => _quantities.clear());
                                  },
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('Clear All', style: TextStyle(color: Colors.red, fontSize: 12)),
                                ),
                            ],
                          ),
                          const Divider(height: 16),
                          if (selectedProducts.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: Text(
                                  'No items added to claim yet.\nSelect products from the catalog.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          else
                            ...selectedProducts.map((p) {
                              final qty = _quantities[p.id] ?? 0;
                              final subtotal = roundToTwoDecimals(qty * p.storeRefundPerPiece);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.productName,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '${Helperfunctions.formatDoubleAmountForDisplay(p.storeRefundPerPiece)} × $qty = ${Helperfunctions.formatDoubleAmountForDisplay(subtotal)}',
                                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: colorScheme.outlineVariant),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.remove, size: 14),
                                            padding: const EdgeInsets.all(4),
                                            constraints: const BoxConstraints(),
                                            onPressed: () {
                                              HapticFeedback.lightImpact();
                                              _updateQuantity(p.id, qty - 1);
                                            },
                                          ),
                                          InkWell(
                                            onTap: () => _showQuantityDialog(p),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              child: Text(
                                                '$qty',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.add, size: 14),
                                            padding: const EdgeInsets.all(4),
                                            constraints: const BoxConstraints(),
                                            onPressed: () {
                                              HapticFeedback.lightImpact();
                                              _updateQuantity(p.id, qty + 1);
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Bottom Action Panel
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$totalSkus SKU${totalSkus == 1 ? '' : 's'} • $totalUnits pcs',
                        style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                      ),
                      const Text(
                        'Refund to store',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFE11D48)),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Helperfunctions.formatDoubleAmountForDisplay(totalAmount),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      if (!_isSalesman && totalSupplierAmount > 0)
                        Text(
                          'Expected supplier: ${Helperfunctions.formatDoubleAmountForDisplay(totalSupplierAmount)}',
                          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: AsyncFilledButton.icon(
                  onPressed: () => _submit(allProducts),
                  loadingLabel: 'Saving...',
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(
                    _isEditMode ? 'Update Bad Order' : 'Save Bad Order',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabletCatalogPanel(
    ColorScheme colorScheme,
    List<SelectaProduct> filteredProducts,
  ) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search products...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
        // Filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('All', style: TextStyle(fontSize: 12)),
                selected: _categoryFilter == 'All',
                onSelected: (_) => setState(() => _categoryFilter = 'All'),
                visualDensity: VisualDensity.compact,
                showCheckmark: false,
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('By Piece', style: TextStyle(fontSize: 12)),
                selected: _categoryFilter == 'By Piece',
                onSelected: (_) => setState(() => _categoryFilter = 'By Piece'),
                visualDensity: VisualDensity.compact,
                showCheckmark: false,
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('By Case', style: TextStyle(fontSize: 12)),
                selected: _categoryFilter == 'By Case',
                onSelected: (_) => setState(() => _categoryFilter = 'By Case'),
                visualDensity: VisualDensity.compact,
                showCheckmark: false,
              ),
              const Spacer(),
              Text(
                '${filteredProducts.length} items',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Product list
        Expanded(
          child: filteredProducts.isEmpty
              ? const Center(child: Text('No active Selecta products match filter.'))
              : ListView.builder(
                  primary: false,
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = filteredProducts[index];
                    return _buildProductCard(product, colorScheme);
                  },
                ),
        ),
      ],
    );
  }
}
