import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/controllers/selecta_product_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/admin_selecta_product.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:selecta_ops/views/widgets/barcodescanner_widget.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

/// Form page for viewing Selecta product details or Admin Add/Edit of an [AdminSelectaProduct].
class SelectaProductFormPage extends StatefulWidget {
  final String? productId;
  final AdminSelectaProduct? existingProduct;
  final SelectaProduct? existingDealerProduct;
  final bool isReadOnly;
  final String userRole;

  const SelectaProductFormPage({
    super.key,
    this.productId,
    this.existingProduct,
    this.existingDealerProduct,
    this.isReadOnly = false,
    this.userRole = 'Dealer',
  });

  @override
  State<SelectaProductFormPage> createState() => _SelectaProductFormPageState();
}

class _SelectaProductFormPageState extends State<SelectaProductFormPage> {
  late final SelectaProductController _controller = SelectaProductController();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _buyingPriceController;
  late final TextEditingController _sellingPriceController;
  late final TextEditingController _boPiecesPerCaseController;
  String _category = 'By Piece';
  String _tag = ProductTag.none;

  File? _image;
  String _networkImagePath = '';
  final ImagePicker _picker = ImagePicker();

  bool _isSaving = false;
  late bool _isReadOnly;

  bool get _isEditing => widget.productId != null;

  bool get _isAdmin {
    final role = widget.userRole.trim().toLowerCase();
    return role == 'admin' || role == 'super admin' || role == 'superadmin';
  }

  bool get _isSalesman => widget.userRole.trim().toLowerCase() == 'salesman';

  final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _isReadOnly = widget.isReadOnly;
    final adminP = widget.existingProduct;
    final dealerP = widget.existingDealerProduct;

    final initialName = adminP?.productName ?? dealerP?.productName ?? '';
    _nameController = TextEditingController(text: initialName);

    final initialBarcode = adminP?.barcode ?? dealerP?.barcode ?? '';
    _barcodeController = TextEditingController(text: initialBarcode);

    final rawCat = (adminP?.category ?? dealerP?.category ?? '').trim();
    final isCase = rawCat.toLowerCase() == 'by case' || rawCat.toLowerCase() == 'case';
    _category = isCase ? 'By Case' : 'By Piece';

    _tag = adminP?.tag ?? dealerP?.tag ?? ProductTag.none;

    final bp = adminP?.buyingPrice ?? dealerP?.buyingPrice ?? 0.0;
    _buyingPriceController = TextEditingController(
      text: bp > 0 ? bp.toStringAsFixed(2) : '',
    );

    final sp = adminP?.sellingPrice ?? dealerP?.sellingPrice ?? 0.0;
    _sellingPriceController = TextEditingController(
      text: sp > 0 ? sp.toStringAsFixed(2) : '',
    );

    final initialPieces = adminP?.boPiecesPerCase ?? dealerP?.boPiecesPerCase;
    _boPiecesPerCaseController = TextEditingController(
      text: initialPieces != null && initialPieces > 0 ? initialPieces.toString() : '',
    );

    _networkImagePath = adminP?.imageUrl ?? dealerP?.imageUrl ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _buyingPriceController.dispose();
    _sellingPriceController.dispose();
    _boPiecesPerCaseController.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerWidget()),
    );
    if (scanned != null && scanned.trim().isNotEmpty && mounted) {
      setState(() {
        _barcodeController.text = scanned.trim();
      });
      HapticFeedback.lightImpact();
      ShowMessage.success(context, 'Barcode scanned: ${scanned.trim()}');
    }
  }


  double get _buyingPrice => double.tryParse(_buyingPriceController.text.trim()) ?? 0.0;
  double get _sellingPrice => double.tryParse(_sellingPriceController.text.trim()) ?? 0.0;
  double get _margin => _sellingPrice - _buyingPrice;
  double get _marginPercent => _buyingPrice > 0 ? (_margin / _buyingPrice) * 100 : 0;

  Future<void> _cleanupLocalFile(File? file) async {
    if (file == null) return;
    try {
      FileImage(file).evict();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 75,
      );
      if (pickedFile != null) {
        final oldLocalFile = _image;
        setState(() {
          _image = File(pickedFile.path);
          _networkImagePath = '';
        });
        if (oldLocalFile != null && oldLocalFile.path != pickedFile.path) {
          await _cleanupLocalFile(oldLocalFile);
        }
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to pick image: $e');
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
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                  child: Icon(Icons.camera_alt_outlined, color: colorScheme.primary),
                ),
                title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Capture photo with camera'),
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
                subtitle: const Text('Select a photo from device storage'),
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final int? piecesPerCase = _category == 'By Case'
        ? int.tryParse(_boPiecesPerCaseController.text.trim())
        : null;

    final tempProduct = AdminSelectaProduct(
      id: widget.productId ?? '',
      productName: _nameController.text.trim(),
      barcode: _barcodeController.text.trim(),
      imageUrl: '',
      buyingPrice: _buyingPrice,
      sellingPrice: _sellingPrice,
      category: _category,
      tag: _tag,
      boPiecesPerCase: piecesPerCase,
    );

    final errors = _controller.validateAdminProduct(tempProduct);
    if (errors.isNotEmpty) {
      ShowMessage.listError(context, errors);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final savedUrl = widget.existingProduct?.imageUrl ?? '';
      final pickedLocalFile = _image;
      final String finalImageUrl = await Helperfunctions.updateImage(
        context,
        pickedLocalFile,
        _networkImagePath,
        savedUrl,
      );
      if (pickedLocalFile != null && finalImageUrl.isEmpty) {
        setState(() => _isSaving = false);
        return;
      }
      if (pickedLocalFile != null) {
        await _cleanupLocalFile(pickedLocalFile);
      }

      final product = AdminSelectaProduct(
        id: widget.productId ?? '',
        productName: _nameController.text.trim(),
        barcode: _barcodeController.text.trim(),
        imageUrl: finalImageUrl,
        buyingPrice: _buyingPrice,
        sellingPrice: _sellingPrice,
        category: _category,
        tag: _tag,
        boPiecesPerCase: piecesPerCase,
      );

      if (_isEditing) {
        await _controller.updateAdminProduct(widget.productId!, product);
        if (mounted) {
          ShowMessage.success(context, 'Admin Selecta product updated successfully!');
          Navigator.pop(context);
        }
      } else {
        await _controller.addAdminProduct(product);
        if (mounted) {
          ShowMessage.success(context, 'Admin Selecta product added successfully!');
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to save product: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Delete Selecta Product',
      message: 'Are you sure you want to delete "${_nameController.text.trim()}" from the master Admin catalog? This action cannot be undone.',
      isDestructive: true,
      icon: Icons.delete_outline_rounded,
      confirmText: 'Delete',
    );
    if (!confirmed || !mounted) return;
    await ShowMessage.runWithLoading(
      context,
      message: 'Deleting product from catalog...',
      task: () async {
        final savedUrl = widget.existingProduct?.imageUrl ?? '';
        if (savedUrl.isNotEmpty) {
          await Helperfunctions.deleteImage(context, savedUrl);
        }
        if (_image != null) {
          await _cleanupLocalFile(_image);
        }
        await _controller.deleteAdminProduct(widget.productId!);
        if (mounted) {
          ShowMessage.success(context, 'Selecta product deleted from Admin catalog.');
          Navigator.pop(context);
        }
      },
    );
  }

  bool get _hasUnsavedChanges {
    if (_isReadOnly) return false;
    final adminP = widget.existingProduct;
    final dealerP = widget.existingDealerProduct;
    final initialName = adminP?.productName ?? dealerP?.productName ?? '';
    final initialBarcode = adminP?.barcode ?? dealerP?.barcode ?? '';
    final rawCat = (adminP?.category ?? dealerP?.category ?? '').trim();
    final isCase = rawCat.toLowerCase() == 'by case' || rawCat.toLowerCase() == 'case';
    final initialCategory = isCase ? 'By Case' : 'By Piece';
    final initialTag = adminP?.tag ?? dealerP?.tag ?? ProductTag.none;
    final bp = adminP?.buyingPrice ?? dealerP?.buyingPrice ?? 0.0;
    final initialBp = bp > 0 ? bp.toStringAsFixed(2) : '';
    final sp = adminP?.sellingPrice ?? dealerP?.sellingPrice ?? 0.0;
    final initialSp = sp > 0 ? sp.toStringAsFixed(2) : '';
    final initialPieces = adminP?.boPiecesPerCase ?? dealerP?.boPiecesPerCase;
    final initialPiecesText = initialPieces != null && initialPieces > 0 ? initialPieces.toString() : '';

    if (_isEditing && (adminP != null || dealerP != null)) {
      return _nameController.text.trim() != initialName ||
          _barcodeController.text.trim() != initialBarcode ||
          _category != initialCategory ||
          _tag != initialTag ||
          _buyingPriceController.text.trim() != initialBp ||
          _sellingPriceController.text.trim() != initialSp ||
          _boPiecesPerCaseController.text.trim() != initialPiecesText ||
          _image != null;
    }
    return _nameController.text.trim().isNotEmpty ||
        _barcodeController.text.trim().isNotEmpty ||
        _buyingPriceController.text.trim().isNotEmpty ||
        _sellingPriceController.text.trim().isNotEmpty ||
        _boPiecesPerCaseController.text.trim().isNotEmpty ||
        _image != null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPositiveMargin = _margin >= 0;
    final marginColor = isPositiveMargin ? const Color(0xFF15803D) : colorScheme.error;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isSaving) return;
        if (_hasUnsavedChanges) {
          final shouldDiscard = await ShowMessage.confirm(
            context,
            title: 'Discard Changes?',
            message: 'You have unsaved changes to this product. Are you sure you want to discard them?',
            confirmText: 'Discard',
            cancelText: 'Keep Editing',
            isDestructive: true,
            icon: Icons.warning_amber_rounded,
          );
          if (shouldDiscard && context.mounted) {
            Navigator.pop(context);
          }
        } else {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
      appBar: CustomAppbar(
        title: _isReadOnly
            ? 'Product Details'
            : (_isEditing ? 'Edit Selecta Product' : 'Add Selecta Product'),
        subtitle: _isReadOnly
            ? 'Selecta product record'
            : (_isEditing ? 'Master Admin Catalog' : 'New Master Catalog Entry'),
        actions: _isReadOnly
            ? (_isAdmin
                ? [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.white),
                      tooltip: 'Edit Product',
                      onPressed: () => setState(() => _isReadOnly = false),
                    ),
                  ]
                : null)
            : [
                if (_isEditing && widget.isReadOnly && _isAdmin)
                  IconButton(
                    icon: const Icon(Icons.visibility_outlined, color: Colors.white),
                    tooltip: 'View Details',
                    onPressed: () => setState(() => _isReadOnly = true),
                  ),
                if (_isEditing)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                    onPressed: _confirmDelete,
                    tooltip: 'Delete Product',
                  ),
              ],
      ),
      body: _isReadOnly
          ? _buildReadOnlyBody(colorScheme, marginColor, isPositiveMargin)
          : Form(
              key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Admin Notice Banner ──────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.admin_panel_settings_rounded, size: 20, color: Colors.amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Admin Master Model: Consists of product image, product name, buying price, and selling price synced across all dealers.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Product Image Picker Card ─────────────────────────────
              _buildImagePickerCard(colorScheme),

              const SizedBox(height: 16),

              // ── Product Name Card ─────────────────────────────────────
              _buildSectionCard(
                colorScheme: colorScheme,
                icon: Icons.inventory_2_outlined,
                iconColor: colorScheme.primary,
                title: 'Product Information',
                children: [
                  _buildField(
                    label: 'Product Name *',
                    controller: _nameController,
                    hint: 'e.g. SELECTA CORNETTO COOKIES & CHOCOLATE 110ML',
                    icon: Icons.label_outline_rounded,
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Product name is required' : null,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    label: 'Barcode (Optional)',
                    controller: _barcodeController,
                    hint: 'Scan or enter product barcode',
                    icon: Icons.qr_code_2_rounded,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      tooltip: 'Scan Barcode',
                      onPressed: _scanBarcode,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Category Card (Strictly "By Piece" or "By Case") ────────
              _buildSectionCard(
                colorScheme: colorScheme,
                icon: Icons.category_outlined,
                iconColor: Colors.deepOrange,
                title: 'Category *',
                children: [
                  Text(
                    'Categorize product strictly as "By Piece" or "By Case" for order delivery receipts:',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'By Piece',
                          label: Text('By Piece'),
                          icon: Icon(Icons.icecream_outlined, size: 18),
                        ),
                        ButtonSegment<String>(
                          value: 'By Case',
                          label: Text('By Case'),
                          icon: Icon(Icons.inventory_2_outlined, size: 18),
                        ),
                      ],
                      selected: {_category},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          _category = newSelection.first;
                          if (_category != 'By Case') {
                            _boPiecesPerCaseController.clear();
                          }
                        });
                      },
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                        selectedForegroundColor: colorScheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  if (_category == 'By Case') ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _boPiecesPerCaseController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (_category != 'By Case') return null;
                        final trimmed = (value ?? '').trim();
                        if (trimmed.isEmpty) {
                          return 'Pieces per case is required for By Case products.';
                        }
                        final count = int.tryParse(trimmed);
                        if (count == null || count < 2 || count > 999) {
                          return 'Enter a whole number between 2 and 999.';
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        labelText: 'Pieces per case (for bad order refunds) *',
                        hintText: 'e.g. 12',
                        helperText: 'Whole number from 2 to 999. Used for store and supplier refund rates.',
                        helperMaxLines: 2,
                        prefixIcon: const Icon(Icons.pin_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Builder(
                      builder: (context) {
                        final pcs = int.tryParse(_boPiecesPerCaseController.text.trim());
                        final isValidPcs = pcs != null && pcs >= 2 && pcs <= 999;
                        final storeRef = isValidPcs && pcs > 0 ? (_sellingPrice / pcs) : 0.0;
                        final suppRef = isValidPcs && pcs > 0 ? (_buyingPrice / pcs) : 0.0;

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isValidPcs
                                ? Colors.blue.withValues(alpha: 0.08)
                                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isValidPcs
                                  ? Colors.blue.withValues(alpha: 0.3)
                                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          child: isValidPcs
                              ? Row(
                                  children: [
                                    const Icon(Icons.calculate_outlined, size: 18, color: Colors.blue),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Store refund/pc: ${currencyFormat.format(storeRef)}  •  Supplier refund/pc: ${currencyFormat.format(suppRef)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.blue.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  'Enter pieces per case (2–999) to view live refund rates.',
                                  style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                                ),
                        );
                      },
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 16),

              // ── Product Tag Card (Best Seller / New Product / None) ───
              _buildSectionCard(
                colorScheme: colorScheme,
                icon: Icons.local_offer_outlined,
                iconColor: const Color(0xFFD97706),
                title: 'Product Tag',
                children: [
                  Text(
                    'Highlight this product in the catalog and placement checklists:',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: ProductTag.none,
                          label: Text('None'),
                          icon: Icon(Icons.label_off_outlined, size: 18),
                        ),
                        ButtonSegment<String>(
                          value: ProductTag.bestSeller,
                          label: Text('Best Seller'),
                          icon: Icon(Icons.star_rounded, size: 18, color: Color(0xFFD97706)),
                        ),
                        ButtonSegment<String>(
                          value: ProductTag.newProduct,
                          label: Text('New Product'),
                          icon: Icon(Icons.fiber_new_rounded, size: 18, color: Color(0xFF0284C7)),
                        ),
                      ],
                      selected: {_tag},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          _tag = newSelection.first;
                        });
                      },
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: _tag == ProductTag.bestSeller
                            ? const Color(0xFFFEF3C7)
                            : (_tag == ProductTag.newProduct
                                ? const Color(0xFFE0F2FE)
                                : colorScheme.primary.withValues(alpha: 0.15)),
                        selectedForegroundColor: _tag == ProductTag.bestSeller
                            ? const Color(0xFF92400E)
                            : (_tag == ProductTag.newProduct
                                ? const Color(0xFF0369A1)
                                : colorScheme.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Pricing Card ───────────────────────────────────────────
              _buildSectionCard(
                colorScheme: colorScheme,
                icon: Icons.attach_money_rounded,
                iconColor: const Color(0xFF15803D),
                title: 'Pricing',
                children: [
                  Row(
                    spacing: 12,
                    children: [
                      Expanded(
                        child: _buildPriceField(
                          label: 'Buying Price *',
                          controller: _buyingPriceController,
                          color: const Color(0xFF2563EB),
                          icon: Icons.shopping_cart_outlined,
                        ),
                      ),
                      Expanded(
                        child: _buildPriceField(
                          label: 'Selling Price *',
                          controller: _sellingPriceController,
                          color: const Color(0xFF15803D),
                          icon: Icons.sell_outlined,
                        ),
                      ),
                    ],
                  ),
                  AnimatedBuilder(
                    animation: Listenable.merge([_buyingPriceController, _sellingPriceController]),
                    builder: (context, child) {
                      final showMargin = _buyingPrice > 0 && _sellingPrice > 0;
                      if (!showMargin) return const SizedBox.shrink();
                      final isPositive = _margin >= 0;
                      final marginColor = isPositive ? const Color(0xFF15803D) : Colors.red;
                      return Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: marginColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: marginColor.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildMarginStat(label: 'Margin', value: currencyFormat.format(_margin), color: marginColor),
                              Container(width: 1, height: 28, color: marginColor.withValues(alpha: 0.3)),
                              _buildMarginStat(label: 'Margin %', value: '${_marginPercent.toStringAsFixed(1)}%', color: marginColor),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // ── Save Button ────────────────────────────────────────────
              AsyncFilledButton.icon(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                loadingLabel: 'Saving...',
                icon: Icon(_isEditing ? Icons.save_rounded : Icons.add_rounded, size: 20),
                label: Text(
                  _isEditing ? 'Save Changes' : 'Add Selecta Product',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildReadOnlyBody(
    ColorScheme colorScheme,
    Color marginColor,
    bool isPositiveMargin,
  ) {
    final bool hasImageData = _image != null || _networkImagePath.isNotEmpty;
    final dealerP = widget.existingDealerProduct;
    final adminP = widget.existingProduct;

    final stockQty = dealerP?.stockQuantity ?? 0;
    final reservedQty = dealerP?.reservedQuantity ?? 0;
    final availableQty = dealerP?.availableQuantity ?? stockQty;
    final lowStockThreshold = dealerP?.lowStockThreshold ?? 10;
    final isOutOfStock = dealerP?.isOutOfStock ?? (stockQty <= 0);
    final isLowStock = dealerP?.isLowStock ?? (stockQty > 0 && availableQty <= lowStockThreshold);

    final Color stockBadgeColor = isOutOfStock
        ? colorScheme.error
        : isLowStock
            ? const Color(0xFFD97706)
            : const Color(0xFF15803D);

    final String stockStatusLabel = isOutOfStock
        ? 'Out of Stock'
        : isLowStock
            ? 'Low Stock'
            : 'In Stock';

    final isBestSeller = ProductTag.isBestSeller(_tag);
    final isNewProd = ProductTag.isNewProduct(_tag);

    final String itemCode = dealerP?.itemCode ?? '';
    final bool isActive = dealerP?.isActive ?? true;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Product Image Card ──────────────────────────────────────
          _buildSectionCard(
            colorScheme: colorScheme,
            icon: Icons.image_outlined,
            iconColor: colorScheme.primary,
            title: 'Product Image',
            children: [
              if (hasImageData)
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          onTap: () => Helperfunctions.navigateTo(
                            context,
                            ImageViewerPage(image: _image, networkImagePath: _networkImagePath),
                          ),
                          child: Container(
                            height: 220,
                            width: double.infinity,
                            decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(10)),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _image != null
                                    ? Image.file(_image!, fit: BoxFit.contain)
                                    : Image.network(
                                        _networkImagePath,
                                        fit: BoxFit.contain,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return const Center(child: CircularProgressIndicator());
                                        },
                                        errorBuilder: (_, _, _) => Container(
                                          color: colorScheme.surfaceContainerHighest,
                                          alignment: Alignment.center,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.broken_image_outlined, size: 36, color: colorScheme.onSurfaceVariant),
                                              const SizedBox(height: 4),
                                              Text('Unable to load image', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                                            ],
                                          ),
                                        ),
                                      ),
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.fullscreen_rounded, size: 14, color: Colors.white),
                                        SizedBox(width: 4),
                                        Text('Tap to expand', style: TextStyle(color: Colors.white, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => Helperfunctions.navigateTo(
                          context,
                          ImageViewerPage(image: _image, networkImagePath: _networkImagePath),
                        ),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.fullscreen_rounded, size: 18),
                        label: const Text('View Full Image', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant, width: 1.2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: Icon(Icons.icecream_outlined, size: 32, color: colorScheme.primary),
                      ),
                      const SizedBox(height: 10),
                      const Text('No Image Available', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('No photo has been uploaded for this Selecta product.', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Product Information Card ────────────────────────────────
          _buildSectionCard(
            colorScheme: colorScheme,
            icon: Icons.inventory_2_outlined,
            iconColor: colorScheme.primary,
            title: 'Product Information',
            children: [
              _buildReadOnlyTile(
                label: 'Product Name',
                value: _nameController.text.trim().isNotEmpty
                    ? _nameController.text.trim()
                    : 'Unnamed Product',
                icon: Icons.label_outline_rounded,
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: _category == 'By Case'
                            ? Colors.deepOrange.withValues(alpha: 0.1)
                            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _category == 'By Case'
                              ? Colors.deepOrange.withValues(alpha: 0.35)
                              : colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Category', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Text(
                            _category,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _category == 'By Case' ? Colors.deepOrange.shade800 : colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isBestSeller
                            ? const Color(0xFFFEF3C7)
                            : isNewProd
                                ? const Color(0xFFDBEAFE)
                                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isBestSeller
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                              : isNewProd
                                  ? const Color(0xFF3B82F6).withValues(alpha: 0.5)
                                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Product Tag', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isBestSeller) ...[
                                const Icon(Icons.star_rounded, size: 14, color: Color(0xFFB45309)),
                                const SizedBox(width: 4),
                              ] else if (isNewProd) ...[
                                const Icon(Icons.fiber_new_rounded, size: 14, color: Color(0xFF1D4ED8)),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  _tag.isNotEmpty ? _tag : 'None',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isBestSeller
                                        ? const Color(0xFFB45309)
                                        : isNewProd
                                            ? const Color(0xFF1D4ED8)
                                            : colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (itemCode.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildReadOnlyTile(
                  label: 'Item Code',
                  value: itemCode,
                  icon: Icons.qr_code_rounded,
                  colorScheme: colorScheme,
                ),
              ],
              const SizedBox(height: 10),
              _buildReadOnlyTile(
                label: 'Barcode',
                value: _barcodeController.text.trim().isNotEmpty
                    ? _barcodeController.text.trim()
                    : 'No barcode assigned',
                icon: Icons.qr_code_2_rounded,
                colorScheme: colorScheme,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Pricing & Margins Card ──────────────────────────────────
          _buildSectionCard(
            colorScheme: colorScheme,
            icon: Icons.payments_outlined,
            iconColor: const Color(0xFF15803D),
            title: _isSalesman ? 'Pricing' : 'Pricing & Margins',
            children: [
              Row(
                spacing: 12,
                children: [
                  if (!_isSalesman)
                    Expanded(
                      child: _buildReadOnlyPriceBox(
                        label: 'Buying Price',
                        value: currencyFormat.format(_buyingPrice),
                        color: const Color(0xFF2563EB),
                        icon: Icons.shopping_cart_outlined,
                        colorScheme: colorScheme,
                      ),
                    ),
                  Expanded(
                    child: _buildReadOnlyPriceBox(
                      label: 'Selling Price',
                      value: currencyFormat.format(_sellingPrice),
                      color: const Color(0xFF15803D),
                      icon: Icons.sell_outlined,
                      colorScheme: colorScheme,
                    ),
                  ),
                ],
              ),
              if (!_isSalesman && _buyingPrice > 0 && _sellingPrice > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: marginColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: marginColor.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildMarginStat(label: 'Margin', value: currencyFormat.format(_margin), color: marginColor),
                        Container(width: 1, height: 28, color: marginColor.withValues(alpha: 0.3)),
                        _buildMarginStat(
                          label: 'Margin %',
                          value: '${isPositiveMargin ? '+' : ''}${_marginPercent.toStringAsFixed(1)}%',
                          color: marginColor,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          if (_category == 'By Case') ...[
            const SizedBox(height: 16),
            _buildSectionCard(
              colorScheme: colorScheme,
              icon: Icons.assignment_return_outlined,
              iconColor: const Color(0xFFE11D48),
              title: 'Bad Order Refund Rates',
              children: [
                () {
                  final pieces = int.tryParse(_boPiecesPerCaseController.text.trim()) ?? 0;
                  final hasValidPieces = pieces >= 2 && pieces <= 999;
                  if (!hasValidPieces) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFFDC2626)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _isSalesman
                                  ? 'Pieces per case not configured. Ask admin to set pieces per case before creating bad orders.'
                                  : 'Pieces per case not configured. Edit product to set pieces per case (2–999) to enable bad orders.',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B)),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final storeRate = _sellingPrice / pieces;
                  final supplierRate = _buyingPrice / pieces;
                  return Column(
                    children: [
                      _buildReadOnlyTile(
                        label: 'Pieces Per Case',
                        value: '$pieces pcs/case',
                        icon: Icons.inventory_2_outlined,
                        colorScheme: colorScheme,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        spacing: 12,
                        children: [
                          Expanded(
                            child: _buildReadOnlyPriceBox(
                              label: 'Store Refund / Piece',
                              value: '${currencyFormat.format(storeRate)} / pc',
                              color: const Color(0xFFE11D48),
                              icon: Icons.storefront_outlined,
                              colorScheme: colorScheme,
                            ),
                          ),
                          if (!_isSalesman)
                            Expanded(
                              child: _buildReadOnlyPriceBox(
                                label: 'Supplier Refund / Piece',
                                value: '${currencyFormat.format(supplierRate)} / pc',
                                color: const Color(0xFFD97706),
                                icon: Icons.local_shipping_outlined,
                                colorScheme: colorScheme,
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                }(),
              ],
            ),
          ],

          // ── Stock & Inventory Card (Dealer Mode) ────────────────────
          if (dealerP != null) ...[
            const SizedBox(height: 16),
            _buildSectionCard(
              colorScheme: colorScheme,
              icon: Icons.warehouse_outlined,
              iconColor: stockBadgeColor,
              title: 'Stock & Inventory',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '$stockQty',
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 6),
                              const Text('pcs in stock', style: TextStyle(fontSize: 13, color: Colors.grey)),
                            ],
                          ),
                          if (reservedQty > 0) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Reserved: $reservedQty pcs • Available: $availableQty pcs',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: stockBadgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: stockBadgeColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isOutOfStock
                                ? Icons.cancel_outlined
                                : isLowStock
                                    ? Icons.warning_amber_rounded
                                    : Icons.check_circle_outline_rounded,
                            size: 15,
                            color: stockBadgeColor,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            stockStatusLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: stockBadgeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        'Low Stock Alert: $lowStockThreshold pcs'
                        '${dealerP.maxStock > 0 ? ' • Max Stock: ${dealerP.maxStock} pcs' : ''}',
                        style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),

          // ── Catalog Status Card ─────────────────────────────────────
          _buildSectionCard(
            colorScheme: colorScheme,
            icon: Icons.toggle_on_outlined,
            iconColor: colorScheme.primary,
            title: 'Catalog Status',
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isActive ? const Color(0xFF15803D) : colorScheme.onSurfaceVariant).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                      size: 20,
                      color: isActive ? const Color(0xFF15803D) : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isActive ? 'Active in Catalog' : 'Inactive in Catalog',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isActive ? const Color(0xFF15803D) : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isActive
                              ? 'This product is visible and available for salesman order booking.'
                              : 'This product is hidden from salesman order booking.',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          if (dealerP?.importedAt != null || dealerP?.updatedAt != null || adminP?.createdAt != null || adminP?.updatedAt != null) ...[
            const SizedBox(height: 16),
            _buildSectionCard(
              colorScheme: colorScheme,
              icon: Icons.history_rounded,
              iconColor: colorScheme.onSurfaceVariant,
              title: 'Record History',
              children: [
                if (adminP?.createdAt != null || dealerP?.importedAt != null)
                  _buildHistoryRow(
                    label: adminP?.createdAt != null ? 'Created' : 'Imported',
                    timestamp: adminP?.createdAt ?? dealerP!.importedAt!,
                    colorScheme: colorScheme,
                  ),
                if (adminP?.updatedAt != null || dealerP?.updatedAt != null) ...[
                  const SizedBox(height: 6),
                  _buildHistoryRow(
                    label: 'Last Updated',
                    timestamp: adminP?.updatedAt ?? dealerP!.updatedAt!,
                    colorScheme: colorScheme,
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 24),

          // ── Actions ─────────────────────────────────────────────────
          if (_isAdmin) ...[
            FilledButton.icon(
              onPressed: () => setState(() => _isReadOnly = false),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Edit Product (Admin)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Back to Catalog', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyTile({
    required String label,
    required String value,
    required IconData icon,
    required ColorScheme colorScheme,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildReadOnlyPriceBox({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryRow({
    required String label,
    required Timestamp timestamp,
    required ColorScheme colorScheme,
  }) {
    final formatted = DateFormat('MMM dd, yyyy • hh:mm a').format(timestamp.toDate());
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
        Text(formatted, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildImagePickerCard(ColorScheme colorScheme) {
    final bool hasImageData = _image != null || _networkImagePath.isNotEmpty;

    return _buildSectionCard(
      colorScheme: colorScheme,
      icon: Icons.image_outlined,
      iconColor: colorScheme.primary,
      title: 'Product Image',
      children: [
        hasImageData
            ? Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => Helperfunctions.navigateTo(
                          context,
                          ImageViewerPage(image: _image, networkImagePath: _networkImagePath),
                        ),
                        child: Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(10)),
                          child: _image != null
                              ? Image.file(_image!, fit: BoxFit.cover)
                              : Image.network(
                                  _networkImagePath,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const Center(child: CircularProgressIndicator());
                                  },
                                  errorBuilder: (_, _, _) => Container(
                                    height: 200,
                                    color: colorScheme.surfaceContainerHighest,
                                    alignment: Alignment.center,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.broken_image_outlined, size: 36, color: colorScheme.onSurfaceVariant),
                                        const SizedBox(height: 4),
                                        Text('Unable to load image', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Helperfunctions.navigateTo(
                              context,
                              ImageViewerPage(image: _image, networkImagePath: _networkImagePath),
                            ),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.fullscreen, size: 16),
                            label: const Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _showImageSourceSelector,
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.replay, size: 16),
                            label: const Text('Retake', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final oldLocalFile = _image;
                              setState(() {
                                _image = null;
                                _networkImagePath = '';
                              });
                              _cleanupLocalFile(oldLocalFile);
                            },
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('Delete', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            : InkWell(
                onTap: _showImageSourceSelector,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant, width: 1.2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: Icon(Icons.add_a_photo_outlined, size: 32, color: colorScheme.primary),
                      ),
                      const SizedBox(height: 10),
                      const Text('Tap to attach product image', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Take a photo or choose from gallery', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
      ],
    );
  }

  Widget _buildSectionCard({
    required ColorScheme colorScheme,
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 22),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    Widget? suffixIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          onChanged: onChanged,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildPriceField({required String label, required TextEditingController controller, required Color color, required IconData icon}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
          onChanged: (_) => setState(() {}),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            final val = double.tryParse(v.trim());
            if (val == null || val < 0) return 'Must be >= 0';
            return null;
          },
          decoration: InputDecoration(
            hintText: '0.00',
            prefixIcon: Icon(icon, size: 20, color: color),
            prefixText: '₱ ',
            prefixStyle: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color.withValues(alpha: 0.3))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildMarginStat({required String label, required String value, required Color color}) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7))),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
