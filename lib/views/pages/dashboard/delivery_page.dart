import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:selecta_ops/controllers/badorder_controller.dart';
import 'package:selecta_ops/controllers/delivery_controller.dart';
import 'package:selecta_ops/controllers/selecta_product_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/data.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/badorder.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/views/pages/dashboard/picklist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/return_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/digital_receipt_dialog.dart';
import 'package:selecta_ops/views/widgets/hapistore_dropdown.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';

class DeliveryPage extends StatefulWidget {
  const DeliveryPage({super.key, required this.deliveryID, required this.delivery});

  final Delivery delivery;
  final String deliveryID;

  @override
  State<DeliveryPage> createState() => _DeliveryPageState();
}

class _DeliveryPageState extends State<DeliveryPage> {
  final DeliveryController _controller = DeliveryController();
  late Delivery _currentDelivery;
  bool hasBreakdownForDay = false;
  bool isDayVerified = false;
  bool get isPermanentlySettled =>
      _currentDelivery.isReturnApprovedByDealer || _currentDelivery.isInventorySettled;

  bool get isLocked {
    if (isPermanentlySettled) return true;
    if (!isDealer) {
      return isDayVerified || hasBreakdownForDay;
    }
    return false;
  }

  bool get isSalesmanLocked => isLocked;

  bool get isDealerLateReconciliation =>
      isDealer && isDayVerified && !_currentDelivery.isInventorySettled && widget.deliveryID.isNotEmpty;

  bool _withReturns = false;
  final Map<String, int> _returnQuantities = {};
  final Set<String> _selectedReturnProductIds = {};
  int _recordedBadOrdersCount = 0;

  double get originalOrderTotal {
    final orig = _currentDelivery.originalOrderAmount;
    if (orig != null && orig > 0) {
      return orig;
    }
    if (_currentDelivery.items.isNotEmpty) {
      return _currentDelivery.items.fold<double>(0.0, (acc, i) => acc + (i.pickedQuantity * i.sellingPrice));
    }
    return _currentDelivery.orderAmount;
  }

  double get calculatedItemsReturnAmount {
    if (!_withReturns || _currentDelivery.items.isEmpty) return 0.0;
    double sum = 0.0;
    for (final item in _currentDelivery.items) {
      if (_selectedReturnProductIds.contains(item.productId)) {
        final qty = _returnQuantities[item.productId] ?? 0;
        sum += (item.sellingPrice * qty);
      }
    }
    return sum;
  }

  double discrepancy = 0;
  double get effectiveOrderAmount =>
      txtOrderAmount.text.isNotEmpty ? Helperfunctions.formatStringAmountToDouble(txtOrderAmount.text) : _currentDelivery.orderAmount;
  TextEditingController dropdownHapiStore = TextEditingController();
  TextEditingController dropdownStatus = TextEditingController();
  bool isDealer = true;
  List<DropdownMenuEntry<String>> listDropdownStatus = [];
  List<DropdownMenuEntry<String>> listDropdownStore = [];
  String networkImagePath = '';
  bool sendText = false;
  String simDetails = '';
  TextEditingController txtCashAmount = TextEditingController();
  TextEditingController txtCreditAmount = TextEditingController();
  TextEditingController txtOnlineAmount = TextEditingController();
  TextEditingController txtOrderAmount = TextEditingController();
  TextEditingController txtRemarks = TextEditingController();
  TextEditingController txtSMS = TextEditingController();
  List<KPlacement> listPlacement = [];
  String placementID = '';

  final _formkey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
    super.dispose();
    txtOrderAmount.dispose();
    txtCashAmount.dispose();
    txtOnlineAmount.dispose();
    txtCreditAmount.dispose();
    txtRemarks.dispose();
    txtSMS.dispose();
    dropdownStatus.dispose();
    dropdownHapiStore.dispose();
  }

  @override
  void initState() {
    super.initState();
    _currentDelivery = widget.delivery;
    if (widget.deliveryID.isNotEmpty) {
      _selectedDate = _currentDelivery.deliveryDate?.toDate() ?? DateTime.now();
      networkImagePath = _currentDelivery.imagePath;
      dropdownHapiStore.text = _currentDelivery.storeName;
      dropdownStatus.text = _currentDelivery.transactionStatus;
      txtRemarks.text = _currentDelivery.remarks;
      txtOrderAmount.text = Helperfunctions.formatDoubleAmountForField(_currentDelivery.orderAmount);
      txtCashAmount.text = Helperfunctions.formatDoubleAmountForField(_currentDelivery.cashAmount);
      txtOnlineAmount.text = Helperfunctions.formatDoubleAmountForField(_currentDelivery.onlineAmount);
      txtCreditAmount.text = Helperfunctions.formatDoubleAmountForField(_currentDelivery.creditAmount);

      if (_currentDelivery.items.isNotEmpty) {
        if (_currentDelivery.hasReturnedItems) {
          _withReturns = true;
          for (final item in _currentDelivery.items) {
            if (item.returnedQuantity > 0) {
              _selectedReturnProductIds.add(item.productId);
              _returnQuantities[item.productId] = item.returnedQuantity;
            } else {
              _returnQuantities[item.productId] = 0;
            }
          }
        } else {
          for (final item in _currentDelivery.items) {
            _returnQuantities[item.productId] = 0;
          }
        }
      }

      computeDiscrepancy();
    }
    prefetchData();
  }

  void onSave() async {
    if (isSalesmanLocked) {
      ShowMessage.error(context, 'Editing is disabled. A cash breakdown is already recorded for this day.');
      return;
    }
    if (_formkey.currentState!.validate()) {
      try {
        final newRecord = await _controller.createDelivery(
          context: context,
          storeName: dropdownHapiStore.text,
          orderAmountText: txtOrderAmount.text,
          selectedDate: _selectedDate,
          imageFile: null,
          placements: listPlacement,
          placementId: placementID,
          sendText: sendText,
          smsMessage: txtSMS.text,
        );

        if (mounted) {
          ShowMessage.success(context, 'Successfully created a new delivery record!\n[${newRecord.storeName}]');
          Navigator.pop(context); // go back to previous page
        }
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'Error creating delivery record: $e');
        }
      }
    } else {
      ShowMessage.error(context, 'Please fill up the required fields');
    }
  }

  void onChangeDate() async {
    final DateTime? dateTime = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(3000),
    );

    if (dateTime != null) {
      setState(() {
        _selectedDate = dateTime;
      });
      await _checkBreakdownStatus();
    }
  }

  Future<void> _checkBreakdownStatus() async {
    final status = await _controller.checkBreakdownAndVerificationStatus(_selectedDate);
    if (mounted) {
      setState(() {
        hasBreakdownForDay = status.hasBreakdown;
        isDayVerified = status.isVerified;
      });
    }
  }

  void prefetchData() async {
    final dealer = await _controller.checkIsDealer();

    if (widget.deliveryID.isNotEmpty) {
      String imgPath = _currentDelivery.imagePath;

      final latest = await _controller.getDeliveryById(widget.deliveryID);
      if (latest != null && mounted) {
        setState(() {
          _currentDelivery = latest;
          if (latest.imagePath.isNotEmpty) {
            imgPath = latest.imagePath;
          }
          if (latest.deliveryDate != null) {
            _selectedDate = latest.deliveryDate!.toDate();
          }
        });
      }

      await _checkBreakdownStatus();

      final entries = [
        DropdownMenuEntry(label: DeliveryStatus.pending, value: DeliveryStatus.pending),
        DropdownMenuEntry(label: DeliveryStatus.delivered, value: DeliveryStatus.delivered),
        DropdownMenuEntry(label: DeliveryStatus.returned, value: DeliveryStatus.returned),
      ];

      computeDiscrepancy();

      if (mounted) {
        setState(() {
          isDealer = dealer;
          networkImagePath = imgPath;
          listDropdownStatus = entries;
        });
      }
    } else {
      await _checkBreakdownStatus();
      if (mounted) {
        setState(() {
          isDealer = dealer;
        });
      }
      onStoreSelected();
    }
  }

  void onUpdate() async {
    if (isLocked) {
      final msg = _currentDelivery.isReturnApprovedByDealer
          ? 'Editing is locked. This returned order has already been approved by the dealer and cannot be modified.'
          : (_currentDelivery.isInventorySettled
              ? 'Editing is locked. This delivery order has already been settled into inventory.'
              : (isDayVerified
                  ? 'Editing is locked. This day\'s cash breakdown has been verified.'
                  : 'Editing is disabled. A cash breakdown is already recorded for this day.'));
      ShowMessage.error(context, msg);
      return;
    }

    if (isDealerLateReconciliation) {
      final confirmReconcile = await ShowMessage.confirm(
        context,
        title: 'Reconcile Late Delivery',
        message:
            'This date\'s cash breakdown has already been verified and closed.\n\n'
            'Updating this order will automatically reconcile and settle inventory movements for these items.\n\n'
            'Do you want to proceed?',
        confirmText: 'Update & Reconcile',
        icon: Icons.sync_problem_outlined,
      );
      if (confirmReconcile != true || !mounted) return;
    }

    final bool hasItemReturns = _withReturns && _currentDelivery.items.isNotEmpty && _selectedReturnProductIds.isNotEmpty;
    final double targetOrderAmount = hasItemReturns
        ? (originalOrderTotal - calculatedItemsReturnAmount).clamp(0.0, double.infinity)
        : effectiveOrderAmount;

    final listError = _controller.validateDeliveryForm(
      status: dropdownStatus.text,
      orderAmount: targetOrderAmount,
      cash: txtCashAmount.text,
      online: txtOnlineAmount.text,
      credit: txtCreditAmount.text,
      returnAmount: hasItemReturns
          ? Helperfunctions.formatDoubleAmountForField(calculatedItemsReturnAmount)
          : '0',
      remarks: txtRemarks.text,
      withItemReturns: hasItemReturns,
      hasReturnsRecorded: hasItemReturns,
    );

    if (listError.isEmpty) {
      try {
        List<OrderItem>? itemsWithReturns;
        if (_currentDelivery.items.isNotEmpty) {
          itemsWithReturns = _currentDelivery.items.map((item) {
            final isReturned = hasItemReturns && _selectedReturnProductIds.contains(item.productId);
            final retQty = isReturned ? (_returnQuantities[item.productId] ?? 0) : 0;
            return item.copyWith(returnedQuantity: retQty);
          }).toList();
        }

        final updatedDelivery = await _controller.updateDelivery(
          context: context,
          deliveryId: widget.deliveryID,
          currentDelivery: _currentDelivery,
          storeName: dropdownHapiStore.text,
          status: dropdownStatus.text,
          remarks: txtRemarks.text,
          orderAmountText: hasItemReturns
              ? Helperfunctions.formatDoubleAmountForField(targetOrderAmount)
              : txtOrderAmount.text,
          cashAmountText: txtCashAmount.text,
          onlineAmountText: txtOnlineAmount.text,
          creditAmountText: txtCreditAmount.text,
          returnAmountText: hasItemReturns
              ? Helperfunctions.formatDoubleAmountForField(calculatedItemsReturnAmount)
              : '0',
          imageFile: null,
          networkImagePath: networkImagePath,
          selectedDate: _selectedDate,
          itemsWithReturns: itemsWithReturns,
        );

        // If this was a late delivery reconciled on a verified date, settle inventory immediately
        if (isDealerLateReconciliation &&
            (dropdownStatus.text == DeliveryStatus.delivered || dropdownStatus.text == DeliveryStatus.returned)) {
          await _controller.settleSingleDelivery(widget.deliveryID);
        }

        if (mounted) {
          final successMsg = isDealerLateReconciliation &&
                  (dropdownStatus.text == DeliveryStatus.delivered || dropdownStatus.text == DeliveryStatus.returned)
              ? 'Successfully updated [${updatedDelivery.storeName}] and reconciled inventory!'
              : 'Successfully updated delivery record!\n[${updatedDelivery.storeName}]';
          ShowMessage.success(context, successMsg);
          Navigator.pop(context); // go back to previous page
        }
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'Error updating delivery record: $e');
        }
      }
    } else {
      if (mounted) ShowMessage.listError(context, listError);
    }
  }

  void onFocusChange(bool hasFocus, TextEditingController controller) {
    if (controller.text.isNotEmpty) {
      if (!hasFocus) {
        computeDiscrepancy();
        setState(() => controller.text = Helperfunctions.formatStringAmountForDisplay(controller.text));
      } else {
        setState(() => controller.text = Helperfunctions.formatStringAmountForEditing(controller.text));
      }
    } else {
      if (!hasFocus) {
        computeDiscrepancy();
      }
    }
  }

  void computeDiscrepancy() {
    final bool hasItemReturns = _withReturns && _currentDelivery.items.isNotEmpty && _selectedReturnProductIds.isNotEmpty;
    final double targetOrderAmount = hasItemReturns
        ? (originalOrderTotal - calculatedItemsReturnAmount).clamp(0.0, double.infinity)
        : effectiveOrderAmount;

    final result = _controller.computeDiscrepancy(
      orderAmount: targetOrderAmount,
      cash: txtCashAmount.text,
      online: txtOnlineAmount.text,
      credit: txtCreditAmount.text,
      returnAmount: '0',
      withItemReturns: hasItemReturns,
    );
    if (mounted) {
      setState(() {
        discrepancy = result;
      });
    }
  }

  Widget hapistoreDropdown() {
    return HapistorePickerField(
      controller: dropdownHapiStore,
      enabled: isDealer && !isSalesmanLocked,
      label: 'Hapi Store',
      validator: (value) => value == null || value.isEmpty ? 'Please select a Hapi Store' : null,
      onChanged: () {
        onStoreSelected();
      },
    );
  }

  void onStoreSelected() async {
    txtSMS.text = _controller.generateSmsMessage(storeName: dropdownHapiStore.text, formattedOrderAmount: txtOrderAmount.text);

    if (dropdownHapiStore.text.isNotEmpty) {
      final result = await _controller.loadPlacementsForStore(dropdownHapiStore.text);
      if (mounted) {
        setState(() {
          placementID = result.placementId;
          listPlacement = result.placements;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          placementID = '';
          listPlacement = [];
        });
      }
    }
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child, Widget? trailing}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 20, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildProofOfDeliveryCard() {
    final imagePath = networkImagePath.trim();
    final colorScheme = Theme.of(context).colorScheme;

    if (imagePath.isEmpty) {
      return _buildSectionCard(
        title: 'Proof of Delivery',
        icon: Icons.image_outlined,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.no_photography_outlined, size: 22, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No Proof of Delivery photo attached.',
                  style: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _buildSectionCard(
      title: 'Proof of Delivery',
      icon: Icons.image_outlined,
      trailing: OutlinedButton.icon(
        onPressed: () => Helperfunctions.navigateTo(context, ImageViewerPage(image: null, networkImagePath: imagePath)),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: const Icon(Icons.fullscreen, size: 16),
        label: const Text('View Full Screen'),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Helperfunctions.navigateTo(context, ImageViewerPage(image: null, networkImagePath: imagePath)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Image.network(
                imagePath,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: 200,
                    width: double.infinity,
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 200,
                  width: double.infinity,
                  color: colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_outlined, size: 36, color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 6),
                      Text('Unable to load Proof of Delivery image', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
                    Icon(Icons.zoom_in, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Tap image to zoom / inspect proof',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
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

  Widget _buildOrderAndStoreCard() {
    return _buildSectionCard(
      title: 'Order & Store Info',
      icon: Icons.storefront_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          hapistoreDropdown(),
          _buildMoneyField(
            label: 'Order Amount',
            controller: txtOrderAmount,
            prefixIcon: Icons.attach_money,
            iconColor: Colors.blue,
            isEnabled: isDealer && !isSalesmanLocked,
          ),
          _buildDatePickerField(
            label: 'Delivery Date',
            selectedDate: _selectedDate,
            isEnabled: isDealer && !isSalesmanLocked,
            onTap: isDealer && !isSalesmanLocked ? onChangeDate : null,
          ),
          if (widget.deliveryID.isNotEmpty) _buildDeliveryStatusSelector(),
        ],
      ),
    );
  }

  Widget _buildDeliveryStatusSelector() {
    String rawStatus = dropdownStatus.text.isNotEmpty ? dropdownStatus.text : DeliveryStatus.pending;
    String currentStatus = rawStatus == DeliveryStatus.pendingPicklist ? DeliveryStatus.pending : rawStatus;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delivery Status',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            segments: [
              ButtonSegment<String>(
                value: DeliveryStatus.pending,
                label: const Text('For Delivery', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                icon: Icon(
                  Icons.local_shipping_outlined,
                  size: 18,
                  color: currentStatus == DeliveryStatus.pending ? Colors.orange.shade800 : colorScheme.onSurfaceVariant,
                ),
              ),
              ButtonSegment<String>(
                value: DeliveryStatus.delivered,
                label: const Text(
                  DeliveryStatus.delivered,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                icon: Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: currentStatus == DeliveryStatus.delivered ? Colors.green.shade800 : colorScheme.onSurfaceVariant,
                ),
              ),
              ButtonSegment<String>(
                value: DeliveryStatus.returned,
                label: const Text(DeliveryStatus.returned, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                icon: Icon(
                  Icons.assignment_return_outlined,
                  size: 18,
                  color: currentStatus == DeliveryStatus.returned ? Colors.red.shade800 : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            selected: {currentStatus},
            onSelectionChanged: isSalesmanLocked
                ? null
                : (Set<String> newSelection) {
                    setState(() {
                      dropdownStatus.text = newSelection.first;
                    });
                  },
          ),
        ),
      ],
    );
  }

  Widget _buildWithReturnsSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildSectionCard(
      title: 'Itemized Returns',
      icon: Icons.assignment_return_outlined,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Text(
          'Total Return: ${Helperfunctions.formatDoubleAmountForDisplay(calculatedItemsReturnAmount)}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.red.shade800,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            value: _withReturns,
            onChanged: isLocked
                ? null
                : (val) {
                    setState(() {
                      _withReturns = val ?? false;
                      if (!_withReturns) {
                        _selectedReturnProductIds.clear();
                      }
                      computeDiscrepancy();
                    });
                  },
            title: const Text(
              'With Returns',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: const Text(
              'Mark specific products or quantities being returned for this delivery.',
              style: TextStyle(fontSize: 12.5),
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_withReturns) ...[
            const Divider(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Original Order Total:', style: TextStyle(fontSize: 13)),
                      Text(
                        Helperfunctions.formatDoubleAmountForDisplay(originalOrderTotal),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Return Deduction:', style: TextStyle(fontSize: 13, color: Colors.red.shade800)),
                      Text(
                        '- ${Helperfunctions.formatDoubleAmountForDisplay(calculatedItemsReturnAmount)}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Adjusted Delivered Total:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      Text(
                        Helperfunctions.formatDoubleAmountForDisplay((originalOrderTotal - calculatedItemsReturnAmount).clamp(0.0, double.infinity)),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedReturnProductIds.isEmpty
                        ? 'No products marked for return.'
                        : '${_selectedReturnProductIds.length} ${_selectedReturnProductIds.length == 1 ? 'product' : 'products'} marked (${_selectedReturnProductIds.fold<int>(0, (acc, id) => acc + (_returnQuantities[id] ?? 0))} units)',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: isLocked ? null : _openItemizedReturnsModal,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                  label: Text(
                    _selectedReturnProductIds.isEmpty ? 'Select Returns' : 'Manage Returns',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            if (_selectedReturnProductIds.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _currentDelivery.items.where((i) => _selectedReturnProductIds.contains(i.productId)).map((item) {
                  final qty = _returnQuantities[item.productId] ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${item.productName} × $qty',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.red.shade900),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          Helperfunctions.formatDoubleAmountForDisplay(item.sellingPrice * qty),
                          style: TextStyle(fontSize: 12, color: Colors.red.shade800, fontWeight: FontWeight.w600),
                        ),
                        if (!isLocked) ...[
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () {
                              setState(() {
                                _selectedReturnProductIds.remove(item.productId);
                                computeDiscrepancy();
                              });
                            },
                            child: Icon(Icons.close, size: 16, color: Colors.red.shade700),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _openItemizedReturnsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return _ItemizedReturnsBottomSheet(
          items: _currentDelivery.items,
          initialSelectedIds: _selectedReturnProductIds,
          initialQuantities: _returnQuantities,
          isLocked: isLocked,
          onApply: (newSelectedIds, newQuantities) {
            setState(() {
              _selectedReturnProductIds.clear();
              _selectedReturnProductIds.addAll(newSelectedIds);
              _returnQuantities.clear();
              _returnQuantities.addAll(newQuantities);
              computeDiscrepancy();
            });
            // After asking if there are returned products, also prompt if there are bad orders from the store
            if (!isPermanentlySettled) {
              Future.delayed(const Duration(milliseconds: 350), () {
                if (mounted) _promptForBadOrders();
              });
            }
          },
        );
      },
    );
  }

  void _openBadOrderModal() {
    if (isPermanentlySettled) {
      ShowMessage.error(context, 'Bad orders cannot be recorded for a delivery that has already been settled.');
      return;
    }
    if (dropdownHapiStore.text.isEmpty) {
      ShowMessage.error(context, 'Please select a store first before recording bad orders.');
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return _DeliveryBadOrderBottomSheet(
          storeName: dropdownHapiStore.text,
          deliveryDate: _selectedDate,
          onBadOrderSaved: () {
            setState(() {
              _recordedBadOrdersCount++;
            });
          },
        );
      },
    );
  }

  Future<void> _promptForBadOrders() async {
    if (isPermanentlySettled || dropdownHapiStore.text.isEmpty) return;
    final askBo = await ShowMessage.confirm(
      context,
      title: 'Bad Orders from Store?',
      message: 'Are there any bad orders (damaged or expired products) to pull out from [${dropdownHapiStore.text}]?',
      icon: Icons.remove_shopping_cart_outlined,
      confirmText: 'Yes, Record Bad Order',
      cancelText: 'No Bad Orders',
    );
    if (askBo == true && mounted) {
      _openBadOrderModal();
    }
  }

  Widget _buildBadOrdersSection() {
    final colorScheme = Theme.of(context).colorScheme;
    final bool cannotRecord = isPermanentlySettled;

    return _buildSectionCard(
      title: 'Bad Orders from Store',
      icon: Icons.remove_shopping_cart_outlined,
      trailing: _recordedBadOrdersCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                '$_recordedBadOrdersCount Recorded',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                ),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cannotRecord
                ? 'This delivery is already settled. Bad orders can no longer be recorded.'
                : 'Pull out and record damaged or expired Selecta products directly from ${dropdownHapiStore.text}.',
            style: TextStyle(
              fontSize: 13,
              color: cannotRecord ? Colors.red.shade700 : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: cannotRecord ? null : _openBadOrderModal,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(_recordedBadOrdersCount > 0 ? 'Record Another Bad Order' : 'Record Bad Orders'),
            style: OutlinedButton.styleFrom(
              foregroundColor: cannotRecord ? Colors.grey : Colors.orange.shade800,
              side: BorderSide(
                color: cannotRecord ? Colors.grey.shade300 : Colors.orange.shade300,
                width: 1.2,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentBreakdownCard() {
    return _buildSectionCard(
      title: 'Payment Breakdown',
      icon: Icons.payments_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          _buildPaymentSummary(),
          _buildQuickFillChips(),
          _buildMoneyField(
            label: 'Cash Amount',
            controller: txtCashAmount,
            prefixIcon: Icons.payments_outlined,
            iconColor: Colors.green,
            isRequired: false,
            isEnabled: !isSalesmanLocked,
          ),
          _buildMoneyField(
            label: 'Online Amount',
            controller: txtOnlineAmount,
            prefixIcon: Icons.account_balance_outlined,
            iconColor: Colors.blue,
            isRequired: false,
            isEnabled: !isSalesmanLocked,
          ),
          _buildMoneyField(
            label: 'Credit Amount',
            controller: txtCreditAmount,
            prefixIcon: Icons.credit_card_outlined,
            iconColor: Colors.purple,
            isRequired: false,
            isEnabled: !isSalesmanLocked,
          ),
          if (_withReturns && _currentDelivery.items.isNotEmpty && calculatedItemsReturnAmount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.assignment_return_outlined, color: Colors.red.shade700, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Returned Products Amount',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(calculatedItemsReturnAmount),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.5,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMoneyField({
    required String label,
    required TextEditingController controller,
    required IconData prefixIcon,
    Color? iconColor,
    bool isRequired = true,
    bool isEnabled = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Focus(
      onFocusChange: (hasFocus) => onFocusChange(hasFocus, controller),
      child: TextFormField(
        enabled: isEnabled,
        controller: controller,
        textAlign: TextAlign.end,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
        autovalidateMode: AutovalidateMode.onUnfocus,
        onChanged: (_) => computeDiscrepancy(),
        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
          prefixIcon: Icon(prefixIcon, size: 22, color: iconColor ?? colorScheme.primary),
          prefixText: '₱ ',
          prefixStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        validator: (value) {
          if (isRequired) {
            double amount = Helperfunctions.formatStringAmountToDouble(controller.text);
            if (amount <= 0) return '$label should be greater than 0';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildDatePickerField({required String label, required DateTime selectedDate, required VoidCallback? onTap, bool isEnabled = true}) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool canTap = isEnabled && onTap != null;
    return InkWell(
      onTap: canTap ? onTap : (isEnabled ? null : () => ShowMessage.info(context, 'Only dealers can change the delivery date.')),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: canTap ? 1.0 : 0.5)),
          color: canTap ? null : colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_outlined, size: 22, color: canTap ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
                Text(
                  Helperfunctions.formatDateForDisplay(selectedDate),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: canTap ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (canTap)
              Icon(Icons.edit_calendar_outlined, size: 20, color: colorScheme.primary)
            else
              Icon(Icons.lock_outline, size: 18, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFillChips() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt, size: 18, color: Colors.amber[800]),
            const SizedBox(width: 4),
            Text(
              'Quick-Fill Total Order:',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 8,
            children: [
              ActionChip(
                avatar: Icon(Icons.payments_outlined, size: 18, color: colorScheme.primary),
                label: Text(
                  'Full Cash',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                ),
                onPressed: isSalesmanLocked ? null : () => _quickFillPayment(target: 'cash'),
              ),
              ActionChip(
                avatar: Icon(Icons.account_balance_outlined, size: 18, color: colorScheme.primary),
                label: Text(
                  'Full Online',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                ),
                onPressed: isSalesmanLocked ? null : () => _quickFillPayment(target: 'online'),
              ),
              ActionChip(
                avatar: Icon(Icons.credit_card_outlined, size: 18, color: colorScheme.primary),
                label: Text(
                  'Full Credit',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                ),
                onPressed: isSalesmanLocked ? null : () => _quickFillPayment(target: 'credit'),
              ),
              ActionChip(
                avatar: Icon(Icons.restart_alt, size: 18, color: colorScheme.error),
                label: Text(
                  'Clear All',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colorScheme.error),
                ),
                onPressed: isSalesmanLocked ? null : () => _quickFillPayment(target: 'clear'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _quickFillPayment({required String target}) {
    final bool hasItemReturns = _withReturns && _currentDelivery.items.isNotEmpty && _selectedReturnProductIds.isNotEmpty;
    final double targetAmount = hasItemReturns
        ? (originalOrderTotal - calculatedItemsReturnAmount).clamp(0.0, double.infinity)
        : effectiveOrderAmount;
    String formattedOrder = Helperfunctions.formatDoubleAmountForField(targetAmount);

    setState(() {
      txtCashAmount.text = target == 'cash' ? formattedOrder : '';
      txtOnlineAmount.text = target == 'online' ? formattedOrder : '';
      txtCreditAmount.text = target == 'credit' ? formattedOrder : '';
      computeDiscrepancy();
    });
  }

  Widget _buildPaymentSummary() {
    final colorScheme = Theme.of(context).colorScheme;
    final bool hasItemReturns = _withReturns && _currentDelivery.items.isNotEmpty && _selectedReturnProductIds.isNotEmpty;
    final double targetOrderAmt = hasItemReturns
        ? (originalOrderTotal - calculatedItemsReturnAmount).clamp(0.0, double.infinity)
        : effectiveOrderAmount;
    final double totalCollected = _controller.computeTotalCollected(
      cash: txtCashAmount.text,
      online: txtOnlineAmount.text,
      credit: txtCreditAmount.text,
      returnAmount: '0',
      withItemReturns: hasItemReturns,
    );
    double orderAmt = targetOrderAmt;
    bool isBalanced = discrepancy.abs() < 0.005;
    bool isOver = discrepancy >= 0.005;

    Color badgeColor = isBalanced ? Colors.green : (isOver ? Colors.orange.shade800 : Colors.red.shade700);
    Color bgColor = isBalanced
        ? Colors.green.withValues(alpha: 0.08)
        : (isOver ? Colors.orange.withValues(alpha: 0.08) : Colors.red.withValues(alpha: 0.08));
    Color borderColor = isBalanced ? Colors.green.shade300 : (isOver ? Colors.orange.shade300 : Colors.red.shade300);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        children: [
          // Live Calculation Grid
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Accounted', style: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      Helperfunctions.formatDoubleAmountForDisplay(totalCollected),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17.5),
                    ),
                  ],
                ),
              ),
              Container(height: 34, width: 1, color: colorScheme.outlineVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasItemReturns ? 'Target (Delivered)' : 'Target Order Amount',
                      style: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(Helperfunctions.formatDoubleAmountForDisplay(orderAmt), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17.5)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          // Status Badge with explanation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(isBalanced ? Icons.check_circle : (isOver ? Icons.error_outline : Icons.warning_amber_rounded), size: 22, color: badgeColor),
                  const SizedBox(width: 6),
                  Text(
                    isBalanced
                        ? 'Balanced'
                        : (isOver
                              ? 'Over by ${Helperfunctions.formatDoubleAmountForDisplay(discrepancy.abs())}'
                              : 'Short by ${Helperfunctions.formatDoubleAmountForDisplay(discrepancy.abs())}'),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: badgeColor),
                  ),
                ],
              ),
              if (!isBalanced)
                Text(
                  isOver ? 'Overpaid' : 'Unsettled',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: badgeColor),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRemarksCard() {
    return _buildSectionCard(
      title: 'Remarks & Return Details',
      icon: Icons.note_alt_outlined,
      child: _buildTextAreaField(
        label: 'Remarks',
        controller: txtRemarks,
        prefixIcon: Icons.notes_outlined,
        minLines: 3,
        isEnabled: !isSalesmanLocked,
        isRequired:
            (dropdownStatus.text == DeliveryStatus.returned || (dropdownStatus.text == DeliveryStatus.delivered && (_withReturns && _selectedReturnProductIds.isNotEmpty))),
      ),
    );
  }

  Widget _buildTextAreaField({
    required String label,
    required TextEditingController controller,
    required IconData prefixIcon,
    int minLines = 3,
    bool isRequired = true,
    bool isEnabled = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      enabled: isEnabled,
      controller: controller,
      keyboardType: TextInputType.multiline,
      minLines: minLines,
      maxLines: null,
      style: const TextStyle(fontSize: 15.5),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
        alignLabelWithHint: true,
        prefixIcon: Icon(prefixIcon, size: 22, color: colorScheme.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      autovalidateMode: AutovalidateMode.onUnfocus,
      validator: (value) {
        if (isRequired && (value == null || value.trim().isEmpty)) return '$label should not be blank';
        return null;
      },
    );
  }

  Widget _buildSmsCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildSectionCard(
      title: 'SMS Notification',
      icon: Icons.sms_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Send Text Message?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
              subtitle: const Text('Notify store contact about the pending order', style: TextStyle(fontSize: 13.5)),
              value: sendText,
              onChanged: isSalesmanLocked ? null : (val) => setState(() => sendText = val),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: sendText
                ? Padding(
                    padding: const EdgeInsets.only(top: 14.0),
                    child: _buildTextAreaField(
                      label: 'Text Message',
                      controller: txtSMS,
                      prefixIcon: Icons.message_outlined,
                      minLines: 4,
                      isEnabled: !isSalesmanLocked,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyBottomBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1.0)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
        ),
        child: widget.deliveryID.isEmpty
            ? FilledButton.icon(
                onPressed: isSalesmanLocked
                    ? null
                    : () async {
                        final confirmed = await ShowMessage.confirm(
                          context,
                          title: ConfirmTitle.save,
                          message: ConfirmMessage.save,
                          icon: Icons.save_outlined,
                          confirmText: 'Save',
                        );
                        if (confirmed) onSave();
                      },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(isSalesmanLocked ? Icons.lock_outline : Icons.save_outlined),
                label: Text(
                  isSalesmanLocked ? 'Locked (Breakdown Recorded)' : 'Save Delivery Record',
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                ),
              )
            : Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isLocked
                          ? null
                          : () async {
                              final confirmed = await ShowMessage.confirm(
                                context,
                                title: ConfirmTitle.update,
                                message: ConfirmMessage.update,
                                icon: Icons.check_circle_outline,
                                confirmText: 'Update',
                              );
                              if (confirmed) onUpdate();
                            },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 50.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(isLocked ? Icons.lock_outline : Icons.check_circle_outline, size: 22),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _currentDelivery.isReturnApprovedByDealer
                              ? 'Locked (Return Approved)'
                              : (_currentDelivery.isInventorySettled
                                  ? 'Locked (Inventory Settled)'
                                  : (isLocked
                                      ? 'Locked (Breakdown Verified)'
                                      : (isDealerLateReconciliation
                                          ? 'Reconcile & Update'
                                          : 'Update Delivery'))),
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPlacementCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final placedCount = listPlacement.where((placement) => placement.isPlaced).length;
    final unplacedCount = listPlacement.where((placement) => !placement.isPlaced).length;

    return _buildSectionCard(
      title: 'Placement Checklist',
      icon: Icons.inventory_2_outlined,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (placedCount == 12 ? colorScheme.primary : colorScheme.onSurfaceVariant).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$placedCount/12 placed',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: placedCount == 12 ? colorScheme.primary : colorScheme.onSurfaceVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: listPlacement.isEmpty ? 0 : placedCount / listPlacement.length,
                      minHeight: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      color: placedCount == 12 ? Colors.green : colorScheme.primary,
                    ),
                  ),
                ),
                if (unplacedCount > 0) ...[
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: isSalesmanLocked
                        ? null
                        : () {
                            setState(() {
                              for (var placement in listPlacement) {
                                placement.isPlaced = true;
                              }
                            });
                          },
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    ),
                    icon: const Icon(Icons.done_all_rounded, size: 16),
                    label: const Text('Place All', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: listPlacement.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            itemBuilder: (context, index) {
              final item = listPlacement[index];
              final isPlaced = item.isPlaced;
              final isLocked = item.isPlacedFromDB;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: isLocked
                      ? colorScheme.primary.withValues(alpha: 0.08)
                      : (isPlaced ? colorScheme.primary.withValues(alpha: 0.04) : Colors.transparent),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isLocked
                        ? colorScheme.primary.withValues(alpha: 0.35)
                        : (isPlaced ? colorScheme.primary.withValues(alpha: 0.2) : Colors.transparent),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  onTap: isSalesmanLocked
                      ? null
                      : (isLocked
                            ? () => ShowMessage.error(context, '${item.itemName} is already placed for this month.')
                            : () => setState(() => item.isPlaced = !item.isPlaced)),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      item.itemImagePath,
                      width: 60,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 60,
                        height: 50,
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.image_outlined, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  title: Text(item.itemName, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    isLocked ? 'Locked (saved in DB)' : (isPlaced ? 'Placed and ready' : 'Pending placement'),
                    style: TextStyle(fontSize: 13, color: isPlaced ? colorScheme.primary : colorScheme.onSurfaceVariant),
                  ),
                  trailing: isLocked
                      ? Icon(Icons.lock_outline, size: 20, color: colorScheme.primary)
                      : Checkbox(
                          value: isPlaced,
                          activeColor: colorScheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          onChanged: isSalesmanLocked
                              ? null
                              : (value) {
                                  setState(() {
                                    item.isPlaced = value ?? false;
                                  });
                                },
                        ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDelivered = dropdownStatus.text == DeliveryStatus.delivered;
    bool isReturned = dropdownStatus.text == DeliveryStatus.returned;
    bool showRemarks = isReturned || (isDelivered && (_withReturns && _selectedReturnProductIds.isNotEmpty));

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Delivery',
        subtitle: widget.deliveryID.isEmpty ? 'New Record' : _currentDelivery.storeName,
        actions: [
          if (_currentDelivery.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.receipt_long_rounded, color: Colors.white),
              tooltip: 'Digital Receipt & Thermal Print',
              onPressed: () => DigitalReceiptDialog.show(context, delivery: _currentDelivery, deliveryId: widget.deliveryID, proceedLabel: 'Close'),
            ),
        ],
      ),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: _formkey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                if (isLocked)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _currentDelivery.isReturnApprovedByDealer
                          ? Colors.green.shade50
                          : (_currentDelivery.isInventorySettled || isDayVerified ? Colors.red.shade50 : Colors.amber.shade50),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _currentDelivery.isReturnApprovedByDealer
                            ? Colors.green.shade300
                            : (_currentDelivery.isInventorySettled || isDayVerified ? Colors.red.shade300 : Colors.amber.shade300),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _currentDelivery.isReturnApprovedByDealer ? Icons.check_circle_outline : Icons.lock_outline,
                          color: _currentDelivery.isReturnApprovedByDealer
                              ? Colors.green.shade900
                              : (_currentDelivery.isInventorySettled || isDayVerified ? Colors.red.shade900 : Colors.amber.shade900),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _currentDelivery.isReturnApprovedByDealer
                                ? 'Locked: This return order has been approved by the dealer. Returned items have been moved into Current Stock and this record cannot be modified or deleted.'
                                : (_currentDelivery.isInventorySettled
                                    ? 'Locked: This delivery order has already been verified and settled into inventory.'
                                    : (isDayVerified
                                        ? 'Locked: The dealer has verified the daily cash breakdown and delivery records for this day are locked for salesmen.'
                                        : 'View-Only: A cash breakdown for this date has already been recorded. Salesmen cannot edit delivery records for this day.')),
                            style: TextStyle(
                              fontSize: 14,
                              color: _currentDelivery.isReturnApprovedByDealer
                                  ? Colors.green.shade900
                                  : (_currentDelivery.isInventorySettled || isDayVerified ? Colors.red.shade900 : Colors.amber.shade900),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isDealerLateReconciliation)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.amber.shade400,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.amber.shade900,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Late Delivery: This date\'s cash breakdown has already been verified. As a dealer, you can update or reschedule this transaction; saving as Delivered or Returned will automatically reconcile inventory.',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_currentDelivery.isReturnIncoming || _currentDelivery.hasReturnedItems || _currentDelivery.returnAmount > 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.assignment_return_outlined,
                          color: Color(0xFF0284C7),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Pending Dealer Return Approval',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0284C7),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Returned items (${Helperfunctions.formatDoubleAmountForDisplay(_currentDelivery.returnAmount > 0 ? _currentDelivery.returnAmount : _currentDelivery.orderAmount)}) are tracked as Incoming Stock until approved into Current Stock by the dealer.',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF0C4A6E)),
                              ),
                            ],
                          ),
                        ),
                        if (isDealer) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => Helperfunctions.navigateTo(
                              context,
                              ReturnPage(recID: widget.deliveryID, delivery: _currentDelivery),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF0284C7),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            child: const Text('Review', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                  ),

                if (_currentDelivery.transactionStatus == DeliveryStatus.pendingPicklist && widget.deliveryID.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.fact_check_outlined, color: Color(0xFF7C3AED), size: 24),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('This order is Booked (Awaiting Picklist).', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        FilledButton.tonal(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PicklistPage(deliveryID: widget.deliveryID, delivery: _currentDelivery),
                              ),
                            );
                          },
                          child: const Text('Open Picklist', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),

                // 1. Order & Store Info Card
                _buildOrderAndStoreCard(),

                // 2. Proof of Delivery Card for reviewing uploaded photo (accessible to all users)
                if (widget.deliveryID.isNotEmpty) _buildProofOfDeliveryCard(),

                // 3. Itemized Returns Section (when Delivered and delivery has items)
                if (widget.deliveryID.isNotEmpty && isDelivered && _currentDelivery.items.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: _buildWithReturnsSection(),
                  ),

                // 3.1 Bad Orders from Store Section
                if (widget.deliveryID.isNotEmpty && dropdownHapiStore.text.isNotEmpty)
                  _buildBadOrdersSection(),

                // 4. Payment Breakdown Card (Animated for Delivered status)
                if (widget.deliveryID.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: isDelivered ? _buildPaymentBreakdownCard() : const SizedBox.shrink(),
                  ),

                // 5. Remarks Card (Animated for Returned or Delivered with return amount)
                if (widget.deliveryID.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: showRemarks ? _buildRemarksCard() : const SizedBox.shrink(),
                  ),

                // 6. Placement Card
                if (widget.deliveryID.isEmpty && dropdownHapiStore.text.isNotEmpty) _buildPlacementCard(),

                // 7. SMS Notification Card (when creating new delivery)
                if (widget.deliveryID.isEmpty) _buildSmsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemizedReturnsBottomSheet extends StatefulWidget {
  final List<OrderItem> items;
  final Set<String> initialSelectedIds;
  final Map<String, int> initialQuantities;
  final bool isLocked;
  final void Function(Set<String> selectedIds, Map<String, int> quantities) onApply;

  const _ItemizedReturnsBottomSheet({
    required this.items,
    required this.initialSelectedIds,
    required this.initialQuantities,
    required this.isLocked,
    required this.onApply,
  });

  @override
  State<_ItemizedReturnsBottomSheet> createState() => _ItemizedReturnsBottomSheetState();
}

class _ItemizedReturnsBottomSheetState extends State<_ItemizedReturnsBottomSheet> {
  late Set<String> _selectedIds;
  late Map<String, int> _quantities;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.initialSelectedIds);
    _quantities = Map<String, int>.from(widget.initialQuantities);

    // Initialize quantities: if previously saved with returnedQuantity > 0, retain it.
    // Otherwise, default return quantity is 0.
    for (final item in widget.items) {
      if (!_quantities.containsKey(item.productId)) {
        if (item.returnedQuantity > 0) {
          _quantities[item.productId] = item.returnedQuantity;
          _selectedIds.add(item.productId);
        } else {
          _quantities[item.productId] = 0;
        }
      } else if ((_quantities[item.productId] ?? 0) <= 0) {
        _selectedIds.remove(item.productId);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _increment(OrderItem item) {
    if (widget.isLocked) return;
    final current = _quantities[item.productId] ?? 0;
    if (current < item.pickedQuantity) {
      setState(() {
        final newQty = current + 1;
        _quantities[item.productId] = newQty;
        _selectedIds.add(item.productId);
      });
    }
  }

  void _decrement(OrderItem item) {
    if (widget.isLocked) return;
    final current = _quantities[item.productId] ?? 0;
    if (current > 1) {
      setState(() {
        _quantities[item.productId] = current - 1;
        _selectedIds.add(item.productId);
      });
    } else if (current == 1) {
      setState(() {
        _quantities[item.productId] = 0;
        _selectedIds.remove(item.productId);
      });
    }
  }

  void _setMax(OrderItem item) {
    if (widget.isLocked) return;
    setState(() {
      _quantities[item.productId] = item.pickedQuantity;
      _selectedIds.add(item.productId);
    });
  }

  void _selectAllMax() {
    if (widget.isLocked) return;
    setState(() {
      for (final item in widget.items) {
        _selectedIds.add(item.productId);
        _quantities[item.productId] = item.pickedQuantity;
      }
    });
  }

  void _clearAll() {
    if (widget.isLocked) return;
    setState(() {
      _selectedIds.clear();
      for (final item in widget.items) {
        _quantities[item.productId] = 0;
      }
    });
  }

  double get _totalReturnAmount {
    double total = 0.0;
    for (final item in widget.items) {
      if (_selectedIds.contains(item.productId)) {
        final qty = _quantities[item.productId] ?? 0;
        total += qty * item.sellingPrice;
      }
    }
    return total;
  }

  int get _totalReturnUnits {
    int units = 0;
    for (final item in widget.items) {
      if (_selectedIds.contains(item.productId)) {
        units += _quantities[item.productId] ?? 0;
      }
    }
    return units;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filteredItems = widget.items.where((i) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return i.productName.toLowerCase().contains(q) || i.category.toLowerCase().contains(q);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 44,
            height: 4.5,
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(3),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.assignment_return_outlined, color: Colors.red.shade700, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Itemized Returns',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${widget.items.length} items ordered • ${_selectedIds.length} returning',
                        style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Search & Quick Action Filters
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search SKU or Category...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
                if (!widget.isLocked) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ActionChip(
                        avatar: Icon(Icons.done_all_rounded, size: 16, color: colorScheme.primary),
                        label: const Text('Return All Max', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        onPressed: _selectAllMax,
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: Icon(Icons.restart_alt_rounded, size: 16, color: colorScheme.error),
                        label: Text('Clear All', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: colorScheme.error)),
                        onPressed: _clearAll,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Product List
          Expanded(
            child: filteredItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        Text(
                          'No products found matching "$_searchQuery"',
                          style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: filteredItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      final isSelected = _selectedIds.contains(item.productId);
                      final returnQty = _quantities[item.productId] ?? 0;
                      final maxQty = item.pickedQuantity;
                      final lineTotal = returnQty * item.sellingPrice;

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.red.shade50.withValues(alpha: 0.6) : colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? Colors.red.shade300 : colorScheme.outlineVariant.withValues(alpha: 0.6),
                            width: isSelected ? 1.4 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Thumbnail
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: item.imageUrl.isNotEmpty
                                      ? Image.network(
                                          item.imageUrl,
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => Container(
                                            width: 44,
                                            height: 44,
                                            color: colorScheme.surfaceContainerHighest,
                                            child: Icon(Icons.icecream_outlined, color: colorScheme.onSurfaceVariant),
                                          ),
                                        )
                                      : Container(
                                          width: 44,
                                          height: 44,
                                          color: colorScheme.surfaceContainerHighest,
                                          child: Icon(Icons.icecream_outlined, color: colorScheme.onSurfaceVariant),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                // Title & Pricing
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.productName,
                                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${Helperfunctions.formatDoubleAmountForDisplay(item.sellingPrice)} each • Picked: $maxQty pcs',
                                        style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            // Stepper and Subtotal
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.remove, size: 18),
                                            visualDensity: VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                                            onPressed: (widget.isLocked || returnQty == 0) ? null : () => _decrement(item),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            child: Text(
                                              '$returnQty',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: returnQty > 0 ? Colors.red.shade700 : colorScheme.onSurface,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.add, size: 18),
                                            visualDensity: VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                                            onPressed: (widget.isLocked || returnQty >= maxQty) ? null : () => _increment(item),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (!widget.isLocked && returnQty < maxQty)
                                      InkWell(
                                        onTap: () => _setMax(item),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text('All ($maxQty)', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Return Value',
                                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                    ),
                                    Text(
                                      Helperfunctions.formatDoubleAmountForDisplay(lineTotal),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: lineTotal > 0 ? Colors.red.shade700 : colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Sticky Bottom Bar
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6))),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, -2)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Returns ($_totalReturnUnits units)',
                          style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                        ),
                        Text(
                          Helperfunctions.formatDoubleAmountForDisplay(_totalReturnAmount),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _totalReturnAmount > 0 ? Colors.red.shade700 : colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: () {
                      final validSelectedIds = _selectedIds.where((id) => (_quantities[id] ?? 0) > 0).toSet();
                      widget.onApply(validSelectedIds, _quantities);
                      Navigator.pop(context);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Apply Returns', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet modal enabling salesmen to record itemized bad orders
/// with photo capture and notes during delivery.
class _DeliveryBadOrderBottomSheet extends StatefulWidget {
  final String storeName;
  final DateTime deliveryDate;
  final VoidCallback onBadOrderSaved;

  const _DeliveryBadOrderBottomSheet({
    required this.storeName,
    required this.deliveryDate,
    required this.onBadOrderSaved,
  });

  @override
  State<_DeliveryBadOrderBottomSheet> createState() => _DeliveryBadOrderBottomSheetState();
}

class _DeliveryBadOrderBottomSheetState extends State<_DeliveryBadOrderBottomSheet> {
  final SelectaProductController _productController = SelectaProductController();
  final BadOrderController _boController = BadOrderController();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final Map<String, int> _quantities = {};
  File? _imageFile;
  String _searchQuery = '';
  String _categoryFilter = 'All'; // 'All', 'By Piece', 'By Case'
  bool _isSubmitting = false;

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
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

  int get _totalUnits {
    return _quantities.values.fold<int>(0, (acc, q) => acc + q);
  }

  double _computeTotalAmount(List<SelectaProduct> products) {
    double total = 0.0;
    for (final p in products) {
      final q = _quantities[p.id] ?? 0;
      if (q > 0) {
        total += q * p.boPricePerPiece;
      }
    }
    return total;
  }

  Future<void> _submit(List<SelectaProduct> allProducts) async {
    final selectedItems = <BadOrderItem>[];
    for (final p in allProducts) {
      final q = _quantities[p.id] ?? 0;
      if (q > 0) {
        if (p.category == 'By Case' && !p.isBoPriceConfigured) {
          ShowMessage.error(
            context,
            'Cannot submit: "${p.productName}" is By Case and has no B.O. price configured by dealer.',
          );
          return;
        }
        selectedItems.add(BadOrderItem(
          productId: p.id,
          productName: p.productName,
          category: p.category,
          quantity: q,
          pricePerPiece: p.boPricePerPiece,
          subtotal: q * p.boPricePerPiece,
          imageUrl: p.imageUrl,
        ));
      }
    }

    if (selectedItems.isEmpty) {
      ShowMessage.error(context, 'Please specify quantities for at least one bad order product.');
      return;
    }

    if (_imageFile == null) {
      ShowMessage.error(context, 'A photo of the bad order is required.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // 1. Upload photo to Firebase Storage
      final uploadedUrl = await Helperfunctions.saveImage(context, _imageFile!);

      // 2. Create Bad Order record
      await _boController.createBadOrder(
        hapistore: widget.storeName,
        selectedDate: widget.deliveryDate,
        imagePath: uploadedUrl,
        items: selectedItems,
        notes: _notesController.text.trim(),
        page: AppPages.delivery,
      );

      if (mounted) {
        ShowMessage.success(context, 'Bad order record successfully submitted and recorded!');
        widget.onBadOrderSaved();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to save bad order record: $e');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Record Bad Order: ${widget.storeName}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Pullout damaged or expired Selecta products',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Search and Category Filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(
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
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('All', style: TextStyle(fontSize: 11.5)),
                  selected: _categoryFilter == 'All',
                  onSelected: (_) => setState(() => _categoryFilter = 'All'),
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                ),
                const SizedBox(width: 4),
                ChoiceChip(
                  label: const Text('Piece', style: TextStyle(fontSize: 11.5)),
                  selected: _categoryFilter == 'By Piece',
                  onSelected: (_) => setState(() => _categoryFilter = 'By Piece'),
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                ),
                const SizedBox(width: 4),
                ChoiceChip(
                  label: const Text('Case', style: TextStyle(fontSize: 11.5)),
                  selected: _categoryFilter == 'By Case',
                  onSelected: (_) => setState(() => _categoryFilter = 'By Case'),
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                ),
              ],
            ),
          ),

          const Divider(height: 12),

          // Stream of Selecta products
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

                return Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        children: [
                          // 1. Photo Picker Card (Required)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12, top: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _imageFile == null
                                  ? Colors.red.shade50.withValues(alpha: 0.5)
                                  : Colors.green.shade50.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _imageFile == null ? Colors.red.shade300 : Colors.green.shade400,
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
                                      color: _imageFile == null ? Colors.red.shade800 : Colors.green.shade800,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Incident Photo (Required)',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: _imageFile == null ? Colors.red.shade800 : Colors.green.shade800,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (_imageFile != null)
                                      TextButton.icon(
                                        onPressed: () => setState(() => _imageFile = null),
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
                                      height: 140,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
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

                          // 2. Remarks / Notes TextField
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: TextField(
                              controller: _notesController,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: 'Notes / Remarks (Optional)',
                                hintText: 'Reason: expired, melted, damaged packaging...',
                                prefixIcon: const Icon(Icons.edit_note, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),

                          const Text(
                            'Select Products & Quantities',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 6),

                          if (filteredProducts.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Center(child: Text('No active Selecta products found matching filter.')),
                            )
                          else
                            ...filteredProducts.map((product) {
                              final qty = _quantities[product.id] ?? 0;
                              final isCase = product.category == 'By Case';
                              final hasValidPrice = product.isBoPriceConfigured;
                              final unitPrice = product.boPricePerPiece;
                              final subtotal = qty * unitPrice;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: qty > 0
                                        ? colorScheme.primary
                                        : colorScheme.outlineVariant.withValues(alpha: 0.5),
                                    width: qty > 0 ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(10.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // Image
                                      Container(
                                        width: 40,
                                        height: 40,
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
                                      // Product Info
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              product.productName,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
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
                                                const SizedBox(width: 6),
                                                if (!hasValidPrice)
                                                  const Text(
                                                    '⚠️ Price not set by dealer',
                                                    style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold),
                                                  )
                                                else
                                                  Text(
                                                    '@ ${Helperfunctions.formatDoubleAmountForDisplay(unitPrice)} / pc',
                                                    style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                                                  ),
                                              ],
                                            ),
                                            if (qty > 0) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                'Subtotal: ${Helperfunctions.formatDoubleAmountForDisplay(subtotal)}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: colorScheme.primary,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      // Stepper
                                      if (!hasValidPrice)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text('Blocked', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                                        )
                                      else
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline, size: 22),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              color: qty > 0 ? Colors.red.shade700 : Colors.grey.shade400,
                                              onPressed: qty > 0
                                                  ? () => setState(() => _quantities[product.id] = qty - 1)
                                                  : null,
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                              child: Text(
                                                '$qty',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.add_circle_outline, size: 22),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              color: colorScheme.primary,
                                              onPressed: () => setState(() => _quantities[product.id] = qty + 1),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),

                    // Sticky Bottom Bar
                    SafeArea(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, -2))],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Total: $_totalUnits pcs',
                                    style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                                  ),
                                  Text(
                                    Helperfunctions.formatDoubleAmountForDisplay(_computeTotalAmount(allProducts)),
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: _isSubmitting ? null : () => _submit(allProducts),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.orange.shade800,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: _isSubmitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.check, size: 18),
                              label: Text(
                                _isSubmitting ? 'Submitting...' : 'Save Bad Order',
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
        ],
      ),
    );
  }
}
