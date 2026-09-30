import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/controllers/selecta_product_controller.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/admin_selecta_product.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/imageviewer_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

/// Form page for Admins to Add or Edit an [AdminSelectaProduct].
/// The Admin model consists solely of: product image, product name, buying price, and selling price.
class SelectaProductFormPage extends StatefulWidget {
  final String? productId;
  final AdminSelectaProduct? existingProduct;

  const SelectaProductFormPage({
    super.key,
    this.productId,
    this.existingProduct,
  });

  @override
  State<SelectaProductFormPage> createState() => _SelectaProductFormPageState();
}

class _SelectaProductFormPageState extends State<SelectaProductFormPage> {
  final SelectaProductController _controller = SelectaProductController();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _buyingPriceController;
  late final TextEditingController _sellingPriceController;
  String _category = 'By Piece';
  String _tag = ProductTag.none;

  File? _image;
  String _networkImagePath = '';
  final ImagePicker _picker = ImagePicker();

  bool _isSaving = false;

  bool get _isEditing => widget.productId != null;

  final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    final p = widget.existingProduct;
    _nameController = TextEditingController(text: p?.productName ?? '');
    final rawCat = (p?.category ?? '').trim();
    final isCase = rawCat.toLowerCase() == 'by case' || rawCat.toLowerCase() == 'case';
    _category = isCase ? 'By Case' : 'By Piece';
    _tag = p?.tag ?? ProductTag.none;
    _buyingPriceController = TextEditingController(
      text: p != null && p.buyingPrice > 0 ? p.buyingPrice.toStringAsFixed(2) : '',
    );
    _sellingPriceController = TextEditingController(
      text: p != null && p.sellingPrice > 0 ? p.sellingPrice.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _buyingPriceController.dispose();
    _sellingPriceController.dispose();
    super.dispose();
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

    final tempProduct = AdminSelectaProduct(
      id: widget.productId ?? '',
      productName: _nameController.text.trim(),
      imageUrl: '',
      buyingPrice: _buyingPrice,
      sellingPrice: _sellingPrice,
      category: _category,
      tag: _tag,
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
        imageUrl: finalImageUrl,
        buyingPrice: _buyingPrice,
        sellingPrice: _sellingPrice,
        category: _category,
        tag: _tag,
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
    try {
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
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to delete product: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CustomAppbar(
        title: _isEditing ? 'Edit Selecta Product' : 'Add Selecta Product',
        subtitle: _isEditing ? 'Master Admin Catalog' : 'New Master Catalog Entry',
        actions: _isEditing
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                  onPressed: _confirmDelete,
                  tooltip: 'Delete Product',
                ),
              ]
            : null,
      ),
      body: Form(
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
                        });
                      },
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                        selectedForegroundColor: colorScheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
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
              FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(_isEditing ? Icons.save_rounded : Icons.add_rounded, size: 20),
                label: Text(
                  _isSaving ? 'Saving...' : (_isEditing ? 'Save Changes' : 'Add Selecta Product'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
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
