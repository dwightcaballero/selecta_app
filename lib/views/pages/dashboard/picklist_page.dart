import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/delivery_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/views/pages/dashboard/book_order_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/digital_receipt_dialog.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';
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
  bool _isSaving = false;

  String _itemFilter = 'All'; // 'All', 'Pending', 'Picked'
  List<int> _selectaCaseIndices = [];
  List<int> _selectaPieceIndices = [];
  List<int> _otherIndices = [];

  @override
  void initState() {
    super.initState();
    _currentDelivery = widget.delivery;
    _items = widget.delivery.items.map((item) => item.copyWith()).toList();
    _networkImagePath = widget.delivery.imagePath;
    _groupAndSortItemIndices();
    _prefetchData();
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
      return Helperfunctions.compareBySrpAndName(
        nameA: itemA.productName,
        priceA: itemA.sellingPrice,
        nameB: itemB.productName,
        priceB: itemB.sellingPrice,
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
    if (mounted) {
      setState(() {
        _isDealer = dealer;
      });
    }
  }

  bool get _hasProofOfDelivery => _pickedImage != null || _networkImagePath.trim().isNotEmpty;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source, maxWidth: 1200, maxHeight: 1200, imageQuality: 80);
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
    return _items.fold<int>(0, (sum, item) => sum + item.pickedQuantity);
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
    setState(() {
      for (int i = 0; i < _items.length; i++) {
        _items[i] = _items[i].copyWith(isPicked: target);
      }
    });
  }

  void _toggleCategoryPicked(List<int> indices) {
    if (indices.isEmpty) return;
    HapticFeedback.lightImpact();
    final allCategoryPicked = indices.every((i) => _items[i].isPicked);
    final target = !allCategoryPicked;
    setState(() {
      for (final i in indices) {
        _items[i] = _items[i].copyWith(isPicked: target);
      }
    });
  }

  void _toggleItemPicked(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      final item = _items[index];
      _items[index] = item.copyWith(isPicked: !item.isPicked);
    });
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
        ShowMessage.success(context, 'Picklist draft saved.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to save progress: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onCompletePicklist() async {
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

    setState(() => _isSaving = true);
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
      );

      if (!mounted) return;

      setState(() {
        _currentDelivery = updatedDelivery;
        _networkImagePath = updatedDelivery.imagePath;
        _pickedImage = null;
      });

      ShowMessage.success(context, 'Picklist completed! [${updatedDelivery.storeName}] is now For Delivery.');

      // Generate digital receipt (text only) that can also be printed on a thermal printer via Bluetooth
      await DigitalReceiptDialog.show(
        context,
        delivery: updatedDelivery,
        deliveryId: widget.deliveryID,
        proceedLabel: 'Close',
        onProceed: () {
          if (!mounted) return;
          Navigator.pop(context, true);
        },
      );
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Error completing picklist: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onDeleteOrder() async {
    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Delete Order',
      message: 'Delete this booked order for [${_currentDelivery.storeName}]? Reserved stock will be released back to inventory.',
      isDestructive: true,
      icon: Icons.delete_outline,
      confirmText: 'Delete',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _controller.deleteDelivery(context: context, deliveryId: widget.deliveryID, delivery: _currentDelivery);
      if (mounted) {
        ShowMessage.success(context, 'Deleted order for [${_currentDelivery.storeName}].');
        Navigator.pop(context, true);
      }
    } catch (e) {
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

  Widget _buildProgressHeader(ColorScheme colorScheme) {
    final totalLines = _items.length;
    final pickedLines = _pickedLinesCount;
    final progress = totalLines == 0 ? 0.0 : pickedLines / totalLines;
    final isComplete = _allItemsPicked;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
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
            color: isSelected
                ? (badgeColor?.withValues(alpha: 0.12) ?? colorScheme.primaryContainer.withValues(alpha: 0.4))
                : colorScheme.surface,
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
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  icon: Icon(allPicked ? Icons.remove_done_rounded : Icons.done_all_rounded, size: 15),
                  label: Text(
                    allPicked ? 'Uncheck' : 'Check All',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
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

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isPicked ? Colors.green.withValues(alpha: 0.06) : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isPicked ? Colors.green.withValues(alpha: 0.45) : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isPicked ? 1.3 : 1.0,
        ),
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
                  activeColor: Colors.green.shade700,
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
                child: Text(
                  item.productName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: isPicked ? Colors.green.shade800 : colorScheme.onSurface,
                    decoration: isPicked ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.green.shade700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isPicked ? Colors.green.withValues(alpha: 0.15) : colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isPicked ? Colors.green.withValues(alpha: 0.3) : colorScheme.primary.withValues(alpha: 0.2)),
                ),
                child: Text(
                  '×${item.pickedQuantity}',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: isPicked ? Colors.green.shade700 : colorScheme.primary),
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

  Widget _buildStickyBottomBar(ColorScheme colorScheme) {
    final hasProof = _hasProofOfDelivery;
    final canComplete = !_isSaving && _allItemsPicked && hasProof;

    return SafeArea(
      child: Container(
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
                    onPressed: _isSaving ? null : _onDeleteOrder,
                    tooltip: 'Delete Order',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 22),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : _onSaveProgress,
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
                  child: FilledButton.icon(
                    onPressed: canComplete ? _onCompletePicklist : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.local_shipping_outlined, size: 20),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final deliveryDate = _currentDelivery.deliveryDate?.toDate() ?? DateTime.now();

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

    int calcUnits(List<int> idxs) => idxs.fold<int>(0, (sum, i) => sum + _items[i].pickedQuantity);

    return PopScope(
      canPop: !_hasUnsavedChanges || _isSaving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
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
      },
      child: Scaffold(
        appBar: CustomAppbar(
          title: _currentDelivery.storeName,
          subtitle: 'Picklist • ${Helperfunctions.formatDateForDisplay(deliveryDate)}',
          centerTitle: false,
          actions: [
            _buildAppBarIconAction(
              icon: Icons.edit_note_rounded,
              tooltip: 'Edit Order in Book Order Page',
              onTap: _isSaving ? null : _openEditOrderProducts,
            ),
          ],
        ),
        bottomNavigationBar: _buildStickyBottomBar(colorScheme),
        body: Column(
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
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _openEditOrderProducts,
                              icon: const Icon(Icons.edit_note_rounded, size: 20),
                              label: const Text('Edit Order', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                            ),
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
                                OutlinedButton(
                                  onPressed: () => setState(() => _itemFilter = 'All'),
                                  child: const Text('Show All Items'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          children: [
                            if (visibleSelectaCase.isNotEmpty) ...[
                              _buildGroupHeader(
                                title: 'Selecta Products (By Case)',
                                icon: Icons.all_inbox_rounded,
                                color: Colors.deepOrange.shade700,
                                totalUnits: calcUnits(visibleSelectaCase),
                                categoryIndices: visibleSelectaCase,
                              ),
                              ...visibleSelectaCase.map((idx) => _buildPicklistItemTile(idx, colorScheme)),
                            ],
                            if (visibleSelectaPiece.isNotEmpty) ...[
                              _buildGroupHeader(
                                title: 'Selecta Products (By Piece)',
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
        ),
      ),
    );
  }
}
