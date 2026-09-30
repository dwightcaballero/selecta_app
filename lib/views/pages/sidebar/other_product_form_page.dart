import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/controllers/other_product_controller.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/other_product.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/imageviewer_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

/// Add / Edit form for a single OtherProduct entry in the dealer catalog.
class OtherProductFormPage extends StatefulWidget {
  final String? productId;
  final OtherProduct? existingProduct;

  const OtherProductFormPage({super.key, this.productId, this.existingProduct});

  @override
  State<OtherProductFormPage> createState() => _OtherProductFormPageState();
}

class _OtherProductFormPageState extends State<OtherProductFormPage> {
  final OtherProductController _controller = OtherProductController();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _buyingPriceController;
  late final TextEditingController _sellingPriceController;

  File? _image;
  String _networkImagePath = '';
  final ImagePicker _picker = ImagePicker();

  bool _isSaving = false;
  bool _isActive = true;

  bool get _isEditing => widget.productId != null;

  final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    final p = widget.existingProduct;
    _nameController = TextEditingController(text: p?.productName ?? '');
    _networkImagePath = p?.imageUrl ?? '';
    _buyingPriceController = TextEditingController(
      text: p != null && p.buyingPrice > 0 ? p.buyingPrice.toStringAsFixed(2) : '',
    );
    _sellingPriceController = TextEditingController(
      text: p != null && p.sellingPrice > 0 ? p.sellingPrice.toStringAsFixed(2) : '',
    );
    _isActive = p?.isActive ?? true;
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

    final tempProduct = OtherProduct(
      productName: _nameController.text.trim(),
      imageUrl: '',
      buyingPrice: _buyingPrice,
      sellingPrice: _sellingPrice,
      isActive: _isActive,
    );

    final errors = _controller.validate(tempProduct);
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
        return;
      }
      if (pickedLocalFile != null) {
        await _cleanupLocalFile(pickedLocalFile);
      }

      final product = OtherProduct(
        productName: _nameController.text.trim(),
        imageUrl: finalImageUrl,
        buyingPrice: _buyingPrice,
        sellingPrice: _sellingPrice,
        isActive: _isActive,
      );

      if (_isEditing) {
        await _controller.updateProduct(widget.productId!, product);
        if (mounted) {
          ShowMessage.success(context, 'Product updated successfully!');
          Navigator.pop(context);
        }
      } else {
        await _controller.addProduct(product);
        if (mounted) {
          ShowMessage.success(context, 'Product added successfully!');
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
      title: 'Delete Product',
      message: 'Are you sure you want to delete "${_nameController.text.trim()}"? This action cannot be undone.',
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
      await _controller.deleteProduct(widget.productId!);
      if (mounted) {
        ShowMessage.success(context, 'Product deleted successfully.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to delete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CustomAppbar(
        title: _isEditing ? 'Edit Product' : 'Add Product',
        subtitle: _isEditing ? 'Update product details' : 'New catalog entry',
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
              // ── Product Image Picker Card ─────────────────────────────
              _buildImagePickerCard(colorScheme),

              const SizedBox(height: 16),

              // ── Product Details Card ───────────────────────────────────
              _buildSectionCard(
                colorScheme: colorScheme,
                icon: Icons.inventory_2_outlined,
                iconColor: colorScheme.primary,
                title: 'Product Information',
                children: [
                  _buildField(
                    label: 'Product Name *',
                    controller: _nameController,
                    hint: 'e.g. P20 SELECTA OOH CRUNCHY BALLS 24X50ML',
                    icon: Icons.label_outline_rounded,
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Product name is required' : null,
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

              const SizedBox(height: 16),

              // ── Status Card ────────────────────────────────────────────
              _buildSectionCard(
                colorScheme: colorScheme,
                icon: Icons.toggle_on_outlined,
                iconColor: colorScheme.primary,
                title: 'Status',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isActive ? 'This product is visible and available for ordering.' : 'This product is hidden from ordering.',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Switch(value: _isActive, onChanged: (v) => setState(() => _isActive = v), activeThumbColor: colorScheme.primary),
                    ],
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
                  _isSaving ? 'Saving...' : (_isEditing ? 'Save Changes' : 'Add Product'),
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
            if (val == null || val <= 0) return 'Must be > 0';
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
